# Locking & Concurrency

## Lock Types

| Lock | Mode | Blocks |
|------|------|--------|
| AccessShareLock | SELECT | AccessExclusive |
| RowShareLock | SELECT FOR UPDATE/SHARE | Exclusive, AccessExclusive |
| RowExclusiveLock | INSERT/UPDATE/DELETE | Share, Exclusive, AccessExclusive |
| ShareUpdateExclusiveLock | VACUUM, CREATE INDEX CONCURRENTLY | Same |
| ShareLock | CREATE INDEX (non-concurrent) | RowExclusive+ |
| ExclusiveLock | REFRESH MAT VIEW CONCURRENTLY | RowShare+ |
| AccessExclusiveLock | ALTER TABLE, DROP, TRUNCATE, VACUUM FULL | **All** |

## View Locks

```sql
SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks
WHERE relation IS NOT NULL
ORDER BY relation;

-- Blockers
SELECT * FROM pg_blocking_pids(12345);
```

## Deadlocks

PostgreSQL detects deadlocks automatically (default `deadlock_timeout = 1s`):

```
ERROR: deadlock detected
DETAIL: Process 123 waits for ShareLock on transaction 456; blocked by process 789...
```

**Prevention:** consistent lock ordering in application code; keep transactions short.

## Advisory Locks

Application-level coordination:

```sql
SELECT pg_advisory_lock(12345);       -- session level
SELECT pg_advisory_xact_lock(12345);  -- transaction level
SELECT pg_try_advisory_lock(12345);   -- non-blocking

SELECT pg_advisory_unlock(12345);
```

Used by migrations, job schedulers, pg_partman.

## Serializable Isolation

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
-- may get: ERROR: could not serialize access due to read/write dependencies
```

Handle with retry in application.

## Row-Level Locks

```sql
SELECT * FROM orders WHERE id = 1 FOR UPDATE;           -- exclusive row lock
SELECT * FROM orders WHERE id = 1 FOR UPDATE SKIP LOCKED;  -- queue workers
SELECT * FROM orders WHERE id = 1 FOR UPDATE NOWAIT;     -- fail immediately
SELECT * FROM orders WHERE id = 1 FOR SHARE;            -- shared row lock
```

## Hot Standby Conflicts

Standby queries can conflict with WAL apply:

```sql
SELECT * FROM pg_stat_database_conflicts;
-- canceling statement due to conflict with recovery
```

## Long Transaction Impact

- Blocks VACUUM (dead tuple accumulation)
- Holds row locks
- Increases replication lag visibility

```sql
SELECT pid, xact_start, state, query
FROM pg_stat_activity
WHERE xact_start < now() - interval '1 hour';
```

## Related

- [System Catalogs](../07-monitoring/system-catalogs.md)
- [Architecture — MVCC](../01-getting-started/architecture.md)
- [Common Errors](../11-troubleshooting/common-errors.md)
