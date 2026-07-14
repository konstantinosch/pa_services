# ACTION VALUES
ACTION_INSERT = "I" # Insert  -> new entity -> index document
ACTION_UPDATE = "U" # Update  -> existing entity changed -> re-index full document
ACTION_DELETE = "D" # Delete  -> entity removed -> delete from index
# Note:
# - I and U are treated the same in practice: UPSERT
# - D means remove document from search engine


# JOB STATUS VALUES
STATUS_PENDING = "P"
STATUS_RUNNING = "R"
STATUS_DONE = "D"
STATUS_SUPERSEDED = "S"
STATUS_FAILED = "F"

STATE_INDEXED = "indexed"
STATE_DELETED = "deleted"
STATE_FAILED = "failed"

class DbAdapter:
    def fetch_jobs(self, limit: int):
        raise NotImplementedError

    def finalize_batch(self, jobs, winner_ids):
        raise NotImplementedError

    def finalize_successful_jobs(self, jobs, winner_ids, entity_keys):
        raise NotImplementedError

    def release_failed_batch(self, jobs, error_text: str, delay_seconds: int = 0):
        raise NotImplementedError

    def release_or_fail_batch(
        self,
        jobs,
        error_text: str,
        delay_seconds: int = 0,
        max_retries: int = 10,
    ):
        raise NotImplementedError

    def mark_state_indexed(self, job):
        raise NotImplementedError

    def mark_state_deleted(self, job):
        raise NotImplementedError

    def mark_state_failed(self, jobs, error_text: str):
        raise NotImplementedError

    def cleanup_terminal_jobs(self, jobs):
        raise NotImplementedError

    def cleanup_state_covered_terminal_jobs(self, limit: int = 10000):
        raise NotImplementedError

    def reap_stale_jobs(self, stale_seconds: int, delay_seconds: int, limit: int = 1000):
        raise NotImplementedError

    def log_config(self):
        raise NotImplementedError
