import os
import socket
import mysql.connector
import uuid
import logging
import random
import time

from db.base import STATUS_PENDING, STATUS_RUNNING, STATUS_DONE, STATUS_SUPERSEDED


MYSQL_ERR_LOCK_WAIT_TIMEOUT = 1205
MYSQL_ERR_DEADLOCK = 1213


class MySqlAdapter:
    RETRYABLE_ERRNOS = {
        MYSQL_ERR_LOCK_WAIT_TIMEOUT,
        MYSQL_ERR_DEADLOCK,
    }

    def __init__(
        self,
        config,
        claim_strategy="simple",
        retry_attempts=3,
        retry_base_delay_seconds=0.1,
        retry_max_delay_seconds=2,
    ):
        self.conn = mysql.connector.connect(**config)
        self.conn.autocommit = False
        self.claim_strategy = claim_strategy
        self.worker_id = f"{socket.gethostname()}-{os.getpid()}"
        self.retry_attempts = max(1, retry_attempts)
        self.retry_base_delay_seconds = max(0, retry_base_delay_seconds)
        self.retry_max_delay_seconds = max(0, retry_max_delay_seconds)


    def log_config(self):
        logging.info(
            "[MySQL Adapter] claim_strategy=%s worker_id=%s db_retry_attempts=%s",
            self.claim_strategy,
            self.worker_id,
            self.retry_attempts,
        )


    def is_retryable_error(self, error):
        return (
            isinstance(error, mysql.connector.Error)
            and error.errno in self.RETRYABLE_ERRNOS
        )


    def retry_delay(self, attempt):
        if self.retry_base_delay_seconds <= 0:
            return 0

        delay = self.retry_base_delay_seconds * (2 ** (attempt - 1))
        delay = min(delay, self.retry_max_delay_seconds)
        jitter = random.uniform(0, delay * 0.25)
        return delay + jitter


    def with_db_retry(self, operation_name, operation):
        for attempt in range(1, self.retry_attempts + 1):
            try:
                return operation()
            except Exception as error:
                if not self.is_retryable_error(error) or attempt >= self.retry_attempts:
                    raise

                delay = self.retry_delay(attempt)
                logging.warning(
                    "Retryable MySQL error during %s: errno=%s attempt=%s/%s delay=%.3fs",
                    operation_name,
                    getattr(error, "errno", None),
                    attempt,
                    self.retry_attempts,
                    delay,
                )

                if delay > 0:
                    time.sleep(delay)


    def fetch_jobs_expanded_once(self, limit=100):
        """
        Advanced claim strategy.

        1. Claim a seed batch of pending jobs.
        2. Expand the claim to include all other pending jobs
        for the same (entity_type, entity_id).
        3. Return all jobs belonging to this claim_id.
        """

        claim_id = str(uuid.uuid4())
        cur = self.conn.cursor(dictionary=True)

        try:
            # 1. Claim seed batch
            cur.execute("""
                UPDATE search_index_jobs
                SET status = %s,
                    worker_id = %s,
                    claim_id = %s,
                    claimed_at = NOW(),
                    started_at = NOW()
                WHERE job_id IN (
                    SELECT job_id
                    FROM (
                        SELECT job_id
                        FROM search_index_jobs
                        WHERE (
                            status = %s
                            OR (status = %s AND claim_id IS NULL)
                        )
                        AND available_at <= NOW()
                        ORDER BY priority DESC, created_at ASC, job_id ASC
                        LIMIT %s
                        FOR UPDATE SKIP LOCKED
                    ) seed
                )
                AND (
                    status = %s
                    OR (status = %s AND claim_id IS NULL)
                )
            """, (
                STATUS_RUNNING,
                self.worker_id,
                claim_id,
                STATUS_PENDING,
                STATUS_RUNNING,
                limit,
                STATUS_PENDING,
                STATUS_RUNNING,
            ))

            if cur.rowcount == 0:
                self.conn.commit()
                return []

            # 2. Expand claim to all pending jobs for same entities
            #    Deadlock-friendlier version:
            #    - read seed entity keys
            #    - lock matching pending job_ids
            #    - update by primary key job_id

            cur.execute("""
                SELECT DISTINCT entity_type, entity_id
                FROM search_index_jobs
                WHERE claim_id = %s
            """, (claim_id,))

            entity_rows = cur.fetchall()

            extra_job_ids = []

            for entity in entity_rows:
                cur.execute("""
                    SELECT job_id
                    FROM search_index_jobs
                    WHERE status = %s
                    AND available_at <= NOW()
                    AND entity_type = %s
                    AND entity_id = %s
                    ORDER BY job_id ASC
                    FOR UPDATE SKIP LOCKED
                """, (
                    STATUS_PENDING,
                    entity["entity_type"],
                    entity["entity_id"],
                ))

                extra_job_ids.extend(r["job_id"] for r in cur.fetchall())

            if extra_job_ids:
                extra_job_ids = sorted(extra_job_ids)
                placeholders = ",".join(["%s"] * len(extra_job_ids))

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        worker_id = %s,
                        claim_id = %s,
                        claimed_at = NOW(),
                        started_at = NOW()
                    WHERE job_id IN ({placeholders})
                    AND (
                        status = %s
                        OR (status = %s AND claim_id IS NULL)
                    )
                    """,
                    [STATUS_RUNNING, self.worker_id, claim_id] + extra_job_ids + [STATUS_PENDING, STATUS_RUNNING]
                )

            # 3. Fetch all claimed jobs
            cur.execute("""
                SELECT job_id, entity_type, entity_id, action,
                    created_at, priority, source, claim_id
                FROM search_index_jobs
                WHERE claim_id = %s
                ORDER BY priority DESC, created_at ASC, job_id ASC
            """, (claim_id,))

            rows = cur.fetchall()
            self.conn.commit()

            return rows

        except Exception:
            self.conn.rollback()
            raise


    def fetch_jobs_simple_once(self, limit=100):
        claim_id = str(uuid.uuid4())
        cur = self.conn.cursor(dictionary=True)
        try:
            cur.execute("""
                SELECT job_id, entity_type, entity_id, action, created_at, priority, source
                FROM search_index_jobs
                WHERE (
                    status = %s
                    OR (status = %s AND claim_id IS NULL)
                )
                AND available_at <= NOW()                        
                ORDER BY priority DESC, created_at ASC, job_id ASC
                LIMIT %s
                FOR UPDATE SKIP LOCKED
            """, (STATUS_PENDING, STATUS_RUNNING, limit))

            rows = cur.fetchall()

            if not rows:
                self.conn.commit()
                return []

            job_ids = [r["job_id"] for r in rows]

            placeholders = ",".join(["%s"] * len(job_ids))

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s,
                    worker_id = %s,
                    claim_id = %s,
                    started_at = NOW(),
                    claimed_at = NOW()
                WHERE job_id IN ({placeholders})
                AND (
                    status = %s
                    OR (status = %s AND claim_id IS NULL)
                )
                """,
                [STATUS_RUNNING, self.worker_id, claim_id] + job_ids + [STATUS_PENDING, STATUS_RUNNING]
            )

            for row in rows:
                row["claim_id"] = claim_id

            self.conn.commit()
            return rows

        except Exception:
            self.conn.rollback()
            raise


    def fetch_jobs(self, limit=100):
        if self.claim_strategy == "expanded":
            return self.with_db_retry(
                "fetch_jobs_expanded",
                lambda: self.fetch_jobs_expanded_once(limit),
            )

        return self.with_db_retry(
            "fetch_jobs_simple",
            lambda: self.fetch_jobs_simple_once(limit),
        )


    def mark_superseded(self, job_ids):
        if not job_ids:
            return

        cur = self.conn.cursor()
        try:
            placeholders = ",".join(["%s"] * len(job_ids))

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s,
                    finished_at = NOW()
                WHERE job_id IN ({placeholders})
                """,
                [STATUS_SUPERSEDED] + job_ids
            )

            self.conn.commit()
        
        except Exception:
            self.conn.rollback()
            raise            


    def mark_superseded_by_claim(self, claim_id, winner_ids):
        if not claim_id:
            return

        cur = self.conn.cursor()

        try:
            if winner_ids:
                placeholders = ",".join(["%s"] * len(winner_ids))

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE claim_id = %s
                    AND status = %s
                    AND job_id NOT IN ({placeholders})
                    """,
                    [STATUS_SUPERSEDED, claim_id, STATUS_RUNNING] + winner_ids
                )
            else:
                cur.execute("""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE claim_id = %s
                    AND status = %s
                """, (STATUS_SUPERSEDED, claim_id, STATUS_RUNNING))

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def mark_done(self, job_ids):
        if not job_ids:
            return

        cur = self.conn.cursor()
        try:
            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s, finished_at = NOW()
                WHERE job_id IN ({",".join(["%s"] * len(job_ids))})
                """,
                [STATUS_DONE] + job_ids
            )
            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise                


    def mark_done_by_claim(self, claim_id, winner_ids):
        if not claim_id or not winner_ids:
            return

        cur = self.conn.cursor()
        placeholders = ",".join(["%s"] * len(winner_ids))

        try:
            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s,
                    finished_at = NOW()
                WHERE claim_id = %s
                AND status = %s
                AND job_id IN ({placeholders})
                """,
                [STATUS_DONE, claim_id, STATUS_RUNNING] + winner_ids
            )

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def finalize_batch_by_claim(self, claim_id, winner_ids):
        if not claim_id:
            return

        cur = self.conn.cursor()

        try:
            if winner_ids:
                placeholders = ",".join(["%s"] * len(winner_ids))

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE claim_id = %s
                    AND status = %s
                    AND job_id IN ({placeholders})
                    """,
                    [STATUS_DONE, claim_id, STATUS_RUNNING] + winner_ids
                )

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE claim_id = %s
                    AND status = %s
                    AND job_id NOT IN ({placeholders})
                    """,
                    [STATUS_SUPERSEDED, claim_id, STATUS_RUNNING] + winner_ids
                )
            else:
                cur.execute("""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE claim_id = %s
                    AND status = %s
                """, (STATUS_SUPERSEDED, claim_id, STATUS_RUNNING))

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def finalize_batch_by_ids(self, job_ids, winner_ids):
        if not job_ids:
            return

        winner_ids = set(winner_ids)
        superseded_ids = sorted(set(job_ids) - winner_ids)
        winner_ids = sorted(winner_ids)

        cur = self.conn.cursor()

        try:
            if winner_ids:
                placeholders = ",".join(["%s"] * len(winner_ids))

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE job_id IN ({placeholders})
                    AND status = %s
                    """,
                    [STATUS_DONE] + winner_ids + [STATUS_RUNNING]
                )

            if superseded_ids:
                placeholders = ",".join(["%s"] * len(superseded_ids))

                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE job_id IN ({placeholders})
                    AND status = %s
                    """,
                    [STATUS_SUPERSEDED] + superseded_ids + [STATUS_RUNNING]
                )

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def release_failed_batch_by_ids(self, job_ids, error_text, delay_seconds=0):
        if not job_ids:
            return 0

        cur = self.conn.cursor()
        placeholders = ",".join(["%s"] * len(job_ids))

        try:
            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET available_at = NOW() + INTERVAL %s SECOND,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE job_id IN ({placeholders})
                AND status = %s
                """,
                [delay_seconds, error_text[:1000]] + job_ids + [STATUS_RUNNING]
            )

            released_count = cur.rowcount
            self.conn.commit()
            return released_count

        except Exception:
            self.conn.rollback()
            raise


    def release_failed_batch_by_claim(self, claim_id, error_text, delay_seconds=0):
        if not claim_id:
            return 0

        cur = self.conn.cursor()

        try:
            cur.execute("""
                UPDATE search_index_jobs
                SET available_at = NOW() + INTERVAL %s SECOND,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE claim_id = %s
                AND status = %s
            """, (
                delay_seconds,
                error_text[:1000],
                claim_id,
                STATUS_RUNNING,
            ))

            released_count = cur.rowcount
            self.conn.commit()
            return released_count

        except Exception:
            self.conn.rollback()
            raise


    def release_failed_batch_once(self, jobs, error_text, delay_seconds=0):
        if not jobs:
            return 0

        raw_claim_ids = {j.get("claim_id") for j in jobs}
        claim_ids = {claim_id for claim_id in raw_claim_ids if claim_id}

        if len(claim_ids) > 1 or (claim_ids and None in raw_claim_ids):
            raise RuntimeError("Batch contains multiple claim_id values")

        if claim_ids:
            claim_id = claim_ids.pop()
            return self.release_failed_batch_by_claim(claim_id, error_text, delay_seconds)

        job_ids = [j["job_id"] for j in jobs]
        return self.release_failed_batch_by_ids(job_ids, error_text, delay_seconds)


    def release_failed_batch(self, jobs, error_text, delay_seconds=0):
        return self.with_db_retry(
            "release_failed_batch",
            lambda: self.release_failed_batch_once(jobs, error_text, delay_seconds),
        )


    def finalize_batch_once(self, jobs, winner_ids):
        if not jobs:
            return

        raw_claim_ids = {j.get("claim_id") for j in jobs}
        claim_ids = {claim_id for claim_id in raw_claim_ids if claim_id}

        if len(claim_ids) > 1 or (claim_ids and None in raw_claim_ids):
            raise RuntimeError("Batch contains multiple claim_id values")

        if claim_ids:
            claim_id = claim_ids.pop()

            self.finalize_batch_by_claim(claim_id, list(winner_ids))
            return

        all_ids = [j["job_id"] for j in jobs]
        self.finalize_batch_by_ids(all_ids, winner_ids)


    def finalize_batch(self, jobs, winner_ids):
        return self.with_db_retry(
            "finalize_batch",
            lambda: self.finalize_batch_once(jobs, winner_ids),
        )


    def fetch_item_document(self, item_id):
        cur = self.conn.cursor(dictionary=True)
        try:
            cur.execute("""
                SELECT item_id, title, body, category, status, created_at
                FROM items
                WHERE item_id = %s
            """, (item_id,))

            row = cur.fetchone()
            self.conn.commit()

            if not row:
                return None

            return {
                "entity_type": "item",
                "entity_id": str(row["item_id"]),
                "title": row["title"],
                "body": row["body"],
                "category": row["category"],
                "status": row["status"],
                "created_at": row["created_at"].isoformat() if row["created_at"] else None,
            }

        except Exception:
            self.conn.rollback()
            raise          


    def reap_stale_jobs_once(self, stale_seconds: int, delay_seconds: int, limit: int = 1000):
        cur = self.conn.cursor(dictionary=True)

        try:
            cur.execute("""
                SELECT job_id
                FROM search_index_jobs
                WHERE status = %s
                AND claim_id IS NOT NULL
                AND started_at < (NOW() - INTERVAL %s SECOND)
                ORDER BY started_at ASC, job_id ASC
                LIMIT %s
                FOR UPDATE SKIP LOCKED
            """, (STATUS_RUNNING, stale_seconds, limit))

            rows = cur.fetchall()

            if not rows:
                self.conn.commit()
                return 0

            job_ids = sorted(r["job_id"] for r in rows)
            placeholders = ",".join(["%s"] * len(job_ids))

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET available_at = NOW() + INTERVAL %s SECOND,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    reap_count = reap_count + 1,
                    error_text = 'Reaped stale running job'
                WHERE job_id IN ({placeholders})
                AND status = %s
                AND claim_id IS NOT NULL
                """,
                [delay_seconds] + job_ids + [STATUS_RUNNING]
            )

            count = cur.rowcount
            self.conn.commit()
            return count

        except Exception:
            self.conn.rollback()
            raise


    def reap_stale_jobs(self, stale_seconds: int, delay_seconds: int, limit: int = 1000):
        return self.with_db_retry(
            "reap_stale_jobs",
            lambda: self.reap_stale_jobs_once(stale_seconds, delay_seconds, limit),
        )
