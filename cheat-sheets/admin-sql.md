# Essential Admin SQL

> **PostgreSQL 18** — examples assume current major. See [VERSION.md](../VERSION.md).

## Cluster Info

```sql
SELECT version();
SHOW server_version_num;
SELECT pg_postmaster_start_time();
SELECT pg_is_in_recovery();
SELECT current_setting('data_directory');
SHOW config_file;
SHOW log_directory;
SHOW archive_mode;
SHOW archive_command;
SELECT * FROM pg_stat_archiver;
```

→ [Data Directory](../02-configuration/data-directory.md) · [Archive Mode](../02-configuration/backup-archive-directories.md) · [PITR](../04-backup-recovery/point-in-time-recovery.md)

## Sizes

```sql
-- Database sizes
SELECT datname, pg_size_pretty(pg_database_size(datname))
FROM pg_database ORDER BY pg_database_size(datname) DESC;

-- Table sizes (including indexes)
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;

-- Total cluster size
SELECT pg_size_pretty(sum(pg_database_size(datname))) FROM pg_database;
```

## Connections

```sql
SELECT count(*), state FROM pg_stat_activity GROUP BY state;

SELECT pid, usename, datname, client_addr, state, query_start,
       left(query, 100)
FROM pg_stat_activity
WHERE pid <> pg_backend_pid();
```

## Kill Sessions

```sql
SELECT pg_cancel_backend(pid);      -- cancel query
SELECT pg_terminate_backend(pid); -- terminate connection
```

## Replication

```sql
-- Primary
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Standby
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();

SELECT * FROM pg_replication_slots;
```

## Vacuum / Bloat

```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;

SELECT datname, age(datfrozenxid) FROM pg_database;
```

## Locks

```sql
SELECT locktype, relation::regclass, mode, granted, pid
FROM pg_locks WHERE NOT granted;

SELECT pg_blocking_pids(pid) FROM pg_stat_activity WHERE wait_event_type = 'Lock';
```

## Index Usage

```sql
SELECT relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
ORDER BY idx_scan;
```

## Cache Hit Ratio

```sql
SELECT sum(blks_hit)*100.0 / nullif(sum(blks_hit)+sum(blks_read),0) AS hit_pct
FROM pg_stat_database;
```

## Configuration

```sql
SELECT name, setting, unit, source, pending_restart
FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_connections');

ALTER SYSTEM SET log_min_duration_statement = 500;
SELECT pg_reload_conf();
```

## Roles

```sql
SELECT rolname, rolsuper, rolcanlogin, rolconnlimit FROM pg_roles;
\du+
```

## Maintenance

```sql
VACUUM (VERBOSE, ANALYZE) table_name;
REINDEX INDEX CONCURRENTLY index_name;
CHECKPOINT;
SELECT pg_switch_wal();
ANALYZE;
```

## Memory & Cache

```sql
-- Buffer hit ratio (target > 99% OLTP)
SELECT sum(blks_hit)*100.0 / nullif(sum(blks_hit)+sum(blks_read),0) AS hit_pct
FROM pg_stat_database;

-- Temp spills (raise work_mem if high)
SELECT query, temp_blks_written FROM pg_stat_statements
WHERE temp_blks_written > 0 ORDER BY temp_blks_written DESC LIMIT 5;

-- PG 18 shared memory
SHOW shared_memory_size;
SHOW shared_buffers;

-- Warm cache after restart (requires pg_prewarm extension)
-- SELECT pg_prewarm('hot_table');
```

## PG 18 Quick Checks

```sql
SELECT uuidv7();
SELECT * FROM pg_aios;
SHOW io_method;
SHOW data_checksums;   -- on by default for PG 18 initdb
SELECT * FROM pg_stat_io;

-- TLS session info (PG 18)
SELECT ssl, version, cipher, client_dn FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

## Backup Status

```sql
SELECT * FROM pg_stat_archiver;
SELECT pg_backup_start('label', true);  -- PG 18 backup API
```

## Useful pg_catalog One-Liners

```sql
-- Table OID / filenode
SELECT oid, relfilenode FROM pg_class WHERE relname = 'orders';

-- Active prepared transactions
SELECT * FROM pg_prepared_xacts;

-- Invalid indexes
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

## Related

- [Knowledge Base Index](../INDEX.md)
- [Cheat Sheets Index](README.md)
- [psql Complete Reference](psql-reference.md)
- [System Catalogs](../07-monitoring/system-catalogs.md)
- [Parameters Quick Reference](parameters-quick-ref.md)
