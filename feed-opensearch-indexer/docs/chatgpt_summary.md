🧠 INDEXING SYSTEM DESIGN SUMMARY (Worker + Reaper Architecture)
1️⃣ 🎯 Στόχος συστήματος

Ασύγχρονο indexing pipeline:

DB → Jobs table → Workers → OpenSearch

με requirements:

✔ υψηλό throughput
✔ deduplication (same entity πολλές φορές)
✔ retryability
✔ resilience σε crashes
✔ scalability (n workers / n reapers)
✔ deterministic behavior (όσο γίνεται)
2️⃣ 🧱 Core Table: search_index_jobs
Fields
job_id        BIGINT PK
entity_type   VARCHAR
entity_id     VARCHAR
action        CHAR(1)

status        CHAR(1)   -- P / R / D / S
priority      INT
source        VARCHAR

worker_id     VARCHAR
claim_id      CHAR(36)

claimed_at    TIMESTAMP
started_at    TIMESTAMP
finished_at   TIMESTAMP

retry_count   INT       -- indexing failures
reap_count    INT       -- stale recoveries

available_at  TIMESTAMP -- (optional scheduling/backoff)

error_text    TEXT
3️⃣ 🔄 State Machine (FINAL VERSION)
P = Pending (never claimed)

R = Running

D = Done (success)
S = Superseded (deduplicated)
F = Failed (optional / future)
⚠️ CRITICAL CONCEPT (breakthrough)
R is NOT enough to describe ownership

👉 ownership είναι:

claim_id != NULL → owned
claim_id = NULL  → orphan
✅ FINAL MODEL
P                     → ready
R + claim_id != NULL  → actively processed
R + claim_id IS NULL  → orphan (reclaimable)
4️⃣ ⚙️ Worker
Responsibilities
1. fetch jobs
2. claim them
3. process (index)
4. finalize
Fetch strategies
SIMPLE
SELECT job_id
FROM search_index_jobs
WHERE (
    status = 'P'
    OR (status = 'R' AND claim_id IS NULL)
)
AND available_at <= NOW()
ORDER BY priority DESC, created_at ASC, job_id ASC
LIMIT N
FOR UPDATE SKIP LOCKED
EXPANDED (dedup-aware)
Phase 1 (seed claim)
claim initial batch
Phase 2 (expand)
find all jobs for same entity
⚠️ OLD (BAD)
UPDATE ... JOIN ...

→ caused massive deadlocks

✅ NEW (GOOD)
SELECT job_ids FOR UPDATE SKIP LOCKED
UPDATE by job_id IN (...)
Claim rule (IMPORTANT)
WHERE job_id IN (...)
AND (
    status = 'P'
    OR (status = 'R' AND claim_id IS NULL)
)
5️⃣ 🧹 Reaper (Recovery Worker)
Purpose
recover stale jobs (worker crash / stuck)
Detection
WHERE status = 'R'
AND claim_id IS NOT NULL
AND started_at < NOW() - INTERVAL X
❌ OLD DESIGN (WRONG)
R → P

→ caused:

index rewrite
worker conflict
deadlocks
✅ FINAL DESIGN (BREAKTHROUGH)
R claimed → R orphan

SQL:

UPDATE search_index_jobs
SET
    claim_id = NULL,
    worker_id = NULL,
    claimed_at = NULL,
    started_at = NULL,
    reap_count = reap_count + 1
WHERE job_id IN (...)
AND status = 'R'
🧠 Meaning
reaper does NOT change status
reaper only releases ownership
6️⃣ 💣 Deadlock Investigation Summary
❌ Deadlock #1 (Initial)
worker UPDATE JOIN
vs
reaper UPDATE

Cause:

JOIN UPDATE on same table
→ unpredictable lock ordering
❌ Deadlock #2
reaper R → P (status change)
vs
worker SELECT FOR UPDATE

Cause:

status is indexed column
→ index rewrite
→ range locks
🔥 Insight
Changing indexed columns = dangerous under concurrency
7️⃣ 🧠 Final Concurrency Model
Golden Rules
✔ never oscillate status unnecessarily
✔ separate "state" from "ownership"
✔ update by primary key whenever possible
✔ use SKIP LOCKED
✔ deterministic ordering
Deterministic locking
job_ids = sorted(job_ids)
8️⃣ 📉 Deadlock Mitigation Strategy
Structural fixes (PRIMARY)
✔ remove UPDATE JOIN
✔ stop R → P churn
✔ claim by PK
✔ orphan model
Operational fixes (SECONDARY)
✔ smaller batches
✔ delays between batches
✔ consistent ordering
Safety net (OPTIONAL but recommended)

Retry:

MySQL 1213 (deadlock)
MySQL 1205 (timeout)
9️⃣ 🧠 available_at — Role
❌ NOT needed for correctness anymore

Deadlocks solved without it.

✅ Still useful for:
✔ retry backoff
✔ throttling
✔ scheduling
✔ future features
🔟 📦 Superseded / Dedup Logic
Concept
multiple jobs per entity → only latest matters
Flow
claim all → process once → mark others S
Important
do NOT delete early
reaper might still need them
1️⃣1️⃣ 🧠 Key Design Breakthroughs
🧨 #1 — Ownership ≠ Status
claim_id defines ownership, not status
🧨 #2 — Avoid index churn
status flip = expensive + dangerous
🧨 #3 — UPDATE JOIN is toxic in concurrency
🧨 #4 — Orphan model = clean recovery
1️⃣2️⃣ ⚠️ Known Pitfalls
❌ UPDATE ... JOIN on same table
❌ large batch updates touching indexed columns
❌ R → P oscillation
❌ mixing lock order across workers
❌ assuming "no deadlocks possible"
1️⃣3️⃣ 🚀 Scalability

System now supports:

✔ N workers
✔ N reapers
✔ high concurrency
✔ safe recovery
1️⃣4️⃣ 🧠 Mental Model (FINAL)
Queue = set of jobs

Worker:
  picks work
  owns via claim_id

Reaper:
  removes ownership only

System:
  never rewinds state unnecessarily
1️⃣5️⃣ 💬 Final Take

Αυτό που έφτιαξες τελικά είναι:

not just a queue
but a distributed coordination system

και τα bugs που βρήκες είναι:

classic database concurrency traps
🧾 TL;DR (για νέο chat)
We built a MySQL-backed job queue with:
- workers (claim/process/finalize)
- reaper (recover stale jobs)

Key design:
- status = state
- claim_id = ownership

Critical fix:
- reaper does NOT set R → P
- it only clears claim_id

Result:
- eliminates index churn
- eliminates main deadlock pattern

Expanded fetch:
- no UPDATE JOIN
- select job_ids → update by PK

System now supports high concurrency safely.

Αν το πετάξεις αυτό σε νέο chat, μπορώ να συνεχίσω κατευθείαν από εδώ σαν να μην χάθηκε τίποτα 👍
