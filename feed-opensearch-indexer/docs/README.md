# Indexer Service

This project is a prototype indexing service.

Its purpose is to keep an external search index, currently intended to be
OpenSearch, in sync with source-of-truth relational data.

The important idea:

```text
source DB -> search_index_jobs -> worker -> OpenSearch
                       |
                       -> search_index_state
```

The project combines the job queue / worker coordination layer with the first
real indexing path for `campaign_action` documents. Workers read change jobs,
rebuild the current document from the source MySQL database, and upsert/delete
documents in OpenSearch.

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

### `search_index_state`

This table is present in `sql/indexer/schema_mysql.sql`. Worker updates are the
next implementation step. It keeps one row per indexed source entity:

```text
(entity_type, entity_id)
last indexed job/checkpoint
last indexed time
last action
current indexing status
last error/debug information
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
6. Upsert/delete the OpenSearch document for `campaign_action`.
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

UPDATE campaign_actions
SET feed_visible = 1
WHERE `index` = ?;

INSERT INTO search_index_jobs (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', ?, 'U', 0, 'app');

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
app/worker.py          worker loop
app/reaper.py          stale job ownership recovery
app/config.py          env-based config
app/index_loader.py    initial OpenSearch loader
app/source_mysql.py    source database reader
app/opensearch_indexer.py
                       OpenSearch document writer

db/base.py             action/status constants and adapter interface
db/mysql_adapter.py    MySQL queue implementation
db/factory.py          adapter factory

sql/indexer/schema_mysql.sql
                       current indexer job/state schema

docker/opensearch/     local OpenSearch docker compose
docs/                  design notes and setup notes
```

## Cleanup / Organization TODO

Near-term repo cleanup:

```text
1. Separate indexer-owned SQL from demo SQL.
2. Move demo `items` schema/data into `sql/demo/`.
3. Keep indexer schema in `sql/indexer/schema_mysql.sql`.
4. Add worker updates for `search_index_state`.
5. Add cleanup for terminal jobs covered by state.
6. Add a top-level README or keep this file as the main README.
7. Move huge chat transcripts into `docs/notes/` or archive them.
8. Remove or clearly label personal VM/dev setup notes.
9. Add tests for job collapse and status/state transitions.
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
1. Add `search_index_state` updates after successful indexing.
2. Only delete terminal job rows after state is checkpointed.
3. Decide how permanent failures become F.
4. Generalize document builders beyond `campaign_action`.
5. Add reconciliation/backfill command:
   - find missing state rows
   - find stale indexed rows
   - enqueue repair jobs
6. Add janitor cleanup for terminal jobs covered by state.
```

Operational tooling:

```text
1. Harden `feed_opensearch_ctl.sh doctor` for production handoff.
2. Add deeper config validation.
3. Add DB/schema drift validation.
4. Add reconciliation/backfill checks against `search_index_state`.
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
1. Worker does not populate `search_index_state` yet.
2. Worker does not clean claimed terminal jobs after state update yet.
3. `F` status exists but is not actively used.
4. Automated tests are still thin.
```

The concurrency model is now paired with a real campaign action indexing path.
The next valuable work is making state updates and queue cleanup part of the
worker finalization chain.
