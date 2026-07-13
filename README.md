# PA Services

This repository contains the operational services that keep the feed experience aligned with the source-of-truth data:

- The OpenSearch indexer service consumes queue jobs, rebuilds campaign-action documents from MySQL, and upserts or deletes them in OpenSearch.
- The feed RAM refresh service maintains MySQL MEMORY tables used by the feed endpoint so reads can stay fast while still being refreshed from the live database.

The layout is intentionally split so each service can be installed, configured, and managed independently while sharing the same host-level conventions.

---

## Repository Layout

```text
pa_services/
├── feed-opensearch-indexer/
│   ├── app/                   # Python worker, reaper, loader, config helpers
│   ├── db/                    # MySQL adapter and schema helpers
│   ├── docker/opensearch/     # local OpenSearch docker-compose setup
│   ├── examples/php/          # application-side enqueue helper example
│   ├── opensearch/            # OpenSearch index mappings and query artifacts
│   ├── sql/                   # MySQL source/indexer schema and loader SQL assets
│   ├── README.md              # service-specific documentation
│   ├── config.example.env     # example configuration for the indexer
│   ├── requirements.txt       # Python runtime dependencies
│   └── feed_opensearch_ctl.sh # control script for install / configure / manage
├── feed-ram-refresh/
│   ├── sql/                   # RAM refresh SQL and state-table setup
│   ├── README.md              # service-specific documentation
│   └── feed_ram_ctl.sh        # control script for refresh / cron / logrotate
└── README.md                  # this file
```

---

## Service Overview

| Service | Purpose | Runtime | Primary Data Stores |
| --- | --- | --- | --- |
| feed-opensearch-indexer | Queue-driven indexing of campaign actions into OpenSearch | worker + reaper daemons | MySQL queue/state tables + OpenSearch |
| feed-ram-refresh | Rebuilds MySQL MEMORY feed tables for fast reads | cron-driven refresh jobs | MySQL MEMORY tables + live MySQL |

---

## Shared Prerequisites

The services assume a Linux host with:

- Python 3 and a virtual environment for the indexer
- MySQL client access and an external MySQL server
- OpenSearch access for the indexer service
- systemd for long-running services
- cron for the RAM refresh service (optional but strongly recommended)
- Docker only when you want to run the bundled local OpenSearch container for development

A typical production host should also have a dedicated service account such as `pa_indexer`.

---

## 1. Feed OpenSearch Indexer

### What it does

The indexer is a queue-based synchronization service. It keeps an OpenSearch index eventually aligned with source-of-truth data in MySQL.

The core flow is:

1. Application or integration code writes a change signal to the queue table.
2. A worker claims pending jobs from MySQL.
3. The worker rebuilds the current document from the source database.
4. The worker upserts or deletes the OpenSearch document.
5. A reaper recovers stale ownership when a worker dies or loses a claim.

The current implementation focuses on `campaign_action` documents.

### Key concepts

- `search_index_jobs`: the indexer-owned work queue.
- `search_index_state`: the durable per-entity checkpoint ledger.
- `P / R / D / S / F`: queue job states for pending, running, done, superseded, and failed.
- `I / U / D`: intended actions for insert, update, or delete.

The worker treats queue rows as change signals, not as the source of truth. The final document is rebuilt from the current source row in MySQL.

For the full service overview, see [feed-opensearch-indexer/README.md](feed-opensearch-indexer/README.md).

## 2. Feed RAM Refresh

### What it does

The feed RAM refresh service is a lightweight materialization layer for the feed. It rebuilds compact MySQL MEMORY tables that the PHP feed endpoint can read quickly, instead of recomputing the same feed-shaped joins from the full live database on every request.

In practice, it acts like a refreshable cache: the live database remains the source of truth, while the RAM tables provide a smaller, precomputed view of recent feed data that is easier and faster to serve. The service refreshes those tables on a schedule and keeps metadata about which time window and memory settings are currently covered.

It maintains:

- `ram_campaign_actions`: compact feed-selection rows for recent visible actions.
- `ram_hydrated_actions`: hydrated post/campaign payload rows keyed by action index.
- `ram_state`: metadata that records the coverage window and the effective memory settings.

For the full service overview, see [feed-ram-refresh/README.md](feed-ram-refresh/README.md).
