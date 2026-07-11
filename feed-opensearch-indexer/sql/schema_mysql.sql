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
    available_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at    TIMESTAMP NULL,
    finished_at   TIMESTAMP NULL,
    retry_count   INT NOT NULL DEFAULT 0,
    reap_count    INT NOT NULL DEFAULT 0,
    error_text    TEXT,

    PRIMARY KEY (job_id),

    -- Worker claims next pending batch
    INDEX idx_jobs_pending_order (
        status,
        priority,
        created_at,
        job_id
    ),

    -- Fetch/finalize claimed batch
    INDEX idx_jobs_claim_status (
        claim_id,
        status,
        job_id
    ),

    -- Expanded claim: find pending jobs for same entities
    INDEX idx_jobs_entity_status (
        entity_type,
        entity_id,
        status,
        job_id
    ),

    -- Monitoring/debug by worker instance
    INDEX idx_jobs_worker_status (
        worker_id,
        status
    ),

    -- Monitoring by job origin
    INDEX idx_jobs_source_status (
        source,
        status
    )
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
