# ACTION VALUES:
# I = Insert  -> new entity -> index document
# U = Update  -> existing entity changed -> re-index full document
# D = Delete  -> entity removed -> delete from index
#
# Note:
# - I and U are treated the same in practice: UPSERT
# - D means remove document from search engine

# ACTION VALUES
ACTION_INSERT = "I"
ACTION_UPDATE = "U"
ACTION_DELETE = "D"

# JOB STATUS VALUES
STATUS_PENDING = "P"
STATUS_RUNNING = "R"
STATUS_DONE = "D"
STATUS_SUPERSEDED = "S"
STATUS_FAILED = "F"

class DbAdapter:
    def fetch_jobs(self, limit: int):
        raise NotImplementedError

    def mark_done(self, job_ids):
        raise NotImplementedError

    def mark_failed(self, job_id, error_text: str):
        raise NotImplementedError

    def fetch_item_document(self, item_id: str):
        raise NotImplementedError