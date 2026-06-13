# VACUUM, Bloat & Storage

## Why VACUUM Exists

PostgreSQL MVCC leaves **dead tuples** after UPDATE/DELETE. VACUUM:

1. Reclaims space for reuse (does not return to OS except edge cases)
2. Updates visibility map (enables index-only scans)
3. Freezes old XIDs (prevents wraparound)
4. Updates planner statistics (with ANALYZE)

## Manual VACUUM

```sql
VACUUM VERBOSE orders;
VACUUM (VERBOSE, ANALYZE) orders;
VACUUM FULL orders;           -- rewrites table, exclusive lock — avoid in prod
VACUUM (PARALLEL 4) big_table;  -- PG 13+ index vacuum parallel
```

## Bloat Detection

```sql
-- pg_stat_user_tables
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC;
```

Use `pgstattuple` extension for precise bloat:

```sql
CREATE EXTENSION pgstattuple;
SELECT * FROM pgstattuple('orders');
SELECT * FROM pgstatindex('orders_pkey');
```

## Reclaim Space to OS

| Method | Lock | Returns disk |
|--------|------|--------------|
| VACUUM | ShareUpdateExclusive | Rarely |
| VACUUM FULL | AccessExclusive | Yes |
| pg_repack | Minimal | Yes |
| CLUSTER | AccessExclusive | Partial |

**pg_repack** (extension) — online rewrite:

```bash
pg_repack -d app_db -t orders
```

## Transaction ID Wraparound

```sql
SELECT datname, age(datfrozenxid) AS age,
       current_setting('autovacuum_freeze_max_age')::int AS max_age
FROM pg_database
ORDER BY age DESC;
```

Emergency: `VACUUM FREEZE VERBOSE`; ensure autovacuum not blocked.

## Fillfactor

```sql
ALTER TABLE orders SET (fillfactor = 80);
-- leaves 20% page space for HOT updates (same-page updates without index churn)
```

## HOT Updates

Updates avoiding indexed columns may stay on same page (Heap-Only Tuple) — no new index entries.

Monitor:

```sql
SELECT relname, n_tup_upd, n_tup_hot_upd,
       round(n_tup_hot_upd * 100.0 / nullif(n_tup_upd, 0), 1) AS hot_pct
FROM pg_stat_user_tables;
```

## Toast Bloat

Oversized values stored in TOAST tables:

```sql
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

## Long Transactions Block VACUUM

```sql
SELECT pid, usename, state, xact_start, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

Idle in transaction = vacuum blocker.

## Prepared Transactions

```sql
SELECT * FROM pg_prepared_xacts;  -- blocks vacuum on involved rows
COMMIT PREPARED 'gid';
```

## Table & Index Maintenance Schedule

| Frequency | Action |
|-----------|--------|
| Continuous | autovacuum |
| Weekly | Review dead_pct, bloat queries |
| Monthly | pg_repack on bloated tables |
| Quarterly | REINDEX CONCURRENTLY on degraded indexes |

## Related

- [Autovacuum](../09-maintenance/autovacuum.md)
- [Indexing](indexing.md)
- [Architecture — MVCC](../01-getting-started/architecture.md)
