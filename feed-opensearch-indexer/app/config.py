import os
from dotenv import load_dotenv

load_dotenv()

DAEMON_POLL_INTERVAL_SECONDS = float(os.getenv("DAEMON_POLL_INTERVAL_SECONDS", "2"))
DAEMON_BATCH_DELAY_SECONDS = float(os.getenv("DAEMON_BATCH_DELAY_SECONDS", "0"))
DAEMON_BATCH_SIZE = int(os.getenv("DAEMON_BATCH_SIZE", "100"))
DAEMON_CLAIM_STRATEGY = os.getenv("DAEMON_CLAIM_STRATEGY", "simple")
DAEMON_RETRY_DELAY_SECONDS = int(os.getenv("DAEMON_RETRY_DELAY_SECONDS", "0"))

DB_RETRY_ATTEMPTS = int(os.getenv("DB_RETRY_ATTEMPTS", "3"))
DB_RETRY_BASE_DELAY_SECONDS = float(os.getenv("DB_RETRY_BASE_DELAY_SECONDS", "0.1"))
DB_RETRY_MAX_DELAY_SECONDS = float(os.getenv("DB_RETRY_MAX_DELAY_SECONDS", "2"))

REAPER_POLL_INTERVAL_SECONDS = float(os.getenv("REAPER_POLL_INTERVAL_SECONDS", "60"))
REAPER_BATCH_DELAY_SECONDS = float(os.getenv("REAPER_BATCH_DELAY_SECONDS", "0.5"))
REAPER_BATCH_SIZE = int(os.getenv("REAPER_BATCH_SIZE", "1000"))
REAPER_STALE_SECONDS = int(os.getenv("REAPER_STALE_SECONDS", "600"))
REAPER_RELEASE_DELAY_SECONDS = int(os.getenv("REAPER_RELEASE_DELAY_SECONDS", "600"))

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOG_FILE = os.getenv("LOG_FILE", "logs/pa_opensearch_indexer.log")

DB_ENGINE = os.getenv("DB_ENGINE", "mysql")

MYSQL_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": int(os.getenv("MYSQL_PORT", "3306")),
    "user": os.getenv("MYSQL_USER", "pa_indexer"),
    "password": os.getenv("MYSQL_PASSWORD"),
    "database": os.getenv("MYSQL_DATABASE", "pa_opensearch_indexer"),
}

SOURCE_MYSQL_CONFIG = {
    "host": os.getenv("SOURCE_MYSQL_HOST", "localhost"),
    "port": int(os.getenv("SOURCE_MYSQL_PORT", "3306")),
    "user": os.getenv("SOURCE_MYSQL_USER", ""),
    "password": os.getenv("SOURCE_MYSQL_PASSWORD", ""),
    "database": os.getenv("SOURCE_MYSQL_DATABASE", "deedspot"),
    "bin": os.getenv("SOURCE_MYSQL_BIN", "mysql"),
    "sudo": os.getenv("SOURCE_MYSQL_SUDO", "0"),
}

OPENSEARCH_CONFIG = {
    "url": os.getenv("OPENSEARCH_URL", "http://localhost:9200"),
    "index": os.getenv("OPENSEARCH_INDEX", "campaign_actions_feed"),
    "username": os.getenv("OPENSEARCH_USERNAME", ""),
    "password": os.getenv("OPENSEARCH_PASSWORD", ""),
    "loader_page_size": int(os.getenv("OPENSEARCH_LOADER_PAGE_SIZE", "500")),
}


def ensure_log_directory():
    log_dir = os.path.dirname(LOG_FILE)

    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
