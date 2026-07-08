--CREATE DATABASE search_prototype;

CREATE TABLE items (
    item_id     BIGSERIAL PRIMARY KEY,
    title       TEXT,
    body        TEXT,
    category    TEXT,
    status      TEXT,
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE search_index_jobs (
    job_id        BIGSERIAL PRIMARY KEY,
    entity_type   TEXT NOT NULL,
    entity_id     TEXT NOT NULL,
    action        CHAR(1) NOT NULL,
    status        CHAR(1) NOT NULL DEFAULT 'P',
    priority      INTEGER DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT now(),
    started_at    TIMESTAMPTZ,
    finished_at   TIMESTAMPTZ,
    retry_count   INTEGER DEFAULT 0,
    error_text    TEXT
);

INSERT INTO items (title, body, category, status)
VALUES ('First prototype item', 'This row will later become a search document.', 'demo', 'open')
RETURNING item_id;

INSERT INTO search_index_jobs (entity_type, entity_id, action)
VALUES ('item', '1', 'I');

SELECT * FROM search_index_jobs;