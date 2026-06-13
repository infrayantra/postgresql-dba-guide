# Autovacuum Tuning

Autovacuum is **critical** — do not disable in production.

## How It Works

1. **Launcher** wakes every `autovacuum_naptime`
2. Selects tables exceeding vacuum/analyze thresholds
3. **Workers** run VACUUM/ANALYZE with cost limits

## Trigger Formula

```
vacuum trigger = autovacuum_vacuum_threshold +
                 autovacuum_vacuum_scale_factor × n_live_tup

analyze trigger = autovacuum_analyze_threshold +
                  autovacuum_analyze_scale_factor × n_live_tup
```

Example: 1M row table, scale 0.1 → vacuum after ~100,050 dead tuples.

## Global Settings

```ini
autovacuum = on
autovacuum_max_workers = 4       # increase on large servers (3-6 typical)
autovacuum_naptime = 30s         # reduce for hot systems (10s)
autovacuum_vacuum_cost_delay = 2ms
autovacuum_vacuum_cost_limit = 1000   # higher = faster vacuum, more I/O
```

## When Defaults Fail

High-churn tables need aggressive per-table settings:

```sql
ALTER TABLE events SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_scale_factor = 0.005,
  autovacuum_vacuum_cost_delay = 0
);
```

Large static tables:

```sql
ALTER TABLE archive SET (autovacuum_enabled = false);
-- run manual VACUUM rarely
```

## Monitor Autovacuum

```sql
SELECT pid, datname, relid::regclass, phase, heap_blks_total, heap_blks_scanned,
       heap_blks_vacuumed, index_vacuum_count
FROM pg_stat_progress_vacuum;

SELECT query, state, wait_event
FROM pg_stat_activity
WHERE query LIKE 'autovacuum%';
```

```ini
log_autovacuum_min_duration = 0   # log every run
```

## Anti-Wraparound Vacuum

When `age(relfrozenxid)` approaches `autovacuum_freeze_max_age` (200M default), autovacuum runs **aggressive** vacuum regardless of dead tuple count.

```sql
SELECT relname, age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER BY xid_age DESC;
```

**Alert** if xid_age > 150M.

## Common Problems

| Problem | Cause | Fix |
|---------|-------|-----|
| Table bloat | autovacuum can't keep up | Lower scale_factor, more workers |
| No autovacuum on table | `autovacuum_enabled=off` | Enable |
| Wraparound warning | Long tx blocking vacuum | Terminate idle tx |
| High I/O | cost_limit too high | Increase cost_delay |

## Do NOT Disable Globally

```ini
# NEVER in production:
# autovacuum = off
```

If "too much I/O", tune per-table or adjust cost parameters.

## Related

- [VACUUM & ANALYZE](vacuum-analyze.md)
- [VACUUM & Bloat](../06-performance/vacuum-bloat.md)
