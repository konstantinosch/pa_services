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

from app.campaign_actions import ENTITY_TYPE as CAMPAIGN_ACTION
from app.config import (
    WORKER_BATCH_DELAY_SECONDS,
    WORKER_BATCH_SIZE,
    WORKER_POLL_INTERVAL_SECONDS,
    WORKER_RETRY_DELAY_SECONDS,
    LOG_FILE,
    LOG_LEVEL,
    OPENSEARCH_CONFIG,
    SOURCE_MYSQL_CONFIG,
    ensure_log_directory,
)
from app.opensearch_indexer import OpenSearchIndexer
from app.source_mysql import SourceMySql
from db.base import ACTION_DELETE, ACTION_INSERT, ACTION_UPDATE
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
        logging.info("Skipping unsupported entity type: %s", entity_type)
        return

    if action in (ACTION_INSERT, ACTION_UPDATE):
        doc = source_db.fetch_campaign_action_document(entity_id)

        if doc is None:
            search_index.delete_document(entity_id)
            logging.info(
                "Deleted campaign_action %s from index because it is missing or not feed_visible",
                entity_id,
            )
            return

        search_index.upsert_document(doc)
        logging.info("Upserted campaign_action %s into OpenSearch", entity_id)

    elif action == ACTION_DELETE:
        search_index.delete_document(entity_id)
        logging.info("Deleted campaign_action %s from OpenSearch", entity_id)

    else:
        raise RuntimeError(f"Unknown action: {action}")


def main():
    setup_logging()
    logging.info("Worker started")

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    db = create_adapter()
    db.log_config()
    source_db = SourceMySql(SOURCE_MYSQL_CONFIG)
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

            for job in collapsed:
                if shutdown_event.is_set():
                    break

                process_job(source_db, search_index, job)

            if not shutdown_event.is_set():
                db.finalize_batch(jobs, winner_ids)

            if WORKER_BATCH_DELAY_SECONDS > 0:
                shutdown_event.wait(WORKER_BATCH_DELAY_SECONDS)

        except Exception as error:
            logging.exception("Fatal worker error while processing batch. Shutting down.")

            try:
                released_count = db.release_failed_batch(
                    jobs,
                    str(error),
                    WORKER_RETRY_DELAY_SECONDS,
                )
                logging.error(
                    "Released failed batch ownership: jobs=%d retry_delay=%ss",
                    released_count,
                    WORKER_RETRY_DELAY_SECONDS,
                )
            except Exception:
                logging.exception("Failed to release batch")

            shutdown_event.set()
            break

    if shutdown_signal_received:
        logging.info("Shutdown requested")

    logging.info("Worker stopped cleanly")


if __name__ == "__main__":
    main()
