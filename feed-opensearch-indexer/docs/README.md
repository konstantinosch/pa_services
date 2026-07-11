# Indexer Service

This project is an alpha indexing service.

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

## Alpha Status

This is no longer just an experiment folder. It is an alpha deliverable with the
main operational spine in place:

```text
installable service and config flow
local Docker OpenSearch setup
initial OpenSearch loader
systemd worker/reaper instances
MySQL queue and state schema
durable search_index_state ledger
worker retry and failed-state handling
state-checkpointed D/S/F queue cleanup
PHP enqueue helper for the app server
operator checks for DB/source/OpenSearch access
```

It is still alpha because the documentation needs a full professional pass,
repair/requeue commands are not built yet, automated tests are still thin, and
the CentOS/Ubuntu clean install cycles should be repeated before handoff.

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

Status reference:

| Status | Name | Meaning |
| --- | --- | --- |
| `P` | Pending | Waiting to be claimed by a worker. |
| `R` | Running | Claimed now or previously claimed for processing. |
| `D` | Done | Winning job processed successfully. |
| `S` | Superseded | Older duplicate job skipped because a newer job for the same entity won. |
| `F` | Failed | Processing failed at least `WORKER_MAX_RETRIES` times and will not be retried automatically. |

Action reference:

| Action | Meaning |
| --- | --- |
| `I` | Insert/index this entity. |
| `U` | Update/rebuild this entity from MySQL. |
| `D` | Delete this entity from OpenSearch. |

For the current worker, `I` and `U` both mean "refresh this entity from the
source database."

Ownership is separate from status:

| Status | `claim_id` | Meaning |
| --- | --- | --- |
| `R` | not null | Actively owned by a worker. |
| `R` | null | Orphaned/reclaimable running job. |

This separation was added to avoid repeatedly flipping `R -> P`, which caused
deadlock-prone index churn in MySQL.

### `search_index_state`

This table is present in `sql/indexer/schema_mysql.sql`. It keeps one row per
indexed source entity:

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

Workers update it after successful OpenSearch writes:

```text
indexed = document was upserted into OpenSearch
deleted = document was removed from OpenSearch, or source row is no longer feed-visible
failed  = worker processing failed, or the reaper recovered stale ownership
```

Once `search_index_state` says an entity has been indexed through a given job,
the worker deletes older terminal job rows for that same entity:

```sql
DELETE FROM search_index_jobs
WHERE entity_type = ?
  AND entity_id = ?
  AND job_id <= ?
  AND status IN ('D', 'S', 'F');
```

This cleanup intentionally ignores `P`, active `R`, and orphaned `R` jobs.

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

The app only needs to insert rows into `search_index_jobs`.

For campaign actions:

```text
entity_type = campaign_action
entity_id   = campaign_actions.`index`, not campaigns.`index`
action      = producer intent: I, U, or D
priority    = optional ordering hint; default 0
source      = short diagnostic label; example app, admin, repair
```

The app MySQL user needs `INSERT` on:

```text
pa_opensearch_indexer.search_index_jobs
```

Example:

```sql
START TRANSACTION;

UPDATE campaign_actions
SET status = 'closed'
WHERE `index` = ?;

INSERT INTO search_index_jobs (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', ?, 'U', 0, 'app');

COMMIT;
```

A later reconciliation/backfill command can find missing or stale indexed
entities by comparing source tables with `search_index_state`.

See `examples/php/feed_opensearch_enqueue.php` for a minimal PDO helper.

## What Happens To Old Jobs?

The worker deletes terminal `D`, `S`, and `F` rows after `search_index_state`
contains the durable checkpoint for that entity.

Cleanup has two paths:

```text
entity-scoped cleanup = removes terminal rows for the just-processed batch
global cleanup        = bounded sweep for older state-covered terminal rows
state table           = durable per-entity indexing ledger
```

Manual cleanup command:

```bash
./feed_opensearch_ctl.sh db:cleanup-jobs
./feed_opensearch_ctl.sh db:cleanup-jobs 50000
```

Failed rows are cleaned like other terminal rows once `search_index_state`
contains the failed checkpoint. Operators can inspect failures from
`search_index_state`, then requeue them by inserting fresh `P` jobs from that
state.

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
4. Promote this document into the polished top-level README.
5. Move huge chat transcripts into `docs/notes/` or archive them.
6. Remove or clearly label personal VM/dev setup notes.
7. Add tests for job collapse and status/state transitions.
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

Near-term product work:

```text
1. Add failed-state operator commands:
   - db:failed:list
   - db:failed:requeue
   - db:failed:cleanup, if we later want explicit state cleanup
2. Add reconciliation/backfill command:
   - find missing state rows
   - find stale indexed rows
   - enqueue repair jobs
3. Generalize document builders beyond `campaign_action`, if new entity types
   become part of the deliverable.
4. Add clearer worker/reaper batch summary logs:
   - indexed
   - deleted
   - failed/released
   - terminal-cleaned
```

Operational tooling:

```text
1. Repeat clean install/uninstall cycles on Ubuntu and CentOS.
2. Harden `feed_opensearch_ctl.sh doctor` for production handoff.
3. Add deeper config validation.
4. Add DB/schema drift validation.
5. Add OpenSearch/document count monitoring examples.
6. Add recovery/repair runbooks:
   - server reboot
   - Docker/OpenSearch restart
   - MySQL outage
   - source DB permission failure
```

Documentation pass:

```text
1. Rewrite the README for delivery:
   - purpose
   - architecture
   - install order
   - configuration
   - operation
   - troubleshooting
2. Document action vs index_status semantics:
   - last_action = producer intent: I/U/D
   - index_status = indexer outcome: indexed/deleted/failed
   - U + deleted is valid when feed_visible becomes false
   - D + deleted is valid for explicit source deletion
3. Document required MySQL grants:
   - pa_indexer reads source tables
   - app user inserts search_index_jobs
4. Document PHP enqueue integration and transaction expectations.
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
1. Automated tests are still thin.
```

The concurrency model is now paired with a real campaign action indexing path.
The worker now updates `search_index_state`, marks queue rows terminal, and
removes terminal queue rows that are covered by the state checkpoint.
Repeated worker failures are capped by `WORKER_MAX_RETRIES`; exhausted jobs move
to `F` and `search_index_state` records `failed`.
