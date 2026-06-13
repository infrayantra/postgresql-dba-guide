# Common Errors & Fixes

## Connection Errors

### `FATAL: too many connections`

```sql
-- Emergency: terminate idle connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND pid <> pg_backend_pid();

-- Long-term: PgBouncer, raise max_connections carefully
ALTER SYSTEM SET max_connections = 300;
-- requires restart
```

### `FATAL: no pg_hba.conf entry for host`

Add matching rule to `pg_hba.conf`; reload. Check rule order — first match wins.

### `FATAL: password authentication failed`

Verify SCRAM password, `pg_hba.conf` method, user exists:

```sql
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'app_user';
```

## Disk Space

### `ERROR: could not extend file`

```bash
df -h $PGDATA
du -sh $PGDATA/pg_wal/*
```

Causes: full disk, WAL bloat from replication slot, runaway temp files.

```sql
-- Find replication slot holding WAL
SELECT * FROM pg_replication_slots;

-- Temp file usage
SELECT datname, temp_files, pg_size_pretty(temp_bytes)
FROM pg_stat_database ORDER BY temp_bytes DESC;
```

## Memory

### `ERROR: out of memory`

Reduce `work_mem`, `maintenance_work_mem`; check parallel workers; OS OOM killer logs (`dmesg`).

### `ERROR: temporary file size exceeds temp_file_limit`

```sql
SET temp_file_limit = '10GB';  -- or fix query (sort/hash too large)
```

## Transaction & Lock

### `ERROR: deadlock detected`

Review application lock order; keep transactions short. Log shows conflicting queries.

### `ERROR: canceling statement due to lock timeout`

```sql
SET lock_timeout = '5s';
-- Find blocker: pg_blocking_pids(), pg_stat_activity
```

### `ERROR: idle-in-transaction timeout`

```ini
idle_in_transaction_session_timeout = 5min
```

Fix connection pool leak leaving transactions open.

## Constraint Violations

```sql
-- Find duplicate for UNIQUE violation
SELECT col, count(*) FROM t GROUP BY col HAVING count(*) > 1;

-- FK violation: row missing in parent
```

## Corruption Indicators

```
ERROR: invalid page in block
WARNING: page verification failed
ERROR: could not read block
```

See [Corruption Recovery](corruption-recovery.md).

## Replication

### `requested WAL segment has been removed`

Standby too far behind; missing WAL archive. Rebuild standby from base backup.

### `conflict with recovery`

Cancel long standby queries or tune `max_standby_streaming_delay`.

## Encoding / Locale

```
ERROR: character with byte sequence ... in encoding "UTF8" has no equivalent
```

Client encoding mismatch; sanitize input or convert:

```sql
SET client_encoding = 'UTF8';
```

## Permission

```
ERROR: permission denied for table
```

```sql
GRANT SELECT ON table TO role;
-- PG 15: GRANT CREATE ON SCHEMA public ...
```

## Useful Diagnostic Queries

```sql
SHOW server_version;
SELECT * FROM pg_stat_activity WHERE pid = <pid>;
SELECT * FROM pg_locks WHERE NOT granted;
SELECT * FROM pg_stat_database_conflicts;
```

## Related

- [Investigation Runbook](investigation-runbook.md)
- [Replication Slots](../05-replication-ha/replication-slots.md)
- [Slow Queries](slow-queries.md)
- [Corruption Recovery](corruption-recovery.md)
- [Logging](../07-monitoring/logging.md)
