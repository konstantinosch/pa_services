# ============================================================
# PROCESSING MODEL
# ============================================================
#
# - Jobs are claimed using FOR UPDATE SKIP LOCKED
# - Status transitions: P → R → (D | S | F)
# - Jobs are processed in batches and compressed per (entity_type, entity_id)
# - Latest job (by created_at, job_id) wins per entity
#
# FUTURE CONSISTENCY MODEL:
# - entity_state will hold latest processed state per (entity_type, entity_id)
# - freshness guard will prevent stale jobs from overwriting newer results
# - document_hash will avoid unnecessary re-indexing
#
# ============================================================

import os
import signal
import threading
import logging
from db.factory import create_adapter
from db.base import ACTION_INSERT, ACTION_UPDATE, ACTION_DELETE
from app.config import (
    LOG_LEVEL, 
    LOG_FILE,
    DAEMON_POLL_INTERVAL_SECONDS,
    DAEMON_BATCH_SIZE,
    DAEMON_BATCH_DELAY_SECONDS, 
)


shutdown_event = threading.Event()


def handle_shutdown(signum, frame):
    logging.info("Shutdown requested...")
    shutdown_event.set()


def setup_logging():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)

    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler(LOG_FILE),
        ],
    )

# ------------------------------------------------------------
# COLLAPSE / COALESCE JOBS PER ENTITY
#
# Purpose:
# Reduce multiple pending jobs per (entity_type, entity_id)
# into a single effective job that represents the latest state.
#
# Why:
# - An entity may receive many updates in quick succession
# - Re-indexing each intermediate state is wasteful
# - Only the latest state (from the DB) matters for indexing
#
# Correctness:
# - The "winning" job per entity is selected by:
#     (created_at, job_id)  → latest wins
# - Priority is NOT used for correctness
#   (priority only affects scheduling, not final state)
#
# Important:
# - Collapse destroys original ordering
#   → results MUST be re-sorted after this step
#
# Processing model:
# - Collapse → then sort by (priority DESC, created_at ASC, job_id ASC)
# - Ensures:
#     ✔ correctness (latest state)
#     ✔ controlled processing order (priority + fairness)
#
# Note:
# - Final document is always rebuilt from DB state
# - Jobs act as change signals, not as the source of truth
# ------------------------------------------------------------
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


def process_job(db, job):
    entity_type = job["entity_type"]
    entity_id = job["entity_id"]
    action = job["action"]

    if entity_type != "item":
        logging.info("Skipping unsupported entity type: %s", entity_type)
        return

    if action in (ACTION_INSERT, ACTION_UPDATE):
        doc = db.fetch_item_document(entity_id)

        if doc is None:
            logging.info("Item %s no longer exists, would delete from index", entity_id)
            return

        logging.debug("Would upsert document: %s", doc)

    elif action == ACTION_DELETE:
        logging.info("Would delete item %s from index", entity_id)

    else:
        raise RuntimeError(f"Unknown action: {action}")


def main():

    setup_logging()
    logging.info("Generic daemon started")

    signal.signal(signal.SIGINT, handle_shutdown)
    signal.signal(signal.SIGTERM, handle_shutdown)

    db = create_adapter()
    db.log_config()

    while not shutdown_event.is_set():
        jobs = []
        try:
            jobs = db.fetch_jobs(limit=DAEMON_BATCH_SIZE)

            if not jobs:
                shutdown_event.wait(DAEMON_POLL_INTERVAL_SECONDS)
                continue

            collapsed = collapse_jobs(jobs)

            winner_ids = {j["job_id"] for j in collapsed}

            ratio = len(collapsed) / len(jobs)
            saved = len(jobs) - len(collapsed)

            logging.info(
                "Fetched %d jobs → collapsed %d entities (saved %d, ratio %.5f)",
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

                process_job(db, job)

            if not shutdown_event.is_set():
                db.finalize_batch(jobs, winner_ids)

            if DAEMON_BATCH_DELAY_SECONDS > 0:
                shutdown_event.wait(DAEMON_BATCH_DELAY_SECONDS)

        except Exception as e:
            logging.exception("Fatal error while processing batch. Shutting down.")

            try:
                released_count = db.release_failed_batch(jobs, str(e))
                logging.error("Released batch back to pending: %d jobs", released_count)
            except Exception:
                logging.exception("Failed to release batch")

            shutdown_event.set()
            break

    logging.info("Daemon stopped cleanly.")


if __name__ == "__main__":
    main()