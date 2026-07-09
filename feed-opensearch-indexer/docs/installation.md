# Feed OpenSearch Indexer Installation

This service is the queue-consuming side of the feed indexing stack. It keeps an
OpenSearch index eventually aligned with the relational source of truth by
claiming rows from `search_index_jobs`, processing them in batches, and
recovering stale claims with a separate reaper process.

The current worker still logs the intended upsert/delete operation. The
installer scaffolding below prepares the project as a deliverable service before
the real OpenSearch adapter is wired in.

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
./feed_opensearch_ctl.sh install-service-user
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

# If doctor reports "miss command docker", install Docker now.
# See "Docker Engine Setup" below.

./feed_opensearch_ctl.sh opensearch:install
./feed_opensearch_ctl.sh opensearch:index:create
./feed_opensearch_ctl.sh opensearch:health
./feed_opensearch_ctl.sh opensearch:load:dry-run
./feed_opensearch_ctl.sh opensearch:load

./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:status

# Lock down project permissions after installation/verification.
# If the deployer account should keep running control commands later:
sudo usermod -aG pa_indexer "$USER"
newgrp pa_indexer
./feed_opensearch_ctl.sh fix-permissions
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

The initial OpenSearch loader needs either a source DB user:

```bash
SOURCE_MYSQL_HOST=localhost
SOURCE_MYSQL_PORT=3306
SOURCE_MYSQL_USER=app_readonly_user
SOURCE_MYSQL_PASSWORD='change-me'
SOURCE_MYSQL_DATABASE=deedspot
SOURCE_MYSQL_BIN=mysql
SOURCE_MYSQL_SUDO=0
```

or local socket sudo access for development:

```bash
SOURCE_MYSQL_DATABASE=deedspot
SOURCE_MYSQL_BIN=mysql
SOURCE_MYSQL_SUDO=1
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
`sql/indexer/schema_mysql.sql`. It creates `search_index_jobs` with
`CREATE TABLE IF NOT EXISTS`.


## Linux Service User

The systemd worker and reaper should run as the dedicated locked-down Linux user
`pa_indexer`, not as the deployer account. Create it and apply ownership after
configuration and before installing systemd units:

```bash
./feed_opensearch_ctl.sh install-service-user
./feed_opensearch_ctl.sh fix-permissions
```

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
./feed_opensearch_ctl.sh services:start
./feed_opensearch_ctl.sh services:status
./feed_opensearch_ctl.sh services:logs
./feed_opensearch_ctl.sh services:restart
./feed_opensearch_ctl.sh services:stop
```

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

The combined uninstall command is interactive and keeps project files in place:

```bash
./feed_opensearch_ctl.sh uninstall
```

It asks separately about systemd units, logrotate, OpenSearch index/container
state, MySQL objects, the Linux service user, and logs. Systemd/logrotate
removal are the natural defaults; OpenSearch index/container data, database,
MySQL user, Linux user, and log deletion default to keeping existing state unless
explicitly selected.

OpenSearch uninstall choices are split deliberately:

```bash
opensearch-index [keep] (keep delete)
opensearch-containers [keep] (keep stop down down-volumes)
```

`delete` removes only `OPENSEARCH_INDEX` through the OpenSearch HTTP API.
`down-volumes` removes the bundled Docker Compose volume and therefore all
local OpenSearch index data for that container.

For only MySQL cleanup:

```bash
./feed_opensearch_ctl.sh db:uninstall
```

Destructive database, schema, MySQL user, and log deletion paths require typed
confirmation.

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
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
OPENSEARCH_LOADER_PAGE_SIZE=500
```

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
`campaign_actions_feed` index, and run an initial rebuild/load from the source
database. The actual worker still needs the real OpenSearch adapter and
entity-specific PHP enqueue hooks before it performs live upserts/deletes.
