# pg_stat_statements

Tracks normalized SQL execution statistics cluster-wide. **Essential for performance monitoring.**

## Setup

```ini
# postgresql.conf — requires RESTART
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = all       # top | all | none
pg_stat_statements.track_utility = on
pg_stat_statements.save = on
```

```sql
CREATE EXTENSION pg_stat_statements;
```

## Key Queries

### Top by Total Time

```sql
SELECT queryid,
       left(query, 100) AS query,
       calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows,
       shared_blks_hit,
       shared_blks_read,
       temp_blks_written
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

### Top by Mean Time (Slow Individual Runs)

```sql
SELECT left(query, 100), calls,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       round(max_exec_time::numeric, 2) AS max_ms
FROM pg_stat_statements
WHERE calls > 10
ORDER BY mean_exec_time DESC
LIMIT 20;
```

### Most Called

```sql
SELECT left(query, 80), calls, rows / calls AS avg_rows
FROM pg_stat_statements
ORDER BY calls DESC LIMIT 20;
```

### I/O Heavy

```sql
SELECT left(query, 80),
       shared_blks_read + shared_blks_dirtied AS io_blocks,
       calls
FROM pg_stat_statements
ORDER BY shared_blks_read DESC LIMIT 20;
```

## PG 15+ Columns

Uses `total_exec_time`, `mean_exec_time` (was `total_time`, `mean_time` in older versions).

## Reset Stats

```sql
SELECT pg_stat_statements_reset();                    -- all
SELECT pg_stat_statements_reset(12345);               -- by queryid
SELECT pg_stat_statements_reset(0, 0, 123456789::oid); -- by db oid
```

## Capture Query Text

```sql
SELECT query FROM pg_stat_statements WHERE queryid = 123456789;
```

With `track = all`, nested statements inside functions are tracked separately.

## Integration with Monitoring

Export via:
- **postgres_exporter** (Prometheus) — `pg_stat_statements` custom query
- **pganalyze**
- **Datadog / New Relic** PostgreSQL integrations

## Security Note

Query text may contain literals (unless using prepared statements). Restrict access:

```sql
REVOKE ALL ON pg_stat_statements FROM PUBLIC;
GRANT SELECT ON pg_stat_statements TO pg_monitor;
```

## Related

- [Query Optimization](../06-performance/query-optimization.md)
- [Logging](logging.md)
- [Metrics Exporters](metrics-exporters.md)
