# ============================================================
# PROCESSING MODEL
# ============================================================
#
# - Jobs are claimed using FOR UPDATE SKIP LOCKED
# - Status transitions: P -> R -> (D | S | F)
# - Jobs are processed in batches and compressed per (entity_type, entity_id)
# - Latest job (by created_at, job_id) wins per entity
#
# FUTURE CONSISTENCY MODEL:
# - entity_state will hold latest processed state per (entity_type, entity_id)
# - freshness guard will prevent stale jobs from overwriting newer results
#
# ============================================================

import logging
import signal
import threading

import mysql.connector

from app.campaign_actions import ENTITY_TYPE as CAMPAIGN_ACTION
from app.config import (
    WORKER_BATCH_DELAY_SECONDS,
    WORKER_BATCH_SIZE,
    WORKER_MAX_RETRIES,
    WORKER_POLL_INTERVAL_SECONDS,
    WORKER_RETRY_DELAY_SECONDS,
    JOB_CLEANUP_BATCH_SIZE,
    LOG_FILE,
    LOG_LEVEL,
    OPENSEARCH_CONFIG,
    SOURCE_MYSQL_CONFIG,
    ensure_log_directory,
)
from app.opensearch_indexer import OpenSearchIndexer
from app.source_mysql import SourceMySql
from db.base import (
    ACTION_DELETE,
    ACTION_INSERT,
    ACTION_UPDATE,
    STATE_DELETED,
    STATE_INDEXED,
)
from db.factory import create_adapter


shutdown_event = threading.Event()
shutdown_signal_received = False


def handle_shutdown(signum, frame):
    global shutdown_signal_received
    shutdown_signal_received = True
    shutdown_event.set()


def setup_logging():
    ensure_log_directory()

    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(LOG_FILE),
        ],
    )


def collapse_jobs(rows):
    latest = {}

    for row in rows:
        key = (row["entity_type"], row["entity_id"])
        current = latest.get(key)

        if current is None:
            latest[key] = row
            continue

        if (row["created_at"], row["job_id"]) > (current["created_at"], current["job_id"]):
            latest[key] = row

    compressed_jobs = list(latest.values())

    compressed_jobs.sort(
        key=lambda r: (-r["priority"], r["created_at"], r["job_id"])
    )

    return compressed_jobs


def process_job(source_db, search_index, job):
    entity_type = job["entity_type"]
    entity_id = job["entity_id"]
    action = job["action"]

    if entity_type != CAMPAIGN_ACTION:
        raise RuntimeError(f"Unsupported entity type: {entity_type}")

    if action in (ACTION_INSERT, ACTION_UPDATE):
        doc = source_db.fetch_campaign_action_document(entity_id)

        if doc is None:
            search_index.delete_document(entity_id)
            logging.info(
                "Deleted campaign_action %s from index because it is missing or not feed_visible",
                entity_id,
            )
            return STATE_DELETED

        search_index.upsert_document(doc)
        logging.info("Upserted campaign_action %s into OpenSearch", entity_id)
        return STATE_INDEXED

    elif action == ACTION_DELETE:
        search_index.delete_document(entity_id)
        logging.info("Deleted campaign_action %s from OpenSearch", entity_id)
        return STATE_DELETED

    else:
        raise RuntimeError(f"Unknown action: {action}")


def main():
    setup_logging()
    logging.info("Worker started")

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    try:
        db = create_adapter()
    except mysql.connector.Error as error:
        logging.error(
            "Cannot connect to indexer MySQL database. Check MYSQL_HOST, MYSQL_PORT, "
            "MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, and that MySQL is running. error=%s",
            error,
        )
        return 1

    db.log_config()

    try:
        source_db = SourceMySql(SOURCE_MYSQL_CONFIG)
    except mysql.connector.Error as error:
        logging.error(
            "Cannot connect to source MySQL database. Check SOURCE_MYSQL_HOST, "
            "SOURCE_MYSQL_PORT, SOURCE_MYSQL_USER/SOURCE_MYSQL_PASSWORD or MYSQL_USER/MYSQL_PASSWORD, "
            "SOURCE_MYSQL_DATABASE, grants, and that MySQL is running. error=%s",
            error,
        )
        return 1

    search_index = OpenSearchIndexer(OPENSEARCH_CONFIG)
    logging.info(
        "Indexer targets: source_db=%s opensearch=%s index=%s",
        SOURCE_MYSQL_CONFIG["database"],
        OPENSEARCH_CONFIG["url"],
        OPENSEARCH_CONFIG["index"],
    )

    while not shutdown_event.is_set():
        jobs = []
        try:
            jobs = db.fetch_jobs(limit=WORKER_BATCH_SIZE)

            if not jobs:
                shutdown_event.wait(WORKER_POLL_INTERVAL_SECONDS)
                continue

            collapsed = collapse_jobs(jobs)
            winner_ids = {j["job_id"] for j in collapsed}
            ratio = len(collapsed) / len(jobs)
            saved = len(jobs) - len(collapsed)

            logging.info(
                "Fetched %d jobs -> collapsed %d entities (saved %d, ratio %.5f)",
                len(jobs),
                len(collapsed),
                saved,
                ratio,
            )
            logging.debug("Raw jobs: %s", jobs)
            logging.debug("Collapsed jobs: %s", collapsed)

            successful_entity_keys = set()
            successful_winner_ids = set()
            failed_entity_keys = set()
            failed_errors = []

            for job in collapsed:
                if shutdown_event.is_set():
                    break

                entity_key = (job["entity_type"], job["entity_id"])

                try:
                    state = process_job(source_db, search_index, job)
                    if state == STATE_INDEXED:
                        db.mark_state_indexed(job)
                    elif state == STATE_DELETED:
                        db.mark_state_deleted(job)

                    successful_entity_keys.add(entity_key)
                    successful_winner_ids.add(job["job_id"])

                except Exception as error:
                    failed_entity_keys.add(entity_key)
                    failed_errors.append(
                        f"{job['entity_type']}:{job['entity_id']} job_id={job['job_id']}: {error}"
                    )
                    logging.exception(
                        "Worker failed entity: entity_type=%s entity_id=%s job_id=%s",
                        job["entity_type"],
                        job["entity_id"],
                        job["job_id"],
                    )

            if not shutdown_event.is_set():
                if failed_entity_keys:
                    successful_entity_keys -= failed_entity_keys
                    successful_winner_ids = {
                        job["job_id"]
                        for job in collapsed
                        if (job["entity_type"], job["entity_id"]) in successful_entity_keys
                    }

                if failed_entity_keys:
                    db.finalize_successful_jobs(
                        jobs,
                        successful_winner_ids,
                        successful_entity_keys,
                    )
                else:
                    db.finalize_batch(jobs, winner_ids)

                if failed_entity_keys:
                    failed_jobs = [
                        job
                        for job in jobs
                        if (job["entity_type"], job["entity_id"]) in failed_entity_keys
                    ]
                    error_text = "; ".join(failed_errors) or "Worker entity processing failed"

                    try:
                        failed_state_count = db.mark_state_failed(failed_jobs, error_text)
                        logging.error(
                            "Updated failed state rows: entities=%d",
                            failed_state_count,
                        )
                    except Exception:
                        logging.exception("Failed to update failed state rows")

                    failure_counts = db.release_or_fail_batch(
                        failed_jobs,
                        error_text,
                        WORKER_RETRY_DELAY_SECONDS,
                        WORKER_MAX_RETRIES,
                    )
                    logging.error(
                        "Handled failed entity jobs: released=%d failed=%d retry_delay=%ss max_retries=%s",
                        failure_counts["released"],
                        failure_counts["failed"],
                        WORKER_RETRY_DELAY_SECONDS,
                        WORKER_MAX_RETRIES,
                    )

                try:
                    scoped_cleaned_count = db.cleanup_terminal_jobs(jobs)
                    global_cleaned_count = db.cleanup_state_covered_terminal_jobs(
                        JOB_CLEANUP_BATCH_SIZE,
                    )
                    cleaned_count = scoped_cleaned_count + global_cleaned_count
                    if cleaned_count:
                        logging.info(
                            "Cleaned terminal queue rows: scoped=%d global=%d total=%d",
                            scoped_cleaned_count,
                            global_cleaned_count,
                            cleaned_count,
                        )
                except Exception:
                    logging.exception(
                        "Terminal queue cleanup failed after successful batch finalization"
                    )

            if WORKER_BATCH_DELAY_SECONDS > 0:
                shutdown_event.wait(WORKER_BATCH_DELAY_SECONDS)

        except Exception as error:
            logging.exception("Fatal worker error while processing batch. Shutting down.")

            try:
                failed_state_count = db.mark_state_failed(jobs, str(error))
                logging.error(
                    "Updated failed state rows: entities=%d",
                    failed_state_count,
                )
            except Exception:
                logging.exception("Failed to update failed state rows")

            try:
                failure_counts = db.release_or_fail_batch(
                    jobs,
                    str(error),
                    WORKER_RETRY_DELAY_SECONDS,
                    WORKER_MAX_RETRIES,
                )
                logging.error(
                    "Handled failed batch: released=%d failed=%d retry_delay=%ss max_retries=%s",
                    failure_counts["released"],
                    failure_counts["failed"],
                    WORKER_RETRY_DELAY_SECONDS,
                    WORKER_MAX_RETRIES,
                )
            except Exception:
                logging.exception("Failed to release batch")

            shutdown_event.set()
            break

    if shutdown_signal_received:
        logging.info("Shutdown requested")

    logging.info("Worker stopped cleanly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
