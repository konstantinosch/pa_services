import logging
import signal
import threading

import mysql.connector

from app.config import (
    LOG_LEVEL,
    LOG_FILE,
    ensure_log_directory,
    REAPER_POLL_INTERVAL_SECONDS,
    REAPER_STALE_SECONDS,
    REAPER_BATCH_SIZE,
    REAPER_BATCH_DELAY_SECONDS,
    REAPER_RELEASE_DELAY_SECONDS
)

from db.factory import create_adapter


shutdown_event = threading.Event()
shutdown_signal_received = False


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


def handle_shutdown(signum, frame):
    global shutdown_signal_received
    shutdown_signal_received = True
    shutdown_event.set()


def main():
    setup_logging()

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

    logging.info(
        "Reaper started: interval=%ss stale=%ss batch_size=%s",
        REAPER_POLL_INTERVAL_SECONDS,
        REAPER_STALE_SECONDS,
        REAPER_BATCH_SIZE,
    )

    while not shutdown_event.is_set():
        total_reaped = 0
        reaped_count = 0

        try:
            while not shutdown_event.is_set():
                reaped_count = db.reap_stale_jobs(
                    REAPER_STALE_SECONDS,
                    REAPER_RELEASE_DELAY_SECONDS,
                    REAPER_BATCH_SIZE,
                )
                if reaped_count == 0:
                    break

                total_reaped += reaped_count

                logging.warning("Reaper batch requeued stale jobs: reaped=%d", reaped_count)

                if REAPER_BATCH_DELAY_SECONDS > 0:
                    shutdown_event.wait(REAPER_BATCH_DELAY_SECONDS)

            if total_reaped:
                logging.warning(
                    "Reaper cycle complete: total_reaped=%d",
                    total_reaped,
                )
            else:
                logging.debug("Reaper found no stale jobs")

        except Exception:
            logging.exception("Fatal reaper error. Shutting down.")
            shutdown_event.set()
            break

        shutdown_event.wait(REAPER_POLL_INTERVAL_SECONDS)

    if shutdown_signal_received:
        logging.info("Shutdown requested")

    logging.info("Reaper stopped cleanly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
