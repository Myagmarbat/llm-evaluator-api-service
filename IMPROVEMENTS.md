# Improvements

Potential enhancements to the LLM Evaluator API Service, organized by priority and area. These are follow-on items beyond the current design, which intentionally prioritizes primary-path availability over complete shadow evaluation coverage.

---

## P0 — High impact, address first

### Deep health checks

**Problem:** `/health` always returns `{"status": "ok"}` without verifying dependencies. An instance can remain in rotation while all inference calls fail (bad API key, upstream outage).

**Proposal:**
- Add `/health/ready` (or extend `/health`) to probe DigitalOcean Inference with a lightweight request or HEAD/ping.
- Return degraded/unready when inference is unreachable.
- Keep `/health` as a fast liveness probe if App Platform requires it.

**Helps:** Availability detection, faster removal of bad instances.

---

### Separate HTTP clients for primary and shadow

**Problem:** One shared `httpx.AsyncClient` serves both the user-facing primary path and up to 10 concurrent shadow workers. Long-running LLM calls compete for the same connection pool.

**Proposal:**
- Create two clients in `LLMClient` or split into `PrimaryLLMClient` and `ShadowLLMClient`.
- Tune pool limits independently (e.g. larger pool for primary, smaller for shadow).

**Helps:** Isolation under load; reduces primary-path contention from background traffic.

---

## P1 — Strong improvements for scale and operations

### Autoscaling signal aligned with workload

**Problem:** App Platform scales on CPU (default 80%), but the service is I/O-bound waiting on LLM responses. Under heavy traffic, CPU may stay low while concurrency is high, causing under-scaling.

**Proposal:**
- Evaluate request-rate or concurrency-based scaling if App Platform supports it.
- Alternatively, increase `autoscaling_min_instances` for known traffic baselines.
- Monitor `shadow_dropped` and p95 primary latency externally to trigger manual scale events.

**Helps:** Scalability for I/O-heavy workloads.

---

### Centralized metrics aggregation

**Problem:** Each instance maintains its own in-memory counters and SQLite file. `/metrics` on one pod is not cluster-wide. Match rate and queue depth are fragmented across replicas.

**Proposal:**
- Export Prometheus metrics or push to Datadog/StatsD.
- Aggregate `total_comparisons`, `total_matches`, `shadow_dropped`, and queue depth across instances.
- Optionally expose a cluster-level match rate via a sidecar or external collector.

**Helps:** Operability and reliable rollout decisions at scale.

---

### Inference quota isolation

**Problem:** Primary and candidate calls share one API key and rate limit. At 100% shadow routing, each user request triggers two inference calls, doubling quota consumption.

**Proposal:**
- Use separate API keys for primary vs candidate where possible.
- Default production `shadow_routing_percentage` below 100% and tune by traffic.
- Document quota math: `primary_rps + (primary_rps × routing% × instances)`.

**Helps:** Prevents shadow load from indirectly starving primary traffic.

---

## P2 — Fault tolerance and shadow reliability

### Circuit breaker on candidate model

**Problem:** If the candidate model is degraded, workers still dequeue tasks and burn up to 30s per slot until timeout. Queue fills; shedding increases; no automatic backoff.

**Proposal:**
- Track consecutive candidate failures/timeouts.
- Auto-set `shadow_routing_percentage` to 0 after a threshold (with manual reset via `PUT /config`).
- Optionally expose `candidate_circuit_open` in `/metrics`.

**Helps:** Fault tolerance during candidate incidents without operator intervention.

---

### Retries with backoff (transient failures)

**Problem:** Primary and candidate calls are single-attempt. Transient network blips or 503s from inference result in immediate failure.

**Proposal:**
- Add limited retries (e.g. 2 attempts) for idempotent-safe transient errors on the primary path.
- Keep shadow retries minimal or disabled to avoid slot exhaustion.

**Helps:** Resilience to brief upstream instability.

---

### Durable shadow queue

**Problem:** In-memory `asyncio.Queue` loses pending tasks on crash/redeploy. Shed tasks are gone forever with no replay.

**Proposal:**
- Optional external queue (Redis, SQS, RabbitMQ) for shadow tasks.
- Fire-and-forget publish from `/v1/chat`; dedicated consumers run evaluation.
- Trade-off: added ops complexity and cost.

**Helps:** Shadow evaluation coverage and durability when 100% sampling matters.

---

### SQLite trace store hardening

**Problem:** New DB connection per mismatch write; file-level locking; ephemeral `/tmp` disk on App Platform; no retention policy.

**Proposal:**
- Reuse a single `aiosqlite` connection or small connection pool.
- Move writes outside the worker semaphore slot (after LLM call completes).
- Add TTL or max-row retention; optionally use managed DB (Postgres) for durable traces.
- Batch inserts under high mismatch rates.

**Helps:** Shadow worker throughput when mismatch rate is high; durable audit trail.

---

## P3 — High availability and platform

### Multi-region deployment

**Problem:** Single region (`nyc3` default). Regional outage affects all instances.

**Proposal:**
- Deploy separate App Platform apps per region with geo-routed DNS.
- Accept per-region fragmented metrics unless centralized aggregation is in place.

**Helps:** Geographic availability.

---

### Fallback primary model

**Problem:** Primary LLM failure returns 502/504 to clients. No degraded-mode fallback.

**Proposal:**
- Configurable fallback model when primary returns 5xx or times out.
- Strict opt-in; only for non-critical workloads where a smaller/faster model is acceptable.

**Helps:** End-to-end chat availability during primary model incidents.

---

### Readiness vs liveness split

**Problem:** Single `/health` endpoint used for both Docker HEALTHCHECK and App Platform health checks.

**Proposal:**

| Endpoint | Purpose | Checks |
|----------|---------|--------|
| `/health/live` | Process alive | Returns 200 if event loop running |
| `/health/ready` | Can serve traffic | Inference reachable, queue started, optional DB writable |

**Helps:** Cleaner deploy drain behavior; don't route to instances that can't call inference.

---

## Application-level refinements

### Worker pool / semaphore simplification

**Problem:** `shadow_max_workers` asyncio tasks and a semaphore of the same size are redundant when both default to 10.

**Proposal:**
- Use either N worker tasks **or** a semaphore-limited pool, not both at equal limits.
- Optionally decouple dequeue workers from concurrent LLM slots (more workers dequeuing, fewer concurrent calls).

**Helps:** Clearer concurrency model; easier tuning.

---

### Shadow task memory footprint

**Problem:** Each queued `ShadowTask` holds full request JSON and primary response. At queue depth 100 with large agent payloads, memory pressure on `0.5gb` instances is possible.

**Proposal:**
- Store only a hash + reference, or truncate large fields in queued tasks.
- Lower default `shadow_queue_max_size` on small instance sizes.

**Helps:** Stability on default App Platform instance size.

---

### Streaming support

**Problem:** `stream: true` requests are rejected with 400.

**Proposal:**
- Proxy streaming from primary model if needed for production clients.
- Shadow eval would sample completed responses or skip streaming requests.

**Helps:** Broader API compatibility if clients require streaming.

---

## Observability additions

| Metric / signal | Why |
|-----------------|-----|
| Primary p50/p95/p99 latency | Detect inference slowdown before CPU spikes |
| Inference 429 rate | Quota exhaustion early warning |
| `shadow_dropped / shadow_submitted` ratio | Eval coverage health |
| Per-instance vs cluster match rate | Detect uneven load |
| Candidate circuit state | Incident visibility |
| Queue age (oldest task timestamp) | Backlog depth beyond slot count |

---

## Suggested implementation order

1. Deep health checks + separate HTTP clients (P0)
2. Centralized metrics (P1)
3. Circuit breaker + runtime docs for routing % (P2)
4. SQLite connection reuse + write outside semaphore (P2, low effort)
5. Durable shadow queue (P2, only if 100% eval coverage is required)
6. Multi-region / fallback model (P3, product decision)

---

## Out of scope (by current design)

These are intentional tradeoffs, not bugs:

- **Shadow task shedding** when queue is full — protects primary path
- **Best-effort shadow eval** — not a guaranteed analytics pipeline
- **Action-only comparison** — targets agent JSON outputs, not semantic similarity
- **Per-instance metrics** — acceptable for dev/canary; insufficient alone for large-scale rollout decisions

See [README.md](README.md) for current architecture, configuration, and deployment.
