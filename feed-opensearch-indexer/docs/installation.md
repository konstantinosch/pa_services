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
./feed_opensearch_ctl.sh fix-permissions
./feed_opensearch_ctl.sh install-systemd
./feed_opensearch_ctl.sh install-logrotate
```

`install-deps` installs common base packages for the service runtime, but it
does not install MySQL. Docker packaging differs more on CentOS/RHEL systems, so
the script reports Docker status in `doctor` and leaves site-specific
Docker/Podman choices explicit.

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

It asks separately about systemd units, logrotate, MySQL objects, the Linux
service user, and logs. Systemd/logrotate removal are the natural defaults;
database, MySQL user, Linux user, and log deletion default to keeping existing
state unless explicitly selected.

For only MySQL cleanup:

```bash
./feed_opensearch_ctl.sh db:uninstall
```

Destructive database, schema, MySQL user, and log deletion paths require typed
confirmation.

## Local OpenSearch

The bundled Docker Compose file remains a local development convenience:

```bash
./feed_opensearch_ctl.sh opensearch:start
./feed_opensearch_ctl.sh opensearch:status
./feed_opensearch_ctl.sh opensearch:logs
./feed_opensearch_ctl.sh opensearch:stop
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

This installer pass does not yet create the real OpenSearch index, enqueue PHP
application jobs, or perform index rebuilds. Those are next deliverability layers
on top of this service spine.
