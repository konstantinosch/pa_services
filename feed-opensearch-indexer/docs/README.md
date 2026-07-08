# Indexer Service

This project is a prototype indexing service.

Its purpose is to keep an external search index, currently intended to be
OpenSearch, in sync with source-of-truth relational data.

The important idea:

```text
source DB -> search_index_jobs -> worker -> OpenSearch
                       |
                       -> search_index_state, planned
```

The project currently focuses mostly on the job queue / worker coordination
side. OpenSearch is set up in Docker/docs, but the worker still only logs
"would upsert/delete" instead of actually writing documents.

## Installation

See [`installation.md`](installation.md) for the first-pass Ubuntu/Debian and CentOS/RHEL installer flow, including dependency setup, `config.env`, Python venv creation, systemd worker/reaper units, logrotate, and local Docker OpenSearch commands.

## Core Tables

### `search_index_jobs`

This is the indexer-owned work queue.

Each row means "something changed for this entity; the search projection should
be refreshed."

Important fields:

```text
entity_type, entity_id  which source entity changed
action                  I/U/D
status                  P/R/D/S/F
claim_id                batch ownership marker
worker_id               which worker claimed it
available_at            retry/backoff/scheduling
retry_count             processing failures
reap_count              stale ownership recoveries
```

Status meaning:

```text
P = pending
R = running
D = done
S = superseded by a newer job for the same entity
F = failed, planned/defined but not really used yet
```

Ownership is separate from status:

```text
R + claim_id != NULL = actively owned by a worker
R + claim_id IS NULL = orphaned/reclaimable running job
```

This separation was added to avoid repeatedly flipping `R -> P`, which caused
deadlock-prone index churn in MySQL.

### `search_index_state` Planned

This table is not implemented yet, but it is the missing piece that explains the
long-term model.

It should keep one row per indexed source entity:

```text
(entity_type, entity_id)
last indexed job/checkpoint
last indexed time
last action
current indexing status
last error/debug information
optional document hash
```

This table acts as the compact "what happened / what is currently indexed"
ledger.

Once `search_index_state` says an entity has been indexed through a given job,
older terminal job rows for that same entity can be safely deleted:

```sql
DELETE FROM search_index_jobs
WHERE entity_type = ?
  AND entity_id = ?
  AND job_id <= ?
  AND status IN ('D', 'S');
```

Do not automatically delete `P`, active `R`, orphaned `R`, or `F` jobs.

## Demo Tables

`items` is not really part of the indexing service.

It is a prototype/demo source table used by the current document builder:

```text
items -> fetch_item_document() -> pretend OpenSearch document
```

Eventually source tables such as `items`, campaigns, users, etc. should live in
the application database/domain, not in the indexer core schema.

## Current Flow

Current worker flow:

```text
1. Fetch/claim pending jobs using FOR UPDATE SKIP LOCKED.
2. Assign one claim_id to the batch.
3. Collapse duplicate jobs by (entity_type, entity_id).
4. Keep only the latest job per entity as the winner.
5. Fetch current source DB state for the winner.
6. Currently log "would upsert/delete".
7. Mark winner jobs D.
8. Mark duplicate jobs S.
```

The worker treats jobs as change signals, not as the source of truth. The final
document is rebuilt from the current source database state.

Current reaper flow:

```text
1. Find stale R jobs with claim_id IS NOT NULL.
2. Clear claim_id / worker_id / claimed timestamps.
3. Leave status as R.
4. The worker can reclaim orphaned R jobs later.
```

The reaper is for recovery only. It should not become the cleanup/deletion
process.

## Trigger vs App-Server Enqueueing

Triggers are not required for the core design.

Two valid enqueue models:

```text
Trigger enqueueing:
DB guarantees every write creates a job, even if writes bypass the app.
Harder to test/version/debug because logic is hidden in the database.

App-server enqueueing:
Application writes source row and job row in the same transaction.
Clearer and easier to test, but every write path must remember to enqueue.
```

Current preference: start with app-server enqueueing.

Example:

```sql
START TRANSACTION;

UPDATE items
SET title = ?, body = ?
WHERE item_id = ?;

INSERT INTO search_index_jobs (entity_type, entity_id, action, priority, source)
VALUES ('item', ?, 'U', 0, 'app');

COMMIT;
```

A later reconciliation/backfill command can find missing or stale indexed
entities by comparing source tables with `search_index_state`.

## What Happens To Old Jobs?

Right now, nothing deletes terminal jobs.

`D` and `S` rows accumulate. `F` is defined but not actively used.

Intended future model:

```text
worker       = indexing work
reaper       = stale running job recovery
janitor      = cleanup of old terminal jobs
state table  = durable per-entity indexing ledger
```

Once `search_index_state` exists, cleanup can be immediate and deterministic per
entity: delete terminal jobs covered by the state checkpoint.

## Current Project Shape

Important current files:

```text
app/daemon.py          worker loop
app/reaper.py          stale job ownership recovery
app/config.py          env-based config
app/seed_data.py       demo item/job seeding

db/base.py             action/status constants and adapter interface
db/mysql_adapter.py    MySQL queue implementation
db/factory.py          adapter factory

sql/schema_mysql.sql   current indexer job schema
sql/demo_data.sql      older demo schema with items + jobs

docker/opensearch/     local OpenSearch docker compose
docs/                  design notes and setup notes
```

## Cleanup / Organization TODO

Near-term repo cleanup:

```text
1. Separate indexer-owned SQL from demo SQL.
2. Move demo `items` schema/data into `sql/demo/`.
3. Keep indexer schema in `sql/indexer/schema_mysql.sql`.
4. Add `search_index_state`.
5. Decide naming: daemon vs worker, reaper vs recovery.
6. Add real `requirements.txt`.
7. Add a top-level README or keep this file as the main README.
8. Move huge chat transcripts into `docs/notes/` or archive them.
9. Remove or clearly label personal VM/dev setup notes.
10. Add tests for job collapse and status/state transitions.
```

Possible target structure:

```text
app/
  worker.py
  reaper.py
  janitor.py
  config.py
  manage.py

indexer/
  jobs.py
  state.py
  documents.py

db/
  base.py
  factory.py
  mysql_adapter.py

search/
  base.py
  opensearch_adapter.py

sql/
  indexer/
    schema_mysql.sql
  demo/
    items_schema.sql
    items_seed.sql
  legacy/

docker/
  opensearch/

docs/
  architecture.md
  setup_dev.md
  operations.md
  notes/
```

## Product TODO

Core functionality:

```text
1. Implement real OpenSearch upsert/delete adapter.
2. Only mark jobs D/S after OpenSearch confirms success.
3. Decide how permanent failures become F.
4. Add `search_index_state` updates after successful indexing.
5. Add reconciliation/backfill command:
   - find missing state rows
   - find stale indexed rows
   - enqueue repair jobs
6. Add janitor cleanup for terminal jobs covered by state.
```

Operational tooling:

```text
1. Add `indexerctl doctor`.
2. Add config validation.
3. Add DB/schema validation.
4. Add safe init-db command.
5. Avoid destructive schema resets unless an explicit force flag is used.
```

Installable service target:

```text
/opt/indexer-service/                         application code
/etc/indexer-service/indexer-service.env      production config/secrets
/var/log/indexer-service/                     logs

systemd:
  indexer-worker.service
  indexer-reaper.service
  indexer-janitor.timer, later
```

Installer responsibilities:

```text
1. Create `indexer` Linux user/group.
2. Install application into `/opt/indexer-service`.
3. Create Python virtualenv.
4. Install requirements.
5. Create `/etc/indexer-service`.
6. Install env template if missing.
7. Install systemd unit files.
8. Run `systemctl daemon-reload`.
9. Do not invent secrets.
10. Do not start services until config/db checks pass.
```

Example future production flow:

```bash
sudo ./scripts/install.sh
sudo cp examples/indexer-service.env /etc/indexer-service/indexer-service.env
sudo nano /etc/indexer-service/indexer-service.env
sudo -u indexer indexerctl doctor
sudo systemctl enable --now indexer-worker indexer-reaper
```

## Current Caveats

Known current gaps:

```text
1. OpenSearch writes are not implemented in the worker.
2. `items` is demo data, not indexer-owned core schema.
3. `search_index_state` is not implemented yet.
4. `F` status exists but is not actively used.
5. No tests yet.
6. No real requirements file yet.
7. No install script/systemd units yet.
8. Some docs are personal setup notes, not production docs.
9. The repo currently contains many modified/untracked files.
```

The concurrency model is more advanced than the rest of the prototype. That is
not wrong, but the next valuable work is making the simple single-worker
indexing path real and making the repo easy to revisit.
