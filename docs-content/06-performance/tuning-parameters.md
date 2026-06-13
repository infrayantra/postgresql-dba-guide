# Memory & I/O Tuning Parameters

> **Deep dive:** [In-Memory Features & Integration](in-memory-features-integration.md) — shared_buffers, work_mem, huge pages, pg_prewarm, Redis integration.

## RAM Sizing Framework

For a **dedicated** PostgreSQL server:

```
shared_buffers     = 25% of RAM (cap ~8-16 GB on Linux)
effective_cache_size = 50-75% of RAM
work_mem           = calculated (see below)
maintenance_work_mem = 5-10% of RAM (cap ~2 GB unless bulk ops)
```

### work_mem Calculation

```
work_mem ≈ (RAM - shared_buffers) / (max_connections × 3)
```

Example: 32 GB RAM, 200 connections:
```
(32GB - 8GB) / (200 × 3) ≈ 40 MB
```

Use lower global default; raise per-session for reporting roles.

## I/O Settings (SSD vs HDD)

| Parameter | SSD/NVMe | HDD |
|-----------|----------|-----|
| `random_page_cost` | 1.1 – 1.5 | 4.0 |
| `effective_io_concurrency` | 200 – 1000 | 2 – 4 |
| `seq_page_cost` | 1.0 | 1.0 |

```sql
ALTER SYSTEM SET random_page_cost = 1.1;
SELECT pg_reload_conf();
```

## WAL & Checkpoint Tuning

High write throughput:

```ini
max_wal_size = 8GB
min_wal_size = 2GB
checkpoint_completion_target = 0.9
wal_compression = on
wal_buffers = 64MB
```

Spread checkpoint I/O:

```
checkpoint writes ≈ shared_buffers dirty pages over (checkpoint_timeout × completion_target)
```

## Connection & Parallelism

```ini
max_connections = 100          # use PgBouncer beyond this
max_worker_processes = 16
max_parallel_workers = 8
max_parallel_workers_per_gather = 4
max_parallel_maintenance_workers = 4
```

```sql
-- Per-query parallel (PG 14+)
SET max_parallel_workers_per_gather = 8;
```

## Planner Statistics

```ini
default_statistics_target = 100   # 500 for skewed columns
constraint_exclusion = partition  # for partitioned tables
```

```sql
ALTER TABLE orders ALTER COLUMN status SET STATISTICS 500;
CREATE STATISTICS orders_corr (dependencies) ON customer_id, status FROM orders;
ANALYZE orders;
```

## Vacuum & Bloat Parameters

```ini
autovacuum_vacuum_scale_factor = 0.05   # lower for hot tables
autovacuum_analyze_scale_factor = 0.02
vacuum_cost_delay = 0                   # PG 13+ default 0
```

Per-table:

```sql
ALTER TABLE hot_table SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.01,
  fillfactor = 90
);
```

## JIT Compilation (PG 11+)

```ini
jit = on
jit_above_cost = 100000
jit_inline_above_cost = 500000
```

Disable for OLTP if overhead exceeds benefit:

```sql
ALTER DATABASE app_db SET jit = off;
```

## Huge Pages (Linux)

```bash
# Estimate: shared_buffers in pages × 2MB
grep HugePages /proc/meminfo

# sysctl
vm.nr_hugepages = 4096
```

```ini
huge_pages = try   # or on
```

## Monitoring Tuning Impact

```sql
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 20;
```

Compare before/after with same workload.

## PG 18 — Shared Memory Visibility

```sql
SHOW shared_memory_size;
SHOW shared_memory_size_in_huge_pages;
SELECT * FROM pg_backend_memory_contexts WHERE pid = pg_backend_pid() ORDER BY total_bytes DESC LIMIT 10;
```

## PG 18: Asynchronous I/O

```ini
io_method = worker
io_combine_limit = 128kB
io_max_combine_limit = 1MB
effective_io_concurrency = 200    # more useful on PG 18 without fadvise
maintenance_io_concurrency = 200
```

```sql
SELECT * FROM pg_aios;
```

After upgrading to PG 18, benchmark sequential scans and VACUUM duration before/after enabling AIO — see [pgbench](pgbench.md).

## Instance Size Templates

### 4 GB RAM (small dev/staging)

```ini
shared_buffers = 1GB
effective_cache_size = 3GB
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
max_wal_size = 8GB
effective_io_concurrency = 200
random_page_cost = 1.1
```

### 256 GB RAM (analytics / mixed)

```ini
shared_buffers = 32GB
effective_cache_size = 192GB
work_mem = 256MB
maintenance_work_mem = 4GB
max_parallel_workers = 16
```

## Related

- [postgresql.conf](../02-configuration/postgresql-conf.md)
- [Query Optimization](query-optimization.md)
- [VACUUM & Bloat](vacuum-bloat.md)
