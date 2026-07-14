import logging
import os
import random
import socket
import time
import uuid

import mysql.connector

from db.base import (
    STATE_DELETED,
    STATE_FAILED,
    STATE_INDEXED,
    STATUS_DONE,
    STATUS_FAILED,
    STATUS_PENDING,
    STATUS_RUNNING,
    STATUS_SUPERSEDED,
)


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


    def release_or_fail_batch_by_ids(self, job_ids, error_text, delay_seconds=0, max_retries=10):
        if not job_ids:
            return {"released": 0, "failed": 0}

        cur = self.conn.cursor()
        placeholders = ",".join(["%s"] * len(job_ids))

        try:
            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET available_at = CASE
                        WHEN retry_count + 1 >= %s THEN available_at
                        ELSE NOW() + INTERVAL %s SECOND
                    END,
                    status = CASE
                        WHEN retry_count + 1 >= %s THEN %s
                        ELSE status
                    END,
                    finished_at = CASE
                        WHEN retry_count + 1 >= %s THEN NOW()
                        ELSE finished_at
                    END,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE job_id IN ({placeholders})
                AND status = %s
                """,
                [
                    max_retries,
                    delay_seconds,
                    max_retries,
                    STATUS_FAILED,
                    max_retries,
                    error_text[:1000],
                ] + job_ids + [STATUS_RUNNING],
            )

            cur.execute(
                f"""
                SELECT
                    SUM(status = %s) AS failed_count,
                    SUM(status = %s AND claim_id IS NULL) AS released_count
                FROM search_index_jobs
                WHERE job_id IN ({placeholders})
                """,
                [STATUS_FAILED, STATUS_RUNNING] + job_ids,
            )
            row = cur.fetchone()
            self.conn.commit()
            return {
                "released": int(row[1] or 0),
                "failed": int(row[0] or 0),
            }

        except Exception:
            self.conn.rollback()
            raise


    def release_or_fail_batch_by_claim(self, claim_id, error_text, delay_seconds=0, max_retries=10):
        if not claim_id:
            return {"released": 0, "failed": 0}

        cur = self.conn.cursor()

        try:
            cur.execute("""
                SELECT job_id
                FROM search_index_jobs
                WHERE claim_id = %s
                AND status = %s
                ORDER BY job_id ASC
                FOR UPDATE
            """, (claim_id, STATUS_RUNNING))

            job_ids = [row[0] for row in cur.fetchall()]

            if not job_ids:
                self.conn.commit()
                return {"released": 0, "failed": 0}

            placeholders = ",".join(["%s"] * len(job_ids))

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET available_at = CASE
                        WHEN retry_count + 1 >= %s THEN available_at
                        ELSE NOW() + INTERVAL %s SECOND
                    END,
                    status = CASE
                        WHEN retry_count + 1 >= %s THEN %s
                        ELSE status
                    END,
                    finished_at = CASE
                        WHEN retry_count + 1 >= %s THEN NOW()
                        ELSE finished_at
                    END,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE job_id IN ({placeholders})
                AND status = %s
                """,
                [
                    max_retries,
                    delay_seconds,
                    max_retries,
                    STATUS_FAILED,
                    max_retries,
                    error_text[:1000],
                ] + job_ids + [STATUS_RUNNING],
            )

            cur.execute(
                f"""
                SELECT
                    SUM(status = %s) AS failed_count,
                    SUM(status = %s AND claim_id IS NULL) AS released_count
                FROM search_index_jobs
                WHERE job_id IN ({placeholders})
                """,
                [STATUS_FAILED, STATUS_RUNNING] + job_ids,
            )
            row = cur.fetchone()
            self.conn.commit()
            return {
                "released": int(row[1] or 0),
                "failed": int(row[0] or 0),
            }

        except Exception:
            self.conn.rollback()
            raise


    def release_or_fail_batch_once(self, jobs, error_text, delay_seconds=0, max_retries=10):
        if not jobs:
            return {"released": 0, "failed": 0}

        max_retries = max(1, int(max_retries))
        raw_claim_ids = {j.get("claim_id") for j in jobs}
        claim_ids = {claim_id for claim_id in raw_claim_ids if claim_id}

        if len(claim_ids) > 1 or (claim_ids and None in raw_claim_ids):
            raise RuntimeError("Batch contains multiple claim_id values")

        if claim_ids:
            claim_id = claim_ids.pop()
            return self.release_or_fail_batch_by_claim(
                claim_id,
                error_text,
                delay_seconds,
                max_retries,
            )

        job_ids = [j["job_id"] for j in jobs]
        return self.release_or_fail_batch_by_ids(
            job_ids,
            error_text,
            delay_seconds,
            max_retries,
        )


    def release_or_fail_batch(self, jobs, error_text, delay_seconds=0, max_retries=10):
        return self.with_db_retry(
            "release_or_fail_batch",
            lambda: self.release_or_fail_batch_once(
                jobs,
                error_text,
                delay_seconds,
                max_retries,
            ),
        )

    def execute_state_upsert(self, cur, job, index_status, error_text=None):
        indexed_at_expr = "NOW()" if index_status == STATE_INDEXED else "NULL"
        deleted_at_expr = "NOW()" if index_status == STATE_DELETED else "NULL"
        failed_at_expr = "NOW()" if index_status == STATE_FAILED else "NULL"

        cur.execute(
            f"""
            INSERT INTO search_index_state (
                entity_type,
                entity_id,
                index_status,
                last_action,
                last_job_id,
                last_job_created_at,
                indexed_at,
                deleted_at,
                failed_at,
                last_error_text
            )
            VALUES (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                {indexed_at_expr},
                {deleted_at_expr},
                {failed_at_expr},
                %s
            )
            ON DUPLICATE KEY UPDATE
                index_status = VALUES(index_status),
                last_action = VALUES(last_action),
                last_job_id = VALUES(last_job_id),
                last_job_created_at = VALUES(last_job_created_at),
                indexed_at = VALUES(indexed_at),
                deleted_at = VALUES(deleted_at),
                failed_at = VALUES(failed_at),
                last_error_text = VALUES(last_error_text)
            """,
            (
                job["entity_type"],
                job["entity_id"],
                index_status,
                job["action"],
                job["job_id"],
                job.get("created_at"),
                error_text[:1000] if error_text else None,
            ),
        )


    def mark_state_once(self, job, index_status, error_text=None):
        cur = self.conn.cursor()

        try:
            self.execute_state_upsert(cur, job, index_status, error_text)
            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def mark_state_indexed(self, job):
        return self.with_db_retry(
            "mark_state_indexed",
            lambda: self.mark_state_once(job, STATE_INDEXED),
        )


    def mark_state_deleted(self, job):
        return self.with_db_retry(
            "mark_state_deleted",
            lambda: self.mark_state_once(job, STATE_DELETED),
        )


    def mark_state_failed_once(self, jobs, error_text):
        if not jobs:
            return 0

        latest_by_entity = {}

        for job in jobs:
            key = (job["entity_type"], job["entity_id"])
            current = latest_by_entity.get(key)

            if current is None or (job["created_at"], job["job_id"]) > (current["created_at"], current["job_id"]):
                latest_by_entity[key] = job

        cur = self.conn.cursor()

        try:
            for job in latest_by_entity.values():
                self.execute_state_upsert(cur, job, STATE_FAILED, error_text)

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise

        return len(latest_by_entity)


    def mark_state_failed(self, jobs, error_text):
        return self.with_db_retry(
            "mark_state_failed",
            lambda: self.mark_state_failed_once(jobs, error_text),
        )


    def cleanup_terminal_jobs_once(self, jobs):
        if not jobs:
            return 0

        latest_by_entity = {}

        for job in jobs:
            key = (job["entity_type"], job["entity_id"])
            current = latest_by_entity.get(key)

            if current is None or (job["created_at"], job["job_id"]) > (current["created_at"], current["job_id"]):
                latest_by_entity[key] = job

        cur = self.conn.cursor()
        cleaned_count = 0

        try:
            for job in latest_by_entity.values():
                cur.execute("""
                    DELETE j
                    FROM search_index_jobs j
                    JOIN search_index_state s
                      ON s.entity_type = j.entity_type
                     AND s.entity_id = j.entity_id
                    WHERE j.entity_type = %s
                      AND j.entity_id = %s
                      AND j.status IN (%s, %s, %s)
                      AND j.job_id <= s.last_job_id
                """, (
                    job["entity_type"],
                    job["entity_id"],
                    STATUS_DONE,
                    STATUS_SUPERSEDED,
                    STATUS_FAILED,
                ))
                cleaned_count += cur.rowcount

            self.conn.commit()
            return cleaned_count

        except Exception:
            self.conn.rollback()
            raise


    def cleanup_terminal_jobs(self, jobs):
        return self.with_db_retry(
            "cleanup_terminal_jobs",
            lambda: self.cleanup_terminal_jobs_once(jobs),
        )


    def cleanup_state_covered_terminal_jobs_once(self, limit=10000):
        cur = self.conn.cursor()

        try:
            cur.execute("""
                DELETE FROM search_index_jobs
                WHERE job_id IN (
                    SELECT job_id
                    FROM (
                        SELECT j.job_id
                        FROM search_index_jobs j
                        JOIN search_index_state s
                          ON s.entity_type = j.entity_type
                         AND s.entity_id = j.entity_id
                        WHERE j.status IN (%s, %s, %s)
                          AND j.job_id <= s.last_job_id
                        ORDER BY j.job_id ASC
                        LIMIT %s
                    ) state_covered_terminal_jobs
                )
            """, (STATUS_DONE, STATUS_SUPERSEDED, STATUS_FAILED, limit))

            cleaned_count = cur.rowcount
            self.conn.commit()
            return cleaned_count

        except Exception:
            self.conn.rollback()
            raise


    def cleanup_state_covered_terminal_jobs(self, limit=10000):
        return self.with_db_retry(
            "cleanup_state_covered_terminal_jobs",
            lambda: self.cleanup_state_covered_terminal_jobs_once(limit),
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


    def finalize_successful_jobs_once(self, jobs, winner_ids, entity_keys):
        if not jobs or not entity_keys:
            return

        winner_ids = set(winner_ids)
        successful_job_ids = [
            j["job_id"]
            for j in jobs
            if (j["entity_type"], j["entity_id"]) in entity_keys
        ]
        successful_winner_ids = sorted(set(successful_job_ids) & winner_ids)
        superseded_ids = sorted(set(successful_job_ids) - winner_ids)

        cur = self.conn.cursor()

        try:
            if successful_winner_ids:
                placeholders = ",".join(["%s"] * len(successful_winner_ids))
                cur.execute(
                    f"""
                    UPDATE search_index_jobs
                    SET status = %s,
                        finished_at = NOW()
                    WHERE job_id IN ({placeholders})
                    AND status = %s
                    """,
                    [STATUS_DONE] + successful_winner_ids + [STATUS_RUNNING],
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
                    [STATUS_SUPERSEDED] + superseded_ids + [STATUS_RUNNING],
                )

            self.conn.commit()

        except Exception:
            self.conn.rollback()
            raise


    def finalize_successful_jobs(self, jobs, winner_ids, entity_keys):
        return self.with_db_retry(
            "finalize_successful_jobs",
            lambda: self.finalize_successful_jobs_once(jobs, winner_ids, entity_keys),
        )


    def reap_stale_jobs_once(self, stale_seconds: int, delay_seconds: int, limit: int = 1000):
        cur = self.conn.cursor(dictionary=True)

        try:
            cur.execute("""
                SELECT job_id, entity_type, entity_id, action, created_at
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

            error_text = "Reaped stale running job"
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
                    error_text = %s
                WHERE job_id IN ({placeholders})
                AND status = %s
                AND claim_id IS NOT NULL
                """,
                [delay_seconds, error_text] + job_ids + [STATUS_RUNNING]
            )

            count = cur.rowcount

            if count:
                for row in rows:
                    self.execute_state_upsert(cur, row, STATE_FAILED, error_text)

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
