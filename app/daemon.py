# ============================================================
# PROCESSING MODEL
# ============================================================
#
# - Jobs are claimed using FOR UPDATE SKIP LOCKED
# - Status transitions: P → R → (D | F)
# - Jobs are processed in batches and compressed per (entity_type, entity_id)
# - Latest job (by created_at, job_id) wins per entity
#
# IMPORTANT:
# - entity_state table holds latest processed state per entity
# - freshness guard prevents stale jobs from overwriting newer results
# - document_hash avoids unnecessary re-indexing
#
# FUTURE CONSISTENCY MODEL:
# - entity_state will hold latest processed state per (entity_type, entity_id)
# - freshness guard will prevent stale jobs from overwriting newer results
# - document_hash will avoid unnecessary re-indexing
#
# ============================================================

import os
import time
import signal
import threading
import logging
from db.factory import create_adapter
from db.base import ACTION_INSERT, ACTION_UPDATE, ACTION_DELETE
from app.config import POLL_INTERVAL_SECONDS, JOB_BATCH_SIZE, BATCH_DELAY_SECONDS, LOG_LEVEL, LOG_FILE

shutdown_event = threading.Event()


def handle_shutdown(signum, frame):
    print("\nShutdown requested...")
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
        print(f"Skipping unsupported entity type: {entity_type}")
        return

    if action in (ACTION_INSERT, ACTION_UPDATE):
        doc = db.fetch_item_document(entity_id)

        if doc is None:
            print(f"Item {entity_id} no longer exists, would delete from index")
            return

        logging.debug("Would upsert document: %s", doc)

    elif action == ACTION_DELETE:
        print(f"Would delete item {entity_id} from index")

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
        try:
            jobs = db.fetch_jobs(limit=JOB_BATCH_SIZE)

            if not jobs:
                shutdown_event.wait(POLL_INTERVAL_SECONDS)
                continue

            collapsed = collapse_jobs(jobs)

            winner_ids = {j["job_id"] for j in collapsed}
            all_ids = {j["job_id"] for j in jobs}
            superseded_ids = list(all_ids - winner_ids)

            eff = len(collapsed) / len(jobs)
            logging.info(
                "Fetched %d jobs → collapsed %d entities (saved %d, ratio %.5f)",
                len(jobs),
                len(collapsed),
                len(jobs) - len(collapsed),
                len(collapsed) / len(jobs),
            )
            logging.debug("Raw jobs: %s", jobs)
            logging.debug("Collapsed jobs: %s", collapsed)

            for job in collapsed:
                if shutdown_event.is_set():
                    break

                process_job(db, job)

            if not shutdown_event.is_set():
                db.finalize_batch(jobs, winner_ids)

            if BATCH_DELAY_SECONDS > 0:
                shutdown_event.wait(BATCH_DELAY_SECONDS)

        except Exception as e:
            logging.exception("Fatal error while processing batch. Shutting down.")

            try:
                if "jobs" in locals() and jobs:
                    db.mark_failed_many([j["job_id"] for j in jobs], str(e))
            except Exception:
                logging.exception("Could not mark jobs as failed.")

            shutdown_event.set()
            break

    logging.info("Daemon stopped cleanly.")


if __name__ == "__main__":
    main()