# Feed OpenSearch Indexer

This service keeps an OpenSearch index aligned with the relational source of truth for feed-facing campaign actions. It is built as a queue-driven pipeline: application or integration code writes a change signal, a worker rebuilds the latest document from MySQL, and the worker upserts or deletes the matching OpenSearch document.

The current implementation focuses on campaign-action documents, but the queue and state model are generic enough to support additional entity types later.

---

## What this service does

At a high level, the flow is:

1. A source change is represented as a queue job in MySQL.
2. A worker claims the pending job and rebuilds the current document from the source database.
3. The worker writes the result to OpenSearch.
4. A reaper recovers stale ownership when a worker goes away or loses its claim.

The service therefore combines three pieces:

- a durable MySQL job queue
- a worker/reaper runtime for processing and recovery
- an OpenSearch indexing path for the feed data model

---

## Architecture at a glance

```text
source DB -> search_index_jobs -> worker -> OpenSearch
                       |
                       -> search_index_state
```

### Main components

- Worker: claims pending jobs, rebuilds the current document from MySQL, and writes to OpenSearch.
- Reaper: releases stale running jobs when ownership appears abandoned.
- Loader: performs initial bulk indexing from the source database.
- Control script: provides the install/configure/manage entrypoint for the whole service.

---

## Core concepts

### Queue table: search_index_jobs

This is the indexer-owned work queue. Each row is a signal that something changed and the search projection should be refreshed.

Important fields:

- entity_type / entity_id: identifies the affected source entity
- action: I, U, or D
- status: P, R, D, S, or F
- claim_id / worker_id: ownership markers for in-flight work
- retry_count / reap_count: retry and recovery counters

Status meanings:

| Status | Meaning |
| --- | --- |
| P | Pending. The job is waiting to be claimed by a worker. |
| R | Running. The job has been claimed and is currently being processed, or it is a stale running job waiting to be reclaimed. |
| D | Done. The job was processed successfully and the indexed state for that entity is now considered current. |
| S | Superseded. A newer job for the same entity arrived, so this older job was collapsed and skipped. |
| F | Failed. The job exhausted its retry budget and is no longer retried automatically. |

Action meanings:

| Action | Meaning |
| --- | --- |
| I | Insert or index. The entity should be created or refreshed in OpenSearch. |
| U | Update or rebuild. The current document should be rebuilt from the source database and written back to OpenSearch. |
| D | Delete. The document should be removed from OpenSearch. |

Batching and collapsing:

Workers do not process every queued row blindly. They claim a batch of eligible jobs, collapse duplicate work for the same entity, and keep only the latest job as the winner. That means a new update can supersede an older one, reducing redundant work and making the queue behave more like a change stream than a list of independent tasks.

### State ledger: search_index_state

This table keeps a durable per-entity checkpoint of what was last indexed or failed. It is the authoritative compact ledger for cleanup and reconciliation.

A key design detail is that ownership and status are separate:

- R with claim_id set = actively owned by a worker
- R with claim_id null = orphaned/reclaimable

That separation avoids the old churn of repeatedly flipping running jobs back to pending.

### Queue concurrency model

The worker uses a deterministic locking approach to claim jobs safely and avoid
the deadlocks that came from older update-heavy patterns. The current flow is
based on selecting eligible jobs, using `FOR UPDATE SKIP LOCKED` to claim them
without blocking on already-locked rows, and then updating by primary key rather
than rewriting the same rows through broad update joins.

The early design used broader update patterns, including update joins against
the same queue table. Those are risky under concurrency because MySQL can lock
secondary-index ranges in different orders for different workers. Another
problematic pattern was stale recovery that changed jobs from `R` back to `P`;
that rewrote the indexed `status` column while other workers were scanning and
locking pending rows.

The current design avoids those failure modes:

1. Select a small deterministic seed batch.
2. Lock eligible rows with `FOR UPDATE SKIP LOCKED`.
3. Expand by entity only through ordered primary-key row locks.
4. Update claimed rows by primary key.
5. Keep stale recovery as ownership cleanup, not `R -> P` status churn.

Instead of treating status as ownership, the queue uses a two-part coordination
model:

- `status` describes the lifecycle state of the job: pending, running, done, superseded, or failed.
- `claim_id` describes ownership for in-flight work. A running job with a claim is considered actively owned; a running job without a claim is orphaned/reclaimable.

That split is what keeps multiple workers and reapers from getting tangled up. Workers only claim jobs that are pending or orphaned-running, and a reaper can recover stale ownership by clearing claim information without converting the job back to pending. This prevents workers from fighting over the same row, avoids oscillation between `R` and `P`, and keeps the system safe under concurrent processing.

Practical rules for future changes:

- Prefer primary-key updates after selecting/locking job IDs.
- Avoid update joins that rewrite `search_index_jobs` while workers are also
  claiming from it.
- Avoid unnecessary writes to indexed coordination columns such as `status`.
- Keep transactions short and ordered by `job_id` where possible.
- Treat MySQL deadlocks and lock-wait timeouts as retryable database events.
- Use `available_at` for retry backoff, scheduling, or throttling; it is not the
  core correctness mechanism.

### Source visibility rule

For campaign actions, the worker rebuilds the document from the source row and uses the same visibility logic as the loader. Visibility is a special boolean-style decision derived from denormalized campaign information plus specific values on the campaign action itself, and it is reduced to a binary choice: either the action is feed-visible and should be indexed, or it is not and the document should be removed from OpenSearch. In other words, the service does not index stale or hidden rows just because a queue job exists; it checks the current source state and only keeps the document when the current visibility criteria still pass.

### Worker flow

The worker follows a simple lifecycle for each batch of jobs:

1. Fetch eligible pending jobs and orphaned running jobs using `FOR UPDATE SKIP LOCKED`.
2. Assign a batch-level claim so the batch is treated as a single ownership unit.
3. Collapse duplicate jobs by `(entity_type, entity_id)` and keep only the newest job as the winner.
4. Rebuild the document from the current source database state.
5. Upsert or delete the OpenSearch document for the winning entity.
6. Mark the winning job as done and mark the collapsed duplicates as superseded.

The worker treats queue rows as change signals, not as the source of truth. The final document is rebuilt from the latest database state at processing time.

### Reaper flow

The reaper is responsible for recovery, not cleanup. Its job is to find running jobs that appear stale because their claim never got cleared, then release ownership without changing the job back to pending:

1. Find running jobs with an active claim that have been running longer than the configured stale threshold.
2. Clear `claim_id`, `worker_id`, and related ownership timestamps.
3. Leave the job in running state so it can be reclaimed later by a worker if needed.

This prevents the queue from oscillating between `R` and `P` and keeps ownership recovery separate from normal processing.

### When jobs are removed

The queue is not kept forever. Terminal rows are removed once the durable state table has a checkpoint for the same entity. In practice:

- done, superseded, and failed jobs can be cleaned up after `search_index_state` records a durable outcome for the entity
- cleanup happens in two ways: entity-scoped cleanup for the just-processed batch and a bounded global sweep for older terminal rows
- the state table is the durable log of what happened and what is currently indexed for that entity

That makes `search_index_state` the main place to inspect the last successful or failed outcome for an entity, while the queue table remains primarily a work queue and not the long-term history store.

### Failure handling

Failures are handled in two layers:

- transient processing failures are retried according to the retry policy until the configured maximum is reached
- once a job reaches the failure threshold, it becomes a failed terminal job and is no longer retried automatically

The worker records failure context and the reaper can recover stale ownership without turning a legitimate running job into a fresh pending job. Operators can inspect failed state from `search_index_state`, then requeue work by inserting a fresh pending job if reconciliation is needed.

---

## Quick start

From the service directory:

```bash
cd /opt/pa_services/feed-opensearch-indexer

./feed_opensearch_ctl.sh doctor
./feed_opensearch_ctl.sh install-deps
./feed_opensearch_ctl.sh setup-venv
./feed_opensearch_ctl.sh init-config
./feed_opensearch_ctl.sh configure
./feed_opensearch_ctl.sh db:install
./feed_opensearch_ctl.sh db:status
./feed_opensearch_ctl.sh source:status
./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh fix-permissions
./feed_opensearch_ctl.sh worker:check
./feed_opensearch_ctl.sh reaper:check
```

If you are using the bundled local OpenSearch container, continue with:

```bash
./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:load
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status
```

---

## Installation

The main entrypoint is the control script:

```bash
/opt/pa_services/feed-opensearch-indexer/feed_opensearch_ctl.sh
```

### 1. Prerequisites

The service expects:

- Python 3 and a virtual environment
- MySQL client access and an external MySQL server
- OpenSearch access, either via a managed external cluster or the bundled local container
- systemd for worker and reaper daemons
- Docker only when you want to run the bundled local OpenSearch service

### 2. Bootstrap the runtime

Run the standard install sequence:

```bash
./feed_opensearch_ctl.sh doctor
./feed_opensearch_ctl.sh install-deps
./feed_opensearch_ctl.sh setup-venv
./feed_opensearch_ctl.sh init-config
./feed_opensearch_ctl.sh configure
```

The installer uses the service directory for its runtime state and logs.

### 3. Bootstrap MySQL

The indexer uses a dedicated MySQL database and runtime user for queue control and state. The control script can create or inspect those pieces:

```bash
./feed_opensearch_ctl.sh db:install
./feed_opensearch_ctl.sh db:status
./feed_opensearch_ctl.sh show-db-sql
./feed_opensearch_ctl.sh db:schema
```

The schema files live in:

- sql/indexer/schema_mysql.sql

This creates the queue and state tables used by the worker and reaper.

### 4. Bootstrap OpenSearch

The service can work with either:

- an external OpenSearch endpoint, configured through OPENSEARCH_URL, or
- the bundled local Docker container for development and tests

For the bundled local path:

```bash
./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:health
```

### 5. Install service account and daemons

The worker and reaper should run as a dedicated Linux service account. The control script can create that user and install systemd units:

```bash
./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh fix-permissions
```

---

### Typical installation flow (example)

The following is a practical end-to-end example for a fresh host. It is meant as a copy/paste-friendly reference rather than a strict requirement for every environment. It assumes you want the bundled local OpenSearch container; if you already have an external OpenSearch endpoint, skip the Docker and local-container steps and point `OPENSEARCH_URL` at that service instead.

```bash
cd /opt/pa_services/feed-opensearch-indexer

./feed_opensearch_ctl.sh doctor
./feed_opensearch_ctl.sh install-deps
./feed_opensearch_ctl.sh setup-venv
./feed_opensearch_ctl.sh init-config
./feed_opensearch_ctl.sh configure

./feed_opensearch_ctl.sh db:install
./feed_opensearch_ctl.sh db:status
./feed_opensearch_ctl.sh source:status

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run hello-world

# CentOS/RHEL
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run hello-world

./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:load

./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh fix-permissions
./feed_opensearch_ctl.sh worker:check
./feed_opensearch_ctl.sh reaper:check
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status
```

---

## Application enqueue examples

The application-side enqueue path is intentionally simple: write the source change, then insert a row into `search_index_jobs` with the appropriate action. The PHP helper in [examples/php/feed_opensearch_enqueue.php](examples/php/feed_opensearch_enqueue.php) shows the general pattern, and the examples below cover the three main cases.

The examples show the two logical operations separately. They are not meant to
force a specific transaction shape. If the source database and indexer database
are on the same MySQL server and the application user has the right grants, the
application may choose to enqueue in the same transaction as the source write.
If not, enqueue immediately after the source write commits and let the indexer
remain eventually consistent.

### 1. Updated campaign action

Use an update action when a campaign action changed in a way that should refresh the OpenSearch document from the current source state.

```sql
UPDATE deedspot.campaign_actions
SET title = 'Updated title', modified_at = UNIX_TIMESTAMP()
WHERE `index` = ?;
```

```sql
INSERT INTO pa_opensearch_indexer.search_index_jobs
  (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', ?, 'U', 0, 'app');
```

See [examples/php/feed_opensearch_enqueue.php](examples/php/feed_opensearch_enqueue.php) for the same pattern in PHP.

### 2. Campaign action becomes not visible

Use an update action when the action is still changing, but the current source state means it should no longer be indexed. A common example is closing the action: the worker will rebuild the document, see that the action is no longer feed-visible, and remove the document from OpenSearch.

```sql
UPDATE deedspot.campaign_actions
SET status = 'closed'
WHERE `index` = ?;
```

```sql
-- This is still an update job, but the indexer will remove the document
-- from OpenSearch because the current state is no longer feed-visible.
INSERT INTO pa_opensearch_indexer.search_index_jobs
  (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', ?, 'U', 0, 'app');
```

See [examples/php/feed_opensearch_enqueue.php](examples/php/feed_opensearch_enqueue.php) for the same pattern in PHP.

### 3. Deleted campaign action

Use a delete action when the source row is being removed and the corresponding OpenSearch document should also disappear.

```sql
DELETE FROM deedspot.campaign_actions
WHERE `index` = ?;
```

```sql
INSERT INTO pa_opensearch_indexer.search_index_jobs
  (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', ?, 'D', 0, 'app');
```

See [examples/php/feed_opensearch_enqueue.php](examples/php/feed_opensearch_enqueue.php) for the same pattern in PHP.

---

## Configuration

The main runtime config file is:

```bash
/opt/pa_services/feed-opensearch-indexer/config.env
```

Create it from the example file:

```bash
./feed_opensearch_ctl.sh init-config
```

The example config is in [config.example.env](config.example.env).

### MySQL configuration

The service uses two MySQL roles:

- MYSQL_*: the indexer queue/control database
- SOURCE_MYSQL_*: the application/source database used to rebuild documents

Typical settings include:

```bash
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=pa_indexer
MYSQL_PASSWORD='...'
MYSQL_DATABASE=pa_opensearch_indexer

SOURCE_MYSQL_HOST=localhost
SOURCE_MYSQL_PORT=3306
SOURCE_MYSQL_USER=''
SOURCE_MYSQL_PASSWORD=''
SOURCE_MYSQL_DATABASE=deedspot
SOURCE_MYSQL_BIN=mysql
SOURCE_MYSQL_SUDO=1
```

If SOURCE_MYSQL_USER is empty, the worker will reuse the indexer MySQL credentials; for production, it is better to provide a dedicated read-only source user.

The source user must be able to read the source tables used by the OpenSearch document SQL. For local testing with the bundled `deedspot` database, the simplest grant is:

```bash
sudo mysql -e "GRANT SELECT ON deedspot.* TO 'pa_indexer'@'localhost'; FLUSH PRIVILEGES;"
./feed_opensearch_ctl.sh source:status
```

### OpenSearch configuration

Key settings:

```bash
OPENSEARCH_URL=http://localhost:9200
OPENSEARCH_INDEX=campaign_actions_feed
OPENSEARCH_USERNAME=''
OPENSEARCH_PASSWORD=''
OPENSEARCH_TIMEOUT_SECONDS=10
OPENSEARCH_WAIT_SECONDS=90
```

### Worker and reaper tuning

Important runtime knobs:

```bash
WORKER_BATCH_SIZE=100
WORKER_MAX_RETRIES=10
JOB_CLEANUP_BATCH_SIZE=10000
REAPER_STALE_SECONDS=120
REAPER_RELEASE_DELAY_SECONDS=30
WORKER_COUNT=1
REAPER_COUNT=1
```

### Logging and service account

```bash
LOG_FILE=logs/pa_opensearch_indexer.log
SERVICE_USER=pa_indexer
SERVICE_GROUP=pa_indexer
```

---

## Initial indexing and bulk load

The initial loader is exposed through the control script and reads from the source database rather than the queue database.

Dry-run the scan without writing OpenSearch:

```bash
./feed_opensearch_ctl.sh opensearch:load:dry-run
```

Create the index if missing and bulk upsert all visible campaign actions:

```bash
./feed_opensearch_ctl.sh opensearch:load
```

Delete and rebuild the index from scratch:

```bash
./feed_opensearch_ctl.sh opensearch:rebuild
```

The loader uses the SQL definition in:

- sql/opensearch/campaign_actions_feed_full_index.sql

and pages through the source rows using the configured page size:

```bash
OPENSEARCH_LOADER_PAGE_SIZE=10000
```

---

## Management and operations

### Service lifecycle

```bash
./feed_opensearch_ctl.sh services:start
./feed_opensearch_ctl.sh services:stop
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status
./feed_opensearch_ctl.sh services:logs
./feed_opensearch_ctl.sh services:logs:follow
```

Journal commands show the latest 100 lines by default. Override that with `JOURNAL_LINES`:

```bash
JOURNAL_LINES=300 ./feed_opensearch_ctl.sh worker:logs
JOURNAL_LINES=50 ./feed_opensearch_ctl.sh services:logs:follow
```

For live monitoring across all configured worker and reaper instances, prefer `services:logs:follow`.

### Worker and reaper control

```bash
./feed_opensearch_ctl.sh worker:start
./feed_opensearch_ctl.sh worker:stop
./feed_opensearch_ctl.sh worker:restart
./feed_opensearch_ctl.sh worker:status
./feed_opensearch_ctl.sh worker:logs

./feed_opensearch_ctl.sh reaper:start
./feed_opensearch_ctl.sh reaper:stop
./feed_opensearch_ctl.sh reaper:restart
./feed_opensearch_ctl.sh reaper:status
./feed_opensearch_ctl.sh reaper:logs
```

### Foreground runs for debugging

```bash
./feed_opensearch_ctl.sh worker:run
./feed_opensearch_ctl.sh reaper:run
```

### OpenSearch management

```bash
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:status
./feed_opensearch_ctl.sh opensearch:logs
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:index:show
./feed_opensearch_ctl.sh opensearch:index:reset
./feed_opensearch_ctl.sh opensearch:index:delete
```

### Queue cleanup

The service can remove terminal jobs that are already covered by the durable state ledger:

```bash
./feed_opensearch_ctl.sh db:cleanup-jobs
./feed_opensearch_ctl.sh db:cleanup-jobs 50000
```

### Uninstall and teardown

The default uninstall command is non-interactive. It removes managed install state while keeping the project files in place:

```bash
./feed_opensearch_ctl.sh uninstall
```

It removes:

- systemd worker/reaper units
- the logrotate configuration
- `OPENSEARCH_INDEX`
- bundled OpenSearch containers and volumes
- the indexer MySQL database and runtime user
- the Linux service user
- runtime logs

It does not remove `/opt/pa_services` or the checked-out project files.

For selective cleanup, use the interactive path:

```bash
./feed_opensearch_ctl.sh uninstall-interactive
```

The interactive OpenSearch choices are split deliberately:

```text
opensearch-index [keep] (keep remove)
opensearch-containers [keep] (keep stop down down-volumes)
```

`remove` deletes only `OPENSEARCH_INDEX` through the OpenSearch HTTP API. `stop` stops the bundled container without deleting it. `down` removes the bundled Docker Compose container and network. `down-volumes` also removes the Docker volume, which destroys all local OpenSearch index data stored by that container.

For only MySQL cleanup:

```bash
./feed_opensearch_ctl.sh db:uninstall
```

For repeat test teardown, the non-interactive drop shortcut removes the configured indexer database and MySQL runtime user immediately:

```bash
./feed_opensearch_ctl.sh db:drop
```

`db:uninstall` destructive paths require typed confirmation. `db:drop` is intentionally non-interactive and should only be used when `MYSQL_DATABASE` and `MYSQL_USER` are known test/install targets.

---

## Operational notes and useful details

### Routine health checks

After installation, these commands give a quick view of whether the service survived routine trouble such as reboot, power loss, Docker restart, MySQL restart, or OpenSearch restart:

```bash
./feed_opensearch_ctl.sh services:status
./feed_opensearch_ctl.sh services:logs
./feed_opensearch_ctl.sh db:status
./feed_opensearch_ctl.sh source:status
./feed_opensearch_ctl.sh opensearch:health
curl http://localhost:9200/campaign_actions_feed/_count?pretty
sudo mysql deedspot -e "SELECT COUNT(*) FROM campaign_actions WHERE feed_visible = 1;"
```

The intended recovery model is:

- systemd restarts worker and reaper instances after reboot
- Docker restarts the bundled OpenSearch container when configured to do so
- the reaper releases stale running jobs after `REAPER_STALE_SECONDS`
- released jobs wait `REAPER_RELEASE_DELAY_SECONDS` before another worker can reclaim them
- the initial loader can rebuild OpenSearch from the source database if local index data is lost

Planned operator commands:

```bash
./feed_opensearch_ctl.sh verify
./feed_opensearch_ctl.sh queue:status
./feed_opensearch_ctl.sh opensearch:count
./feed_opensearch_ctl.sh opensearch:drift
```

### Local OpenSearch with Docker

The bundled local OpenSearch setup is a development convenience. It runs a single-node OpenSearch instance with security disabled. For production, point OPENSEARCH_URL at a managed OpenSearch deployment instead.

The compose file is in:

- docker/opensearch/docker-compose.yml

### Why the queue model is structured this way

The service was designed to avoid a fragile model where running jobs are repeatedly flipped back and forth between pending and running. The current design keeps queue status and claim ownership distinct so the reaper can safely recover stale work without causing churn.

---

## Troubleshooting

Start with the built-in health checks:

```bash
./feed_opensearch_ctl.sh doctor
./feed_opensearch_ctl.sh worker:check
./feed_opensearch_ctl.sh reaper:check
./feed_opensearch_ctl.sh services:status
```

Common issues and fixes:

- Permission denied on config.env: rerun fix-permissions and confirm the service account can read the config and repo.
- MySQL access failures: verify the queue DB credentials and the source DB grants.
- OpenSearch connection failures: verify OPENSEARCH_URL and the health endpoint.
- Missing index: create it with opensearch:index:create and rebuild if needed.
- Stale running jobs: let the reaper recover them or inspect the queue state table.
- Docker access problems: ensure the deployer account can reach Docker, or use sudo-compatible access for the control script.

---
