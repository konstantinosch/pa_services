# Feed OpenSearch Indexer Installation

This service is the queue-consuming side of the feed indexing stack. It keeps an
OpenSearch index eventually aligned with the relational source of truth by
claiming rows from `search_index_jobs`, processing them in batches, and
recovering stale claims with a separate reaper process.

The worker processes `campaign_action` queue jobs by rebuilding the source
document from MySQL and upserting or deleting the matching OpenSearch document.
The installer scaffolding below prepares the project as a deliverable service.

## Supported Hosts

The control script detects OS family from `/etc/os-release` and supports the two
families we care about first:

- Ubuntu/Debian via `apt-get`
- CentOS/RHEL-like hosts via `dnf` or `yum`

Both families use `systemd` for the long-running worker and reaper. MySQL is
treated as an external prerequisite: the installer does not install or manage
MySQL, but `doctor` checks that the `mysql` client exists. Local OpenSearch for
development uses Docker Compose when Docker is available. Production can point
the later OpenSearch adapter at an external OpenSearch URL instead of running
the bundled container.

## First Install

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
sudo usermod -aG pa_indexer "$USER"
newgrp pa_indexer
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh fix-permissions
```

`install-deps` installs common base packages for the service runtime, but it
does not install MySQL. Docker packaging differs more on CentOS/RHEL systems, so
the script reports Docker status in `doctor` and leaves site-specific
Docker/Podman choices explicit.

## Recommended Full Install Order

This is the recommended clean-host order when using the bundled local
OpenSearch container. Install Docker after base configuration and database setup,
but before `opensearch:install`.

```bash
cd /opt/pa_services/feed-opensearch-indexer

./feed_opensearch_ctl.sh doctor
./feed_opensearch_ctl.sh install-deps
./feed_opensearch_ctl.sh setup-venv
./feed_opensearch_ctl.sh init-config
./feed_opensearch_ctl.sh configure

./feed_opensearch_ctl.sh db:install
./feed_opensearch_ctl.sh db:status

# temporary note - dont forget the pa_indexer db user has to access
# the host db (deedspot)
sudo mysql -e "GRANT SELECT ON deedspot.* TO 'pa_indexer'@'localhost'; FLUSH PRIVILEGES;"
./feed_opensearch_ctl.sh source:status

# If doctor reports "miss command docker", install Docker now.
# See "Docker Engine Setup" below.

#centos:
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run hello-world


#Ubuntu
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

./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:load:dry-run
./feed_opensearch_ctl.sh opensearch:load

./feed_opensearch_ctl.sh install-service-user

# If the deployer account should keep running control commands:
sudo usermod -aG pa_indexer "$USER"
newgrp pa_indexer

./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh fix-permissions
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status
```

## Configuration

`config.env` is loaded by the control script and exported to the Python worker.
Create it from the example:

```bash
./feed_opensearch_ctl.sh init-config
```

Or write it interactively:

```bash
./feed_opensearch_ctl.sh configure
```

The default example is `config.example.env`. Keep real passwords in `config.env`
only; it should be deployed with private permissions. `doctor` reports whether
`MYSQL_PASSWORD` is set without printing the secret.

There are two MySQL roles in this service:

```bash
MYSQL_*
```

The indexer queue/control database. This owns `search_index_jobs`, worker claims,
retries, and reaper state.

```bash
SOURCE_MYSQL_*
```

The production/application source database. This owns tables such as
`campaign_actions`, `campaigns_tags`, and `campaign_tags`, and is read when
building OpenSearch documents.

The default local/development loader path uses socket-authenticated sudo access
for bulk loads from the control script:

```bash
SOURCE_MYSQL_DATABASE=deedspot
SOURCE_MYSQL_BIN=mysql
SOURCE_MYSQL_SUDO=1
```

The worker service itself uses a normal MySQL client connection. If
`SOURCE_MYSQL_USER` is empty, it reuses `MYSQL_USER`/`MYSQL_PASSWORD`, which is
usually `pa_indexer`. Grant that user read access to the source tables, or set
an explicit read-only source DB user:

```bash
SOURCE_MYSQL_HOST=localhost
SOURCE_MYSQL_PORT=3306
SOURCE_MYSQL_USER=app_readonly_user
SOURCE_MYSQL_PASSWORD='change-me'
SOURCE_MYSQL_DATABASE=deedspot
SOURCE_MYSQL_BIN=mysql
SOURCE_MYSQL_SUDO=0
```

## MySQL Bootstrap

MySQL server itself is external to this service, but the indexer database, runtime
user, grants, and queue table are owned by this installer.

The intended names are:

```bash
MYSQL_DATABASE=pa_opensearch_indexer
MYSQL_USER=pa_indexer
SERVICE_USER=pa_indexer
SERVICE_GROUP=pa_indexer
LOG_FILE=logs/pa_opensearch_indexer.log
```

The example config ships with a strong placeholder password and defaults to
admin bootstrap through `sudo mysql`. Change `MYSQL_PASSWORD` for production,
and adjust `MYSQL_ADMIN_BIN` / `MYSQL_ADMIN_ARGS` only if the host uses a
different MySQL admin path.

Default socket-authenticated local root via sudo:

```bash
MYSQL_BIN=mysql
MYSQL_ADMIN_BIN=sudo
MYSQL_ADMIN_ARGS=mysql
MYSQL_PASSWORD='Pa_Indexer_2026!ChangeMe'
```

Alternative MySQL root password prompt:

```bash
MYSQL_BIN=mysql
MYSQL_ADMIN_BIN=mysql
MYSQL_ADMIN_ARGS="-u root -p"
```

Then run:

```bash
./feed_opensearch_ctl.sh db:install
./feed_opensearch_ctl.sh db:status
```

`db:install` asks separately what to do with the database, runtime user/grants,
and schema. The safe defaults are to create missing pieces and preserve existing
data. Destructive options are available as `drop-recreate`, but they require
typing the exact database or user name before anything is dropped.

To manage only the queue table after the database/user already exist:

```bash
./feed_opensearch_ctl.sh db:schema
```

To print the database/user/grant SQL without executing it:

```bash
./feed_opensearch_ctl.sh show-db-sql
```

The schema file used by the installer is
`sql/indexer/schema_mysql.sql`. It creates `search_index_jobs` and
`search_index_state` with `CREATE TABLE IF NOT EXISTS`.


## Linux Service User

The systemd worker and reaper should run as the dedicated locked-down Linux user
`pa_indexer`, not as the deployer account. Create it and apply ownership after
configuration and before installing systemd units:

```bash
./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh fix-permissions
```

Run `fix-permissions` again after changing `config.env`, recopying the project,
or before restarting services at the end of installation. The services read the
same config as `pa_indexer`, so this catches the common `config.env: Permission
denied` failure before the worker starts. It also grants the service group
traverse permission on the parent install directory, such as `/opt/pa_services`,
so systemd can reach `feed_opensearch_ctl.sh`.

The generated units use `SERVICE_USER` and `SERVICE_GROUP`, both defaulting to
`pa_indexer`.

## Service Management

Install generated systemd units:

```bash
./feed_opensearch_ctl.sh install-systemd
```

Preview the unit files without installing:

```bash
./feed_opensearch_ctl.sh show-systemd
```

Start and inspect services:

```bash
./feed_opensearch_ctl.sh fix-permissions
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status
./feed_opensearch_ctl.sh services:logs
./feed_opensearch_ctl.sh services:logs:follow
./feed_opensearch_ctl.sh services:stop
```

Journal commands show the latest 100 lines by default. Override with
`JOURNAL_LINES`:

```bash
JOURNAL_LINES=300 ./feed_opensearch_ctl.sh worker:logs
JOURNAL_LINES=50 ./feed_opensearch_ctl.sh services:logs:follow
```

For live monitoring across all configured worker and reaper instances, prefer
`services:logs:follow`.

The service uses systemd template instances. Multiplicity is controlled in
`config.env`:

```bash
WORKER_COUNT=4
REAPER_COUNT=1
```

With those values, `install-systemd` and `services:*` manage units such as
`pa-feed-opensearch-worker@1.service` through
`pa-feed-opensearch-worker@4.service`, plus `pa-feed-opensearch-reaper@1.service`.
Each worker/reaper is supervised independently by systemd.

Foreground runs remain available for development:

```bash
./feed_opensearch_ctl.sh worker:run
./feed_opensearch_ctl.sh reaper:run
```

## Uninstall

The default uninstall command is non-interactive and removes managed install
state while keeping project files in place:

```bash
./feed_opensearch_ctl.sh uninstall
```

It removes systemd units, logrotate config, `OPENSEARCH_INDEX`, bundled
OpenSearch containers and volumes, the indexer MySQL database/user, the Linux
service user, and logs. It does not remove `/opt/pa_services` project files.

For selective cleanup, use the interactive path:

```bash
./feed_opensearch_ctl.sh uninstall-interactive
```

It asks separately about systemd units, logrotate, OpenSearch index/container
state, MySQL objects, the Linux service user, and logs.

OpenSearch uninstall choices are split deliberately:

```bash
opensearch-index [keep] (keep remove)
opensearch-containers [keep] (keep stop down down-volumes)
```

`remove` deletes only `OPENSEARCH_INDEX` through the OpenSearch HTTP API.
`down-volumes` removes the bundled Docker Compose volume and therefore all
local OpenSearch index data for that container.

For only MySQL cleanup:

```bash
./feed_opensearch_ctl.sh db:uninstall
```

For repeat test teardown, the non-interactive drop shortcut removes the indexer
database and MySQL runtime user immediately:

```bash
./feed_opensearch_ctl.sh db:drop
```

`db:uninstall` destructive paths require typed confirmation. `db:drop` is
intentionally non-interactive and should only be used when the configured
`MYSQL_DATABASE` and `MYSQL_USER` are known test/install targets.

## Docker Engine Setup

Docker is required only when using the bundled local OpenSearch container. It is
not required when production points `OPENSEARCH_URL` at an external OpenSearch
service.

The commands below install Docker Engine and the Docker Compose plugin from
Docker's official package repositories. They intentionally stay outside
`install-deps` because Docker policy varies by host and organization.

CentOS/RHEL-like hosts:

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker run hello-world
```

Ubuntu hosts:

```bash
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
```

Optional non-root Docker access for the deployer account:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
docker run hello-world
```

Membership in the `docker` group grants root-level control of the host. Use it
on development VMs or trusted deployer accounts only.

If Docker is installed but the current user cannot access
`/var/run/docker.sock`, Docker commands may fail with permission denied. Either
add the deployer account to the `docker` group and reconnect:

```bash
sudo usermod -aG docker "$USER"
exit
```

or allow the control script to use `sudo docker` when it manages the bundled
OpenSearch container. `doctor` reports whether Docker API access works directly,
via sudo, or not at all.

## Local OpenSearch

The bundled Docker Compose file is a local development convenience. It runs a
single-node OpenSearch container with security disabled, so production should
normally point `OPENSEARCH_URL` at the managed/external OpenSearch endpoint
instead.

```bash
./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:start
./feed_opensearch_ctl.sh opensearch:status
./feed_opensearch_ctl.sh opensearch:logs
./feed_opensearch_ctl.sh opensearch:stop
```

The relevant settings are:

```bash
OPENSEARCH_URL=http://localhost:9200
OPENSEARCH_INDEX=campaign_actions_feed
OPENSEARCH_USERNAME=''
OPENSEARCH_PASSWORD=''
OPENSEARCH_INITIAL_ADMIN_PASSWORD='Pa_OpenSearch_2026!ChangeMe'
```

The first feed index artifacts from `deedspot_sql` are now carried by this
service:

```bash
opensearch/campaign_actions_feed.index.json
opensearch/query_stage_d_unrelated_discovery.json
sql/opensearch/campaign_actions_feed_full_index.sql
```

Create or inspect the index:

```bash
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:index:show
```

Resetting or deleting the index is destructive and requires typing the exact
index name:

```bash
./feed_opensearch_ctl.sh opensearch:index:reset
./feed_opensearch_ctl.sh opensearch:index:delete
```

To remove the bundled local container:

```bash
./feed_opensearch_ctl.sh opensearch:uninstall
```

## Initial OpenSearch Load

The initial loader lives in `app/index_loader.py` and is exposed through the
control script. It reads from `SOURCE_MYSQL_*`, not the indexer queue database,
then writes documents to `OPENSEARCH_INDEX`.

Dry-run the source DB scan without writing OpenSearch:

```bash
./feed_opensearch_ctl.sh opensearch:load:dry-run
```

Create the index if missing and bulk upsert all visible campaign actions:

```bash
./feed_opensearch_ctl.sh opensearch:load
```

Delete/recreate the index and then bulk upsert all visible campaign actions:

```bash
./feed_opensearch_ctl.sh opensearch:rebuild
```

The loader pages by `(created_at, index)` using
`sql/opensearch/campaign_actions_feed_full_index.sql`, and writes bulk requests
using document id `index`. Page size is controlled by:

```bash
OPENSEARCH_LOADER_PAGE_SIZE=10000
```

## Incremental OpenSearch Jobs

After the initial load, application code should enqueue changed source rows in
the indexer database:

```sql
INSERT INTO search_index_jobs (entity_type, entity_id, action, priority, source)
VALUES ('campaign_action', '12345', 'U', 0, 'app');
```

Supported actions are:

- `I` and `U`: rebuild the full campaign action document from the source DB and
  upsert it into OpenSearch.
- `D`: delete the OpenSearch document with `_id = entity_id`.

For `I`/`U`, if the source row no longer exists or `feed_visible = 0`, the
worker deletes the OpenSearch document instead of indexing stale data. The
worker uses the same document shape as the bulk loader:

```json
{
  "created_at": 1778284800,
  "index": 100000000,
  "campaign_index": 123,
  "tags": [1, 2, 3]
}
```

`feed_visible` is a stored generated column on `campaign_actions`. It is true
only when the action is globally feed-visible:

```text
created_at IS NOT NULL
status = 'open'
type = 'external'
campaign_is_public = 1
campaign_status IN ('active', 'completed')
```

For a narrow local delete/upsert test, flip the action `status` away from
`open`, enqueue a `U` job, and the worker should delete the OpenSearch document.
Then restore `status = 'open'`, enqueue another `U`, and the document should
come back.

## Operations And Monitoring

After installation, operators need a quick way to understand whether the service
survived routine trouble such as reboot, power loss, Docker restart, MySQL
restart, or OpenSearch restart.

Current useful commands:

```bash
./feed_opensearch_ctl.sh services:status
./feed_opensearch_ctl.sh services:logs
./feed_opensearch_ctl.sh db:status
./feed_opensearch_ctl.sh opensearch:health
curl http://localhost:9200/campaign_actions_feed/_count?pretty
sudo mysql deedspot -e "SELECT COUNT(*) FROM campaign_actions WHERE feed_visible = 1;"
```

The recovery model should be:

```text
systemd restarts worker/reaper after reboot
Docker restarts bundled OpenSearch after reboot
reaper releases stale running jobs after REAPER_STALE_SECONDS
initial loader can rebuild OpenSearch from the source DB if index data is lost
```

Planned operator commands:

```bash
./feed_opensearch_ctl.sh verify
./feed_opensearch_ctl.sh queue:status
./feed_opensearch_ctl.sh opensearch:count
./feed_opensearch_ctl.sh opensearch:drift
```

`verify` should report:

```text
System:
  worker systemd instances active
  reaper systemd instances active
  Docker/OpenSearch container running when bundled OpenSearch is used

Indexer DB:
  runtime login ok
  queue table visible
  pending/running/done/failed counts
  stale running job count
  oldest pending job age

OpenSearch:
  cluster reachable
  cluster status green/yellow/red
  campaign_actions_feed exists
  index document count

Source DB:
  source DB reachable
  feed_visible source row count

Drift:
  source feed_visible count
  OpenSearch document count
  difference between source rows and indexed documents
```

If bundled local OpenSearch remains part of the deployable story, the Compose
service should use a restart policy such as `restart: unless-stopped`.

## Doctor

Use `doctor` after moving the service to a new host:

```bash
./feed_opensearch_ctl.sh doctor
```

It checks OS family, package manager, common commands, Python venv support,
config, requirements, venv, compose file, and systemd unit visibility. It also
prints next-step hints. A missing Docker command is acceptable when production
uses an external OpenSearch service instead of the bundled local container.

## Current Installer Boundary

This installer pass can start bundled local OpenSearch, create/reset the first
`campaign_actions_feed` index, run an initial rebuild/load from the source
database, and run worker/reaper services for live queue processing. Application
PHP enqueue hooks are still the main integration piece outside this service.
