# Feed RAM Refresh

Small operational wrapper for feed RAM/read-model refresh jobs.

This folder is the home for the next RAM phase. Existing SQL under
`sql_components/` is intentionally left unchanged until the refresh bodies are
moved here.

## Files

- `feed_ram_ctl.sh`: single entrypoint for manual refreshes and cron management.
- `config.env`: service tunables loaded by the control script.
- `sql/ram_state.sql`: destructive shared state-table recreation.
- `sql/ensure_ram_state.sql`: non-destructive shared state-table setup for refresh/drop.
- `sql/refresh_campaign_actions.sql`: runnable `ram_campaign_actions` refresh.
- `sql/refresh_hydrated_actions.sql`: runnable `ram_hydrated_actions` refresh.

## Planned Commands

```bash
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh help
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh init-ram-state
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh campaign_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh hydrated_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh all
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh status campaign_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh status hydrated_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh status ram_state
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh status all
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh config
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh drop campaign_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh drop hydrated_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh drop ram_state
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh drop all
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh install-cron campaign_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh install-cron hydrated_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh install-cron all
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh uninstall-cron campaign_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh uninstall-cron hydrated_actions
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh uninstall-cron all
/opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh show-cron
```

## Refresh Flow

`init-ram-state` recreates `ram_state` in its canonical shape. Refreshes use
the non-destructive ensure file so refreshing one RAM model does not clear the
other model's state row.

`refresh campaign_actions` ensures `ram_state` exists, acquires the
`praxi_agapis_feed:ram_campaign_actions` advisory lock, injects the configured
RAM bounds as SQL session variables, and runs `sql/refresh_campaign_actions.sql`.

The campaign-actions refresh body builds `ram_campaign_actions_next`, atomically
swaps it into `ram_campaign_actions`, and updates `ram_state` only after the swap.

The hydrated-actions refresh body materializes the live hydration join aliases
into `ram_hydrated_actions_next`, keyed by `action_index`, then atomically swaps
it into `ram_hydrated_actions`.

## Drop Command

`drop campaign_actions|hydrated_actions|ram_state|all` drops the selected MEMORY table.
For action and hydration RAM, it also removes the matching `ram_state` row.
`drop ram_state` removes the shared state table itself, and `drop all` removes
both RAM tables before removing `ram_state`.


## Status And Config

`status campaign_actions|hydrated_actions|ram_state|all` reports table metadata from
`information_schema` and, when present, the matching `ram_state` row.

`config` validates the effective configuration and prints the loaded config file,
log directory, cron schedules, and computed row caps.

## MySQL Credentials

A standalone MySQL client defaults file can live beside the service:

```ini
# /opt/pa_services/feed-ram-refresh/mysql.cnf
[client]
host=127.0.0.1
user=indexer
password=indexerpass
```

Keep it private:

```bash
chmod 600 /opt/pa_services/feed-ram-refresh/mysql.cnf
```

Then load it from `config.env`:

```bash
MYSQL_ARGS="--defaults-extra-file=/opt/pa_services/feed-ram-refresh/mysql.cnf"
```

## Config

The control script loads `/opt/pa_services/feed-ram-refresh/config.env` on every run, so cron jobs pick up changed tunables without being reinstalled. Cron expressions must be quoted because they contain spaces:

```bash
FEED_RAM_CAMPAIGN_ACTIONS_CRON="*/5 * * * *"
```

## Logs

Cron redirects refresh output to the configured log directory. The controller
prints timestamped operational lines such as refresh start/end, lock acquire and
release, and drop actions:

```text
[2026-05-31 18:56:48 +0300] [INFO] Refresh completed for campaign_actions.
```

MySQL warnings and errors still pass through stderr/stdout so failed refreshes
keep their SQL context in the same log file.

## Cron Markers

Cron entries managed by the control script are marked on the same line with
stable ids:

```cron
*/5 * * * * /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh campaign_actions >> /opt/pa_services/feed-ram-refresh/logs/pa_campaign_actions.log 2>&1 # praxi_agapis_feed:campaign_actions
*/5 * * * * /opt/pa_services/feed-ram-refresh/feed_ram_ctl.sh refresh hydrated_actions >> /opt/pa_services/feed-ram-refresh/logs/pa_hydrated_actions.log 2>&1 # praxi_agapis_feed:hydrated_actions
```

Those markers let install/update/remove logic find only the feed RAM jobs.
`install-cron` removes any existing line with the matching marker before adding
the new line, so changing the cron pattern in `config.env` and installing again
updates the schedule.

## State Rows

Both refresh jobs write to the shared `ram_state` table:

```text
name = campaign_actions
name = hydrated_actions
```

`recent_days` is the configured target window. `min_created_at` and
`max_created_at` are the actual usable coverage after heap/row-cap limits.
`ram_heap_target_bytes` and `ram_row_cap` should record the memory target and
computed row cap used for that refresh.
