from app.config import DB_ENGINE, MYSQL_CONFIG, CLAIM_STRATEGY
from db.mysql_adapter import MySqlAdapter

def create_adapter():
    if DB_ENGINE == "mysql":
        return MySqlAdapter(MYSQL_CONFIG, CLAIM_STRATEGY)

    raise RuntimeError(f"Unsupported DB engine: {DB_ENGINE}")
