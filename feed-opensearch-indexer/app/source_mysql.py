import mysql.connector

from app.campaign_actions import (
    CAMPAIGN_ACTION_DOCUMENT_SQL,
    campaign_action_document_from_row,
)


class SourceMySql:
    def __init__(self, config):
        self.conn = mysql.connector.connect(**config)
        self.conn.autocommit = True

    def fetch_campaign_action_document(self, entity_id):
        cur = self.conn.cursor(dictionary=True)
        try:
            cur.execute(CAMPAIGN_ACTION_DOCUMENT_SQL, (entity_id,))
            return campaign_action_document_from_row(cur.fetchone())
        finally:
            cur.close()

    def close(self):
        self.conn.close()
