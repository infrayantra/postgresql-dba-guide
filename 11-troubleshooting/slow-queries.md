# Slow Query Investigation

Systematic workflow for PostgreSQL performance incidents.

## Step 1: Identify the Query

```sql
-- Currently running slow queries
SELECT pid, now() - query_start AS duration, state, wait_event_type, wait_event,
       left(query, 200) AS query
FROM pg_stat_activity
WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration DESC;

-- Historical — pg_stat_statements
SELECT left(query, 100), calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(total_exec_time::numeric, 2) AS total_ms
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 10;
```

## Step 2: EXPLAIN (ANALYZE, BUFFERS)

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
<paste query here>;
```

### Interpret Key Signals

| Signal | Likely issue |
|--------|--------------|
| Seq Scan on large table | Missing index, stale stats |
| Rows estimate >> actual | Stale ANALYZE, correlated columns |
| Nested Loop + high loops | Bad join order, missing index on inner |
| Sort / Hash batches to disk | work_mem too low |
| High shared_blks_read | Cold cache or too much random I/O |
| Lock wait in activity | Blocker query |

## Step 3: Check Statistics

```sql
SELECT relname, last_analyze, last_autoanalyze, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'orders';

ANALYZE orders;
```

## Step 4: Index Analysis

```sql
-- Existing indexes
SELECT indexdef FROM pg_indexes WHERE tablename = 'orders';

-- Unused indexes (don't add more blindly)
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes WHERE relname = 'orders';
```

## Step 5: Wait Events (PG 9.6+)

```sql
SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
GROUP BY 1, 2;
```

| wait_event | Meaning |
|------------|---------|
| IO / DataFileRead | Disk read |
| Lock / transactionid | Lock wait |
| LWLock | Internal contention |
| Client / ClientRead | Waiting for client |

## Step 6: Server Resources

```bash
top -u postgres
iostat -x 1
vmstat 1
```

Correlate CPU, I/O wait, memory with query patterns.

## Common Fixes

### Missing Index

```sql
CREATE INDEX CONCURRENTLY idx_orders_created ON orders (created_at)
  WHERE status = 'pending';
```

### Bloated Table

```sql
VACUUM (VERBOSE, ANALYZE) orders;
-- or pg_repack
```

### Bad Parameter Sniffing

```sql
SET plan_cache_mode = force_custom_plan;
-- or PREPARE with typical values; upgrade stats
```

### Too Many Connections

Deploy PgBouncer; reduce connection count from app servers.

## Capture Query for Later

```sql
SELECT pg_cancel_backend(pid);  -- graceful
SELECT pg_terminate_backend(pid);  -- force
```

Enable `auto_explain` for proactive capture.

## Reporting Template

```
Query ID / fingerprint:
Mean time / calls:
EXPLAIN finding:
Root cause:
Fix applied:
Verification:
```

## Related

- [Query Optimization](../06-performance/query-optimization.md)
- [Indexing](../06-performance/indexing.md)
- [pg_stat_statements](../07-monitoring/pg-stat-statements.md)
