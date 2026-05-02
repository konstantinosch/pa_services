DROP TABLE IF EXISTS search_index_jobs;
CREATE TABLE search_index_jobs (
    job_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    entity_type   VARCHAR(64) NOT NULL,
    entity_id     VARCHAR(128) NOT NULL,
    action        CHAR(1) NOT NULL,
    status        CHAR(1) NOT NULL DEFAULT 'P',
    priority      INT NOT NULL DEFAULT 0,
    source        VARCHAR(32) NOT NULL DEFAULT 'live',
    worker_id     VARCHAR(128) NULL,
    claim_id      CHAR(36) NULL,
    claimed_at    TIMESTAMP NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at    TIMESTAMP NULL,
    finished_at   TIMESTAMP NULL,
    retry_count   INT NOT NULL DEFAULT 0,
    error_text    TEXT,

    PRIMARY KEY (job_id),

    -- Used by the worker to claim the next pending batch:
    -- WHERE status = 'P'
    -- ORDER BY priority DESC, created_at ASC, job_id ASC
    CREATE INDEX idx_jobs_pending_order
    ON search_index_jobs (
        status,
        priority,
        created_at,
        job_id
    );

    -- Used after claiming a batch:
    -- SELECT ...
    -- FROM search_index_jobs
    -- WHERE claim_id = ?
    --
    -- Also used by claim-aware finalize operations:
    -- WHERE claim_id = ? AND status = 'R'
    CREATE INDEX idx_jobs_claim_status
    ON search_index_jobs (
        claim_id,
        status,
        job_id
    );

    -- Used by expanded claim strategy:
    -- Find all other pending jobs for the same entities as the seed batch:
    -- JOIN/WHERE entity_type = ? AND entity_id = ? AND status = 'P'
    CREATE INDEX idx_jobs_entity_status
    ON search_index_jobs (
        entity_type,
        entity_id,
        status,
        job_id
    );

    -- Used for operational monitoring/debugging:
    -- SELECT worker_id, status, COUNT(*)
    -- FROM search_index_jobs
    -- GROUP BY worker_id, status
    --
    -- Also useful when investigating stuck running jobs per daemon instance.
    CREATE INDEX idx_jobs_worker_status
    ON search_index_jobs (
        worker_id,
        status
    );

    -- Used for monitoring job origin:
    -- SELECT source, status, COUNT(*)
    -- FROM search_index_jobs
    -- GROUP BY source, status
    --
    -- Example sources: live, reindex, manual, import
    CREATE INDEX idx_jobs_source_status
    ON search_index_jobs (
        source,
        status
    );

) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
