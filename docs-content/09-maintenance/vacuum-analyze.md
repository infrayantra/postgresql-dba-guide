# VACUUM & ANALYZE

## VACUUM

Reclaims dead tuple space, updates visibility map, prevents XID wraparound.

```sql
VACUUM;                          -- all tables in current DB
VACUUM VERBOSE orders;
VACUUM (ANALYZE) orders;          -- vacuum + analyze in one pass
VACUUM FREEZE orders;            -- aggressive freeze
VACUUM FULL orders;              -- exclusive lock, rewrites — emergency only
```

## ANALYZE

Updates planner statistics in `pg_statistic`.

```sql
ANALYZE;
ANALYZE orders;
ANALYZE orders (customer_id, status);  -- column list PG 14+
```

Run after:
- Large bulk loads
- CREATE INDEX CONCURRENTLY completion
- Significant data changes

## Monitoring Need for VACUUM

```sql
SELECT relname, n_dead_tup, last_vacuum, last_autovacuum, last_analyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

## Manual vs Autovacuum

| Scenario | Action |
|----------|--------|
| Normal OLTP | Rely on autovacuum |
| Bulk delete/update | `VACUUM ANALYZE` after job |
| Autovacuum blocked | Fix long transactions, then manual VACUUM |
| Anti-wraparound | Watch `age(datfrozenxid)` |

## Cost-Based Vacuum Throttling

```ini
vacuum_cost_delay = 0           # PG 13+ default — no throttling
vacuum_cost_limit = 200
```

For replicas under I/O pressure, increase delay.

## Per-Table Storage Parameters

```sql
ALTER TABLE events SET (
  autovacuum_enabled = true,
  autovacuum_vacuum_threshold = 1000,
  autovacuum_vacuum_scale_factor = 0.0,
  autovacuum_analyze_scale_factor = 0.01,
  fillfactor = 90
);
```

## Parallel VACUUM (PG 13+)

```sql
VACUUM (PARALLEL 4, VERBOSE) large_table;
```

Index vacuum runs in parallel; requires `max_parallel_maintenance_workers > 0`.

## Related

- [Autovacuum](autovacuum.md)
- [VACUUM & Bloat](../06-performance/vacuum-bloat.md)
