import os
import socket
import mysql.connector
import uuid
import logging

from db.base import STATUS_PENDING, STATUS_RUNNING, STATUS_DONE, STATUS_SUPERSEDED


class MySqlAdapter:
    def __init__(self, config, claim_strategy="simple"):
        self.conn = mysql.connector.connect(**config)
        self.conn.autocommit = False
        self.claim_strategy = claim_strategy
        self.worker_id = f"{socket.gethostname()}-{os.getpid()}"


    def log_config(self):
        logging.info(
            "[MySQL Adapter] claim_strategy=%s worker_id=%s",
            self.claim_strategy,
            self.worker_id,
        )


    def fetch_jobs_expanded(self, limit=100):
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
                        WHERE status = %s
                        AND available_at <= NOW()
                        ORDER BY priority DESC, created_at ASC, job_id ASC
                        LIMIT %s
                        FOR UPDATE SKIP LOCKED
                    ) seed
                )
            """, (STATUS_RUNNING, self.worker_id, claim_id, STATUS_PENDING, limit))

            if cur.rowcount == 0:
                self.conn.commit()
                return []

            # 2. Expand claim to all pending jobs for same entities
            cur.execute("""
                UPDATE search_index_jobs j
                JOIN (
                    SELECT DISTINCT entity_type, entity_id
                    FROM search_index_jobs
                    WHERE claim_id = %s
                ) seed
                ON seed.entity_type = j.entity_type
                AND seed.entity_id = j.entity_id
                SET j.status = %s,
                    j.worker_id = %s,
                    j.claim_id = %s,
                    j.claimed_at = NOW(),
                    j.started_at = NOW()
                WHERE j.status = %s AND available_at <= NOW()
            """, (claim_id, STATUS_RUNNING, self.worker_id, claim_id, STATUS_PENDING))

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


    def fetch_jobs_simple(self, limit=100):
        cur = self.conn.cursor(dictionary=True)
        try:
            cur.execute("""
                SELECT job_id, entity_type, entity_id, action, created_at, priority
                FROM search_index_jobs
                WHERE status = %s
                AND available_at <= NOW()                        
                ORDER BY priority DESC, created_at ASC, job_id ASC
                LIMIT %s
                FOR UPDATE SKIP LOCKED
            """, (STATUS_PENDING, limit))

            rows = cur.fetchall()

            if not rows:
                self.conn.commit()
                return []

            job_ids = [r["job_id"] for r in rows]

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s, worker_id = %s, started_at = NOW(), claimed_at = NOW()
                WHERE job_id IN ({",".join(["%s"] * len(job_ids))})
                """,
                [STATUS_RUNNING, self.worker_id] + job_ids
            )

            self.conn.commit()
            return rows

        except Exception:
            self.conn.rollback()
            raise


    def fetch_jobs(self, limit=100):
        if self.claim_strategy == "expanded":
            return self.fetch_jobs_expanded(limit)

        return self.fetch_jobs_simple(limit)


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


    def release_failed_batch_by_ids(self, job_ids, error_text):
        if not job_ids:
            return 0

        cur = self.conn.cursor()
        placeholders = ",".join(["%s"] * len(job_ids))

        try:
            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE job_id IN ({placeholders})
                AND status = %s
                """,
                [STATUS_PENDING, error_text[:1000]] + job_ids + [STATUS_RUNNING]
            )

            released_count = cur.rowcount
            self.conn.commit()
            return released_count

        except Exception:
            self.conn.rollback()
            raise


    def release_failed_batch_by_claim(self, claim_id, error_text):
        if not claim_id:
            return 0

        cur = self.conn.cursor()

        try:
            cur.execute("""
                UPDATE search_index_jobs
                SET status = %s,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    retry_count = retry_count + 1,
                    error_text = %s
                WHERE claim_id = %s
                AND status = %s
            """, (
                STATUS_PENDING,
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


    def release_failed_batch(self, jobs, error_text):
        if not jobs:
            return 0

        if self.claim_strategy == "expanded":
            claim_ids = {j["claim_id"] for j in jobs}

            if len(claim_ids) != 1:
                raise RuntimeError("Batch contains multiple claim_id values")

            claim_id = claim_ids.pop()
            return self.release_failed_batch_by_claim(claim_id, error_text)

        else:
            job_ids = [j["job_id"] for j in jobs]
            return self.release_failed_batch_by_ids(job_ids, error_text)


    def finalize_batch(self, jobs, winner_ids):
        if not jobs:
            return

        if self.claim_strategy == "expanded":

            claim_ids = {j["claim_id"] for j in jobs}

            if len(claim_ids) != 1:
                raise RuntimeError("Batch contains multiple claim_id values")

            claim_id = claim_ids.pop()            

            self.mark_done_by_claim(claim_id, list(winner_ids))
            self.mark_superseded_by_claim(claim_id, list(winner_ids))

        else:
            all_ids = [j["job_id"] for j in jobs]
            superseded_ids = list(set(all_ids) - set(winner_ids))

            self.mark_done(list(winner_ids))
            self.mark_superseded(superseded_ids)


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


    def reap_stale_jobs(self, stale_seconds: int, delay_seconds: int, limit: int = 1000):
        cur = self.conn.cursor(dictionary=True)

        try:
            cur.execute("""
                SELECT job_id
                FROM search_index_jobs
                WHERE status = %s
                AND started_at < (NOW() - INTERVAL %s SECOND)
                ORDER BY started_at ASC, job_id ASC
                LIMIT %s
                FOR UPDATE SKIP LOCKED
            """, (STATUS_RUNNING, stale_seconds, limit))

            rows = cur.fetchall()

            if not rows:
                self.conn.commit()
                return 0

            job_ids = [r["job_id"] for r in rows]
            placeholders = ",".join(["%s"] * len(job_ids))

            cur.execute(
                f"""
                UPDATE search_index_jobs
                SET status = %s,
                    available_at = NOW() + INTERVAL %s SECOND,
                    claim_id = NULL,
                    worker_id = NULL,
                    claimed_at = NULL,
                    started_at = NULL,
                    reap_count = reap_count + 1,
                    error_text = 'Reaped stale running job'
                WHERE job_id IN ({placeholders})
                AND status = %s
                """,
                [STATUS_PENDING] + [delay_seconds] + job_ids + [STATUS_RUNNING]
            )

            count = cur.rowcount
            self.conn.commit()
            return count

        except Exception:
            self.conn.rollback()
            raise
