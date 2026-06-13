# In-Memory Features & Integration

PostgreSQL **18** is a **disk-first** database — it does not ship an Oracle-style In-Memory Column Store. This guide covers **native RAM features**, **tuning**, **warm-cache tools**, and **integration with external in-memory systems** (Redis, etc.).

> See also: [Architecture — Memory](../01-getting-started/architecture.md) · [Tuning Parameters](tuning-parameters.md) · [PG 18 AIO](../01-getting-started/postgresql-18.md)

---

## Memory Model Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                     SHARED MEMORY (all backends)                  │
│  shared_buffers │ WAL buffers │ lock tables │ proc array │ clog  │
└──────────────────────────────────────────────────────────────────┘
         ▲                    ▲
         │                    │
┌────────┴────────┐  ┌────────┴────────┐  ┌─────────────────────┐
│ Backend 1       │  │ Backend 2       │  │ Autovacuum worker   │
│ work_mem        │  │ work_mem        │  │ maintenance_work_mem│
│ temp_buffers    │  │ temp_buffers    │  │                     │
│ catalog cache   │  │ catalog cache   │  │                     │
└─────────────────┘  └─────────────────┘  └─────────────────────┘
         ▲
┌────────┴────────┐
│ OS Page Cache   │  ← effective_cache_size hints planner; PG + OS both cache pages
└─────────────────┘
```

| Region | Scope | Survives disconnect? |
|--------|-------|----------------------|
| `shared_buffers` | Cluster | Yes |
| `work_mem` | Per operation per backend | No |
| `temp_buffers` | Per session | No |
| OS page cache | Server | Yes (until evicted) |
| UNLOGGED tables | On disk, minimal WAL | Until crash/restart |

---

## Native In-Memory / RAM Features

### 1. shared_buffers — Primary Page Cache

PostgreSQL's main buffer pool for table and index pages (default 8 KB pages).

```ini
# postgresql.conf — PG 18 production starting point (32 GB RAM server)
shared_buffers = 8GB              # ~25% RAM; cap 8–16 GB often optimal on Linux
```

```sql
SHOW shared_buffers;
SELECT setting, unit FROM pg_settings WHERE name = 'shared_buffers';

-- Buffer hit ratio (target > 99% OLTP)
SELECT
  sum(blks_hit) * 100.0 / nullif(sum(blks_hit) + sum(blks_read), 0) AS cache_hit_pct
FROM pg_stat_database;
```

**Integration note:** Larger `shared_buffers` is not always faster — OS cache also holds pages. On Linux, 25% RAM is the usual starting point.

---

### 2. effective_cache_size — Planner Hint (Not Allocated Memory)

Tells the optimizer how much RAM is available for caching (PG + OS).

```ini
effective_cache_size = 24GB    # ~50–75% of total RAM on dedicated DB server
```

Does **not** allocate memory — only affects index vs sequential scan cost estimates.

---

### 3. work_mem — In-Memory Sorts & Hashes

Each sort, hash join, or merge operation can use up to `work_mem` **per node per query**.

```ini
work_mem = 32MB    # global default — keep conservative
```

```sql
-- Reporting role gets more
ALTER ROLE analyst SET work_mem = '256MB';

-- Single heavy query
SET work_mem = '512MB';
EXPLAIN ANALYZE SELECT ... ORDER BY ...;
RESET work_mem;
```

**Danger:** `work_mem × active sorts × connections` can exhaust RAM.

```
Safe default ≈ (RAM - shared_buffers) / (max_connections × 3)
```

Watch for disk spills:

```sql
-- Queries spilling to disk
SELECT query, calls, temp_blks_written
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC LIMIT 10;
```

---

### 4. maintenance_work_mem — VACUUM, CREATE INDEX, ALTER

```ini
maintenance_work_mem = 1GB     # 5–10% RAM; cap ~2 GB unless bulk maintenance
```

```sql
-- Single large index build
SET maintenance_work_mem = '2GB';
CREATE INDEX CONCURRENTLY idx_big ON large_table (col);
```

Used by: `VACUUM`, `CREATE INDEX`, `ALTER TABLE ADD FOREIGN KEY`, parallel vacuum workers.

---

### 5. temp_buffers — Session Temp Tables

```ini
temp_buffers = 32MB    # per session; only for TEMP tables
```

```sql
SET temp_buffers = '256MB';
CREATE TEMP TABLE staging AS SELECT * FROM orders WHERE ...;
```

Memory returned at session end.

---

### 6. hash_mem_multiplier (PG 13+)

Scales hash table memory relative to `work_mem` for hash joins/aggs.

```ini
hash_mem_multiplier = 2.0    # hash operations can use 2× work_mem
```

---

### 7. Huge Pages (Linux) — Shared Memory Integration

Reduces TLB misses for large `shared_buffers`.

```bash
# Estimate pages (2MB huge pages)
echo $(($(grep shared_buffers /path/postgresql.conf | awk '{print $3}') * 8192 / 2 / 1024 / 1024))

# /etc/sysctl.d
vm.nr_hugepages = 4096
```

```ini
huge_pages = try    # or on — fail start if unavailable when 'on'
```

```sql
SELECT * FROM pg_settings WHERE name = 'huge_pages';
```

Verify:

```bash
grep HugePages /proc/meminfo
```

---

### 8. pg_prewarm — Warm shared_buffers After Restart

Loads relation pages into `shared_buffers` from disk — reduces cold-cache latency.

```sql
CREATE EXTENSION pg_prewarm;

-- Warm entire table
SELECT pg_prewarm('orders');

-- Options: 'buffer' (shared_buffers), 'read' (OS cache only), 'prefetch'
SELECT pg_prewarm('orders', 'buffer');

-- Autoprewarm — save/load buffer state across restarts (PG 18: check extension docs)
-- shared_preload_libraries = 'pg_prewarm'
-- pg_prewarm.autoprewarm = on
```

**HA failover:** Run `pg_prewarm` on new primary after promotion for hot tables.

```sql
-- Warm top tables script
SELECT pg_prewarm(c.oid::regclass)
FROM pg_class c
JOIN pg_stat_user_tables s ON s.relid = c.oid
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;
```

---

### 9. pg_buffercache — Inspect What Is in RAM

```sql
CREATE EXTENSION pg_buffercache;

-- Pages cached per table
SELECT c.relname,
       count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS cached
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = c.relfilenode
WHERE c.relname = 'orders'
GROUP BY c.relname;

-- Cache usage summary
SELECT usagecount, count(*) FROM pg_buffercache GROUP BY usagecount;
```

---

### 10. UNLOGGED Tables — Minimal WAL (Not True In-Memory)

Data on disk but **not crash-safe** — contents lost on unclean shutdown. Faster writes (no WAL for data).

```sql
CREATE UNLOGGED TABLE session_cache (
  session_id uuid PRIMARY KEY,
  payload jsonb,
  expires_at timestamptz
);

-- Revert to logged
ALTER TABLE session_cache SET LOGGED;   -- triggers full rewrite
```

| Use | Avoid |
|-----|-------|
| Staging ETL | Financial data |
| Session scratch | Anything needed after crash |
| Rebuildable cache | Replication to standby (UNLOGGED not replicated) |

---

### 11. MATERIALIZED VIEW — Disk-Backed Result Cache

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
  SELECT date_trunc('day', created_at) AS day, sum(total) AS revenue
  FROM orders GROUP BY 1;

CREATE UNIQUE INDEX ON mv_daily_sales (day);

REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_sales;
```

Schedule refresh via [pg_cron](../10-advanced/pg-cron-agent.md).

---

### 12. PostgreSQL 18 — Async I/O & Memory

AIO improves read throughput — works with `shared_buffers` and OS cache, not a separate memory store.

```ini
io_method = worker
io_combine_limit = 128kB
effective_io_concurrency = 200
```

```sql
SELECT * FROM pg_aios;
```

---

## Memory Parameters — Complete Reference

| Parameter | Default (approx) | Scope | Restart? |
|-----------|------------------|-------|----------|
| `shared_buffers` | 128MB | Cluster | Yes |
| `effective_cache_size` | 4GB | Planner hint | No |
| `work_mem` | 4MB | Per sort/hash op | No |
| `maintenance_work_mem` | 64MB | Per maintenance op | No |
| `temp_buffers` | 8MB | Per session | No |
| `wal_buffers` | auto | Cluster | Yes |
| `hash_mem_multiplier` | 2.0 | Per hash op | No |
| `logical_decoding_work_mem` | 64MB | Logical replication | No |
| `max_stack_depth` | 2MB | Per backend | No |
| `shared_memory_size` | — | PG 18: total shared mem | — |
| `shared_memory_size_in_huge_pages` | — | PG 18: huge page count | — |

```sql
-- PG 18: inspect shared memory allocation
SELECT name, setting, unit, context
FROM pg_settings
WHERE name LIKE '%mem%' OR name LIKE '%buffer%'
ORDER BY name;
```

---

## OS Integration — Linux Memory

### sysctl tuning

```ini
# /etc/sysctl.d/99-postgresql-memory.conf
vm.swappiness = 1                 # avoid swapping shared_buffers
vm.overcommit_memory = 2          # strict overcommit
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
```

```bash
sudo sysctl -p /etc/sysctl.d/99-postgresql-memory.conf
```

### Transparent Huge Pages (THP)

PostgreSQL recommends **disabling** THP on Linux — can cause latency spikes.

```bash
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag
```

Use explicit `huge_pages = try/on` instead.

### Swap

Avoid swap for DB servers. If unavoidable:

```bash
# Monitor swap usage
free -h
vmstat 1

-- OOM risk — find long-running heavy queries
SELECT pid, usename, state, left(query, 80) AS query
FROM pg_stat_activity
WHERE state = 'active' AND pid <> pg_backend_pid();
```

```sql
-- PG 18: per-backend memory (if enabled)
SELECT pid, memory_context_name, total_bytes
FROM pg_backend_memory_contexts
WHERE pid = pg_backend_pid()
ORDER BY total_bytes DESC LIMIT 20;
```

---

## External In-Memory Integration Patterns

PostgreSQL has **no built-in Redis/Memcached module** in core. Integrate at application or extension layer.

### Pattern A — Application Cache (Most Common)

```
App ──► Redis (hot keys, sessions, rate limits)
  │
  └──► PostgreSQL (source of truth, durable data)
```

| Cache | Store | TTL | Invalidation |
|-------|-------|-----|--------------|
| User session | Redis | 30 min | Logout / expiry |
| Product catalog | Redis | 5 min | Pub/sub on PG UPDATE |
| Query result | Redis | 1 min | Version key in cache key |

**Cache-aside flow:**

1. Read Redis → hit → return
2. Miss → read PostgreSQL → write Redis → return
3. Write → update PostgreSQL → delete/invalidate Redis key

---

### Pattern B — redis_fdw (Foreign Data Wrapper)

Query Redis from SQL — read-heavy, optional writes.

```bash
sudo dnf install postgresql18-redis_fdw   # if available in PGDG
```

```sql
CREATE EXTENSION redis_fdw;

CREATE SERVER redis_server
  FOREIGN DATA WRAPPER redis_fdw
  OPTIONS (address '127.0.0.1', port '6379');

CREATE FOREIGN TABLE redis_cache (
  key text,
  value text
) SERVER redis_server
  OPTIONS (database '0');

SELECT * FROM redis_cache WHERE key = 'user:123';
```

**Use when:** SQL-centric apps need cache lookups in joins or reporting.

---

### Pattern C — LISTEN/NOTIFY for Cache Invalidation

```sql
-- PostgreSQL trigger on update
CREATE OR REPLACE FUNCTION notify_cache_invalidate() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('cache_invalidate', TG_TABLE_NAME || ':' || NEW.id::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_notify
  AFTER INSERT OR UPDATE OR DELETE ON orders
  FOR EACH ROW EXECUTE FUNCTION notify_cache_invalidate();
```

Application subscribes to `cache_invalidate` and purges Redis keys.

---

### Pattern D — Logical Replication to Read Models

Stream changes to another store (analytics DB, search index, cache warmer).

```
PostgreSQL (primary) ──logical replication──► Subscriber / Debezium ──► Redis / Elasticsearch
```

---

### Pattern E — PgBouncer (Connection Memory, Not Data Cache)

Each PostgreSQL backend uses ~5–10 MB baseline RAM. PgBouncer multiplexes connections:

```
1000 app connections ──► PgBouncer (50 pool) ──► PostgreSQL (50 backends)
```

Reduces **connection memory overhead**, not data caching. See [Connection Pooling](../10-advanced/connection-pooling.md).

---

### Pattern F — Citus / Distributed (Sharding, Not RAM Store)

Citus spreads data across nodes — horizontal scale, not in-memory column store.

---

## HA / Patroni Memory Considerations

| Topic | Guidance |
|-------|----------|
| All nodes same `shared_buffers` | Yes — consistent performance after failover |
| `pg_prewarm` after failover | Warm critical tables on new primary |
| UNLOGGED on standby | Not replicated — only on primary |
| Replication lag | Large `work_mem` sorts on primary increase WAL volume indirectly |

```yaml
# patroni.yml — memory params (PG 18 example, 64 GB RAM)
postgresql:
  parameters:
    shared_buffers: 16GB
    effective_cache_size: 48GB
    work_mem: 64MB
    maintenance_work_mem: 2GB
    huge_pages: try
    io_method: worker
```

---

## Docker / Kubernetes Memory Limits

```yaml
# Kubernetes — set limits above shared_buffers + work_mem headroom
resources:
  requests:
    memory: "24Gi"
  limits:
    memory: "28Gi"
env:
  - name: POSTGRES_SHARED_BUFFERS
    value: "8GB"
```

**Rule:** Container limit ≥ `shared_buffers` + `(max_connections × ~10MB)` + OS headroom.

OOM kill in K8s → pod restart — set `shared_buffers` conservatively in constrained pods.

---

## Sizing Templates (PG 18)

### 8 GB RAM (dev/small)

```ini
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 16MB
maintenance_work_mem = 256MB
max_connections = 50
```

### 64 GB RAM (production OLTP)

```ini
shared_buffers = 16GB
effective_cache_size = 48GB
work_mem = 64MB
maintenance_work_mem = 2GB
max_connections = 200
huge_pages = try
io_method = worker
shared_preload_libraries = pg_stat_statements,pg_prewarm
```

### 256 GB RAM (analytics / mixed)

```ini
shared_buffers = 32GB
effective_cache_size = 192GB
work_mem = 256MB
maintenance_work_mem = 4GB
max_parallel_workers = 16
```

---

## Monitoring Checklist

```sql
-- Cache hit ratio
SELECT datname, blks_hit, blks_read,
       round(blks_hit::numeric / nullif(blks_hit + blks_read, 0) * 100, 2) AS hit_pct
FROM pg_stat_database WHERE datname = current_database();

-- Memory-related waits
SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity WHERE wait_event IS NOT NULL
GROUP BY 1, 2;

-- Temp file usage (work_mem too low)
SELECT datname, temp_files, pg_size_pretty(temp_bytes)
FROM pg_stat_database ORDER BY temp_bytes DESC;
```

Prometheus / postgres_exporter: track `pg_stat_database_blks_hit`, `pg_stat_database_temp_bytes`.

---

## What PostgreSQL Does NOT Have (vs Other Databases)

| Feature | Oracle / SQL Server | PostgreSQL 18 |
|---------|---------------------|---------------|
| In-memory column store | Yes | **No** — use OS cache + shared_buffers |
| Buffer pool per table | Partial | shared_buffers shared globally |
| Native Redis integration | No | **No** — app layer or redis_fdw |
| All-RAM database mode | TimesTen etc. | **No** — use UNLOGGED + risk acceptance |

---

## Related

- [Architecture — Memory](../01-getting-started/architecture.md)
- [Tuning Parameters](tuning-parameters.md)
- [postgresql.conf](../02-configuration/postgresql-conf.md)
- [Parameters Quick Reference](../cheat-sheets/parameters-quick-ref.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
- [pg_cron](../10-advanced/pg-cron-agent.md)
- [PG 18 Features](../01-getting-started/postgresql-18.md)
