# System Catalogs & Views

## Essential pg_stat_* Views

| View | Purpose |
|------|---------|
| `pg_stat_activity` | Current sessions, queries, wait events |
| `pg_stat_replication` | Replication status (primary) |
| `pg_stat_user_tables` | Seq/index scans, tuples, vacuum stats |
| `pg_stat_user_indexes` | Index usage |
| `pg_stat_database` | DB-level commits, deadlocks, cache hit |
| `pg_stat_bgwriter` | Checkpoint, buffer writes |
| `pg_stat_archiver` | WAL archive success/fail |
| `pg_stat_subscription` | Logical replication (subscriber) |
| `pg_stat_io` | I/O statistics (PG 16+) |

## pg_stat_activity

```sql
SELECT pid, usename, datname, state, wait_event_type, wait_event,
       query_start, state_change,
       left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;
```

| state | Meaning |
|-------|---------|
| active | Executing query |
| idle | Waiting for client |
| idle in transaction | Open transaction, no active query |
| idle in transaction (aborted) | Failed tx not rolled back |

## Cache Hit Ratio

```sql
SELECT datname,
       blks_hit * 100.0 / nullif(blks_hit + blks_read, 0) AS cache_hit_pct
FROM pg_stat_database
WHERE datname = current_database();
```

Target: **> 99%** for OLTP; lower may be OK for analytics.

## Table Access Patterns

```sql
SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch,
       n_tup_ins, n_tup_upd, n_tup_del
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;
```

High `seq_scan` on large tables → investigate indexes.

## Lock Inspection

```sql
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks blkr ON bl.locktype = blkr.locktype
  AND bl.database IS NOT DISTINCT FROM blkr.database
  AND bl.relation IS NOT DISTINCT FROM blkr.relation
  AND bl.page IS NOT DISTINCT FROM blkr.page
  AND bl.tuple IS NOT DISTINCT FROM blkr.tuple
  AND bl.virtualxid IS NOT DISTINCT FROM blkr.virtualxid
  AND bl.transactionid IS NOT DISTINCT FROM blkr.transactionid
  AND bl.classid IS NOT DISTINCT FROM blkr.classid
  AND bl.objid IS NOT DISTINCT FROM blkr.objid
  AND bl.objsubid IS NOT DISTINCT FROM blkr.objsubid
  AND bl.pid != blkr.pid
JOIN pg_stat_activity blocking ON blocking.pid = blkr.pid
WHERE bl.granted = false;
```

## Catalog Queries

```sql
-- Table definitions
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'orders';

-- Index definitions
SELECT indexdef FROM pg_indexes WHERE tablename = 'orders';

-- Foreign keys
SELECT conname, conrelid::regclass, confrelid::regclass
FROM pg_constraint WHERE contype = 'f';

-- Table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(oid))
FROM pg_class WHERE relkind = 'r' ORDER BY pg_total_relation_size(oid) DESC;
```

## pg_catalog vs. information_schema

Prefer `pg_catalog` for PG-specific metadata; `information_schema` is SQL-standard portable.

## Reset Statistics

```sql
SELECT pg_stat_reset();                    -- database stats
SELECT pg_stat_reset_shared('archiver');  -- specific subsystem
```

## Related

- [pg_stat_statements](pg-stat-statements.md)
- [Slow Queries](../11-troubleshooting/slow-queries.md)
- [Locking](../10-advanced/locking-concurrency.md)
