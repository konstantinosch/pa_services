from app.config import (
    DB_ENGINE,
    MYSQL_CONFIG,
    WORKER_CLAIM_STRATEGY,
    DB_RETRY_ATTEMPTS,
    DB_RETRY_BASE_DELAY_SECONDS,
    DB_RETRY_MAX_DELAY_SECONDS,
)
from db.mysql_adapter import MySqlAdapter

def create_adapter():
    if DB_ENGINE == "mysql":
        return MySqlAdapter(
            MYSQL_CONFIG,
            WORKER_CLAIM_STRATEGY,
            DB_RETRY_ATTEMPTS,
            DB_RETRY_BASE_DELAY_SECONDS,
            DB_RETRY_MAX_DELAY_SECONDS,
        )

    raise RuntimeError(f"Unsupported DB engine: {DB_ENGINE}")
