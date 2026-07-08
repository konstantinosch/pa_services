# Indexing System Design & Concurrency Notes

## Overview
This document describes the architecture, design decisions, concurrency issues, and final solutions for the MySQL-based indexing job system consisting of:
- Daemon workers
- Reaper recovery process

---

## Architecture

### Flow
DB → search_index_jobs → Workers → OpenSearch

### Components
- **Daemon**: Fetches, claims, processes, finalizes jobs
- **Reaper**: Detects and releases stale jobs

---

## Table: search_index_jobs

Key fields:
- job_id (PK)
- entity_type, entity_id
- action
- status (P, R, D, S)
- claim_id (ownership)
- worker_id
- started_at, claimed_at
- retry_count, reap_count
- available_at (optional scheduling)
- error_text

Indexes:
- idx_jobs_pending_order (status, priority, created_at, job_id)
- idx_jobs_entity_status (entity_type, entity_id, status)
- idx_jobs_claim_status (claim_id, status)

---

## State Model

Status:
- P = Pending
- R = Running
- D = Done
- S = Superseded

Ownership for running jobs:
- R + claim_id != NULL → owned/running
- R + claim_id = NULL → orphan/reclaimable

Terminal jobs:
- D/S rows may retain claim_id as batch history
- D/S rows are not owned

Critical concept:
Status != ownership

---

## Worker (Daemon)

### Fetch Logic

Eligible jobs:
```
status = 'P'
OR (status = 'R' AND claim_id IS NULL)
```

Uses:
```
FOR UPDATE SKIP LOCKED
```

### Expanded Strategy

Old:
UPDATE JOIN → caused deadlocks

New:
1. Select seed jobs
2. Fetch entity keys
3. SELECT job_ids FOR UPDATE SKIP LOCKED
4. UPDATE by PK

---

## Reaper

### Purpose
Recover stale jobs

### Detection
```
status = 'R'
AND claim_id IS NOT NULL
AND started_at < threshold
```

### Old behavior (WRONG)
R → P

### Final behavior (CORRECT)
Release ownership only:
```
claim_id = NULL
worker_id = NULL
```

---

## Deadlocks Observed

### Case 1
UPDATE JOIN vs UPDATE

Cause:
- secondary index locking
- unpredictable order

### Case 2
R → P vs SELECT FOR UPDATE

Cause:
- index rewrite on status
- range locks

---

## Root Causes

- Updating indexed columns (status)
- UPDATE JOIN on same table
- inconsistent lock ordering
- large batch updates

---

## Final Fixes

### Structural
- Remove UPDATE JOIN
- Avoid status churn
- Use PK-based updates
- Introduce orphan model

### Operational
- batch size tuning
- deterministic ordering
- SKIP LOCKED usage

---

## available_at

Not required for correctness anymore.

Still useful for:
- retry backoff
- scheduling
- throttling

---

## Concurrency Model

Daemon:
- claims P or orphan R
- sets claim_id

Reaper:
- clears claim_id only

System invariant:
No R → P oscillation

---

## Best Practices

- Always update by primary key
- Avoid modifying indexed columns unnecessarily
- Keep transactions short
- Use deterministic ordering
- Treat deadlocks as retryable

---

## Summary

This system evolved from a naive job queue into a robust concurrent coordination system by:

- separating state from ownership
- eliminating index churn
- enforcing deterministic locking
- avoiding dangerous SQL patterns

The final model supports high concurrency with minimal deadlock risk.
