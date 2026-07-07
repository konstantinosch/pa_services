-- CREATE DATABASE indexer_demo
--   CHARACTER SET utf8mb4
--   COLLATE utf8mb4_unicode_ci;

-- USE indexer_demo;

CREATE TABLE items (
    item_id     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    title       TEXT,
    body        TEXT,
    category    VARCHAR(255),
    status      VARCHAR(64),
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE search_index_jobs (
    job_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    entity_type   VARCHAR(64) NOT NULL,
    entity_id     VARCHAR(128) NOT NULL,
    action        CHAR(1) NOT NULL,
    status        CHAR(1) NOT NULL DEFAULT 'P',
    priority      INT NOT NULL DEFAULT 0,
    source        VARCHAR(32) NOT NULL DEFAULT 'live',
    claim_id      CHAR(36) NULL,
    claimed_at    TIMESTAMP NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at    TIMESTAMP NULL,
    finished_at   TIMESTAMP NULL,
    retry_count   INT NOT NULL DEFAULT 0,
    error_text    TEXT,

    PRIMARY KEY (job_id),

    INDEX idx_jobs_pending (
        status,
        priority,
        created_at,
        job_id
    ),

    INDEX idx_jobs_entity (
        entity_type,
        entity_id
    ),

    INDEX idx_jobs_claim (
        claim_id
    ),

    INDEX idx_jobs_source_status (
        source,
        status
    )
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;

INSERT INTO items (title, body, category, status)
VALUES ('First prototype item', 'This row will later become a search document.', 'demo', 'open');

SET @item_id = LAST_INSERT_ID();

INSERT INTO search_index_jobs (entity_type, entity_id, action)
VALUES ('item', CAST(@item_id AS CHAR), 'I');

SELECT * FROM search_index_jobs;




-- UPDATE search_index_jobs
-- SET entity_id = CASE
--     WHEN entity_id % 3 = 1 THEN 1
--     WHEN entity_id % 3 = 2 THEN 2
--     ELSE 3
-- END;
-- UPDATE search_index_jobs SET status = 'P';


-- UPDATE search_index_jobs SET entity_id = 1 WHERE entity_id > 2500;