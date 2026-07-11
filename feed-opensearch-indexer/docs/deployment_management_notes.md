# Deployment & Management Notes

## Goal

Package the service so a host can be prepared with a predictable flow:

```
tar -xzf indexer-service-x.y.z.tar.gz
cd indexer-service-x.y.z
sudo ./scripts/install.sh
```

The install flow should prepare the OS/service environment, but runtime workers should still fail fast when required configuration or infrastructure is missing.

---

## Recommended Layout

Development:

```
/opt/indexer-service/.env
```

Production:

```
/opt/indexer-service/
/etc/indexer-service/indexer-service.env
```

Recommended production env file permissions:

```
owner: root
group: indexer
mode: 0640
```

Example:

```bash
sudo mkdir -p /etc/indexer-service
sudo chown root:indexer /etc/indexer-service/indexer-service.env
sudo chmod 640 /etc/indexer-service/indexer-service.env
```

---

## Install Script Responsibilities

A bash installer is a good fit for OS-level setup:

- create `indexer` user/group if missing
- create `/opt/indexer-service`
- copy/extract application files
- create Python virtualenv
- install requirements
- create `/etc/indexer-service`
- install env template if missing
- install systemd unit files
- run `systemctl daemon-reload`
- optionally enable services, but do not start until config checks pass

The installer should avoid silently creating production secrets. Missing production configuration should be explicit.

---

## Management Commands

A Python management layer is a good fit for app/database-aware checks:

```bash
python -m app.manage doctor
python -m app.manage init-env
python -m app.manage check-config
python -m app.manage check-db
python -m app.manage init-db
```

Possible wrapper:

```bash
bin/indexerctl doctor
bin/indexerctl init-env
bin/indexerctl check-db
bin/indexerctl init-db
bin/indexerctl service-install
```

---

## Checks

`check-config` should verify:

- required env vars exist
- `DB_ENGINE` is supported
- log directory is writable
- numeric settings parse correctly
- worker/reaper batch sizes and delays are sane

`check-db` should verify:

- MySQL connection works
- MySQL version supports `FOR UPDATE SKIP LOCKED`
- target database exists
- required tables exist
- required columns exist
- required indexes exist

`doctor` should run all non-destructive checks and print a clear report.

---

## Schema Management

`init-db` may apply `sql/schema_mysql.sql`, but it should be explicit.

Avoid destructive schema changes by default. If a destructive reset is ever needed, require an explicit flag such as:

```bash
python -m app.manage init-db --force
```

The authoritative SQL file is:

```
sql/schema_mysql.sql
```

Other SQL files may be test/demo/history files unless explicitly promoted.

---

## Runtime Philosophy

Worker and reaper should stay boring:

- load config
- connect to DB
- process/reap jobs
- fail fast on missing critical dependencies

They should create safe runtime directories such as the log directory, but they should not silently create production env files or production secrets.

Retry policy belongs at the right layer:

- adapter retries transient DB transaction conflicts such as deadlocks and lock wait timeouts
- worker/reaper handle processing and service lifecycle failures
- missing DB/config/schema is fatal and should be fixed by deployment or management commands

---

## Target Deployment Flow

Suggested production flow:

```bash
tar -xzf indexer-service-x.y.z.tar.gz
cd indexer-service-x.y.z

sudo ./scripts/install.sh
sudo indexerctl init-env

# edit /etc/indexer-service/indexer-service.env

sudo -u indexer indexerctl doctor
sudo -u indexer indexerctl init-db
sudo -u indexer indexerctl doctor

sudo systemctl enable --now indexer-worker indexer-reaper
```
