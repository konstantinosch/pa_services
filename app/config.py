import os
from dotenv import load_dotenv

load_dotenv()

DB_ENGINE = os.getenv("DB_ENGINE", "mysql")
POLL_INTERVAL_SECONDS = float(os.getenv("POLL_INTERVAL_SECONDS", "2"))
BATCH_DELAY_SECONDS = float(os.getenv("BATCH_DELAY_SECONDS", "2"))
JOB_BATCH_SIZE = int(os.getenv("JOB_BATCH_SIZE", "100"))
CLAIM_STRATEGY = os.getenv("CLAIM_STRATEGY", "simple")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOG_FILE = os.getenv("LOG_FILE", "logs/indexer.log")

MYSQL_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "localhost"),
    "port": int(os.getenv("MYSQL_PORT", "3306")),
    "user": os.getenv("MYSQL_USER", "indexer"),
    "password": os.getenv("MYSQL_PASSWORD"),
    "database": os.getenv("MYSQL_DATABASE", "search_prototype"),
}