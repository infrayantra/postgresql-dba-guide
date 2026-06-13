# Parameters Quick Reference

> **PostgreSQL 18** production defaults. Full detail: [postgresql.conf](../02-configuration/postgresql-conf.md) · [VERSION.md](../VERSION.md).

## Paths & Logging

| Parameter | Example | Notes |
|-----------|---------|-------|
| `data_directory` | `/data/pgdata/18` | Set at init; see [data-directory](../02-configuration/data-directory.md) |
| `log_directory` | `/data/pglog` | Requires `logging_collector=on` + restart |
| `archive_command` | `pgbackrest ... %p` | `%p` path, `%f` filename |

## Memory

| Parameter | Default | Recommended | Restart? |
|-----------|---------|-------------|----------|
| shared_buffers | 128MB | 25% RAM | Yes |
| effective_cache_size | 4GB | 50-75% RAM | No |
| work_mem | 4MB | Calculated | No |
| maintenance_work_mem | 64MB | 5-10% RAM | No |
| temp_buffers | 8MB | 8-32MB | No |
| wal_buffers | -1 (auto) | auto or 64MB | Yes |

## Connections

| Parameter | Default | Notes |
|-----------|---------|-------|
| max_connections | 100 | Use PgBouncer above ~200-300 |
| superuser_reserved_connections | 3 | Emergency admin access |

## WAL & Checkpoint

| Parameter | Default | Production |
|-----------|---------|------------|
| wal_level | replica | replica or logical |
| max_wal_size | 1GB | 4-8GB |
| min_wal_size | 80MB | 1-2GB |
| checkpoint_completion_target | 0.9 | 0.9 |
| checkpoint_timeout | 5min | 15min |
| archive_mode | off | on (for PITR) — see [backup-archive-directories](../02-configuration/backup-archive-directories.md) |
| synchronous_commit | on | on (or remote_* for sync rep) |

## Replication

| Parameter | Default | Notes |
|-----------|---------|-------|
| max_wal_senders | 10 | ≥ number of standbys |
| max_replication_slots | 10 | Monitor inactive slots |
| wal_keep_size | 0 | Set if no archive |
| hot_standby | on | Standby only |
| hot_standby_feedback | off | on to reduce conflicts |

## Planner (SSD)

| Parameter | HDD | SSD |
|-----------|-----|-----|
| random_page_cost | 4.0 | 1.1 |
| effective_io_concurrency | 1 | 200 |
| default_statistics_target | 100 | 100-500 |

## Parallelism

| Parameter | Default |
|-----------|---------|
| max_worker_processes | 8 |
| max_parallel_workers | 8 |
| max_parallel_workers_per_gather | 2 |
| max_parallel_maintenance_workers | 2 |

## Autovacuum

| Parameter | Default | Hot tables |
|-----------|---------|------------|
| autovacuum | on | on |
| autovacuum_max_workers | 3 | 4-6 |
| autovacuum_naptime | 1min | 10-30s |
| autovacuum_vacuum_scale_factor | 0.2 | 0.01-0.05 |
| autovacuum_analyze_scale_factor | 0.1 | 0.02-0.05 |

## Logging

| Parameter | Production suggestion |
|-----------|----------------------|
| log_min_duration_statement | 500-1000 ms |
| log_checkpoints | on |
| log_connections | on |
| log_lock_waits | on |
| log_autovacuum_min_duration | 0 or 1000ms |
| log_line_prefix | `%m [%p] %u@%d %a %h ` |

## Timeouts

| Parameter | Suggested |
|-----------|-----------|
| statement_timeout | 30s-5min (role-specific) |
| lock_timeout | 5-30s |
| idle_in_transaction_session_timeout | 5-15min |
| deadlock_timeout | 1s |

## PG 18 — Memory & AIO

| Parameter | Purpose |
|-----------|---------|
| `shared_memory_size` | Total shared memory (read-only, PG 18) |
| `shared_memory_size_in_huge_pages` | Huge pages used |
| `io_method` | Async I/O: `worker`, `io_uring`, `none` |

Monitor: `SELECT * FROM pg_aios;` · `pg_buffercache` · `pg_stat_database` hit ratio

## PG 18 — Asynchronous I/O

| Parameter | Default | Notes |
|-----------|---------|-------|
| `io_method` | `worker` | `none`, `worker`, `io_uring` (Linux) |
| `io_combine_limit` | 128kB | Merge adjacent read requests |
| `io_max_combine_limit` | 1MB | Max combined I/O size |

Monitor: `SELECT * FROM pg_aios;`

## Optimizer (PG 18)

| Parameter | Purpose |
|-----------|---------|
| `enable_self_join_elimination` | Auto remove redundant self-joins |
| `enable_distinct_reordering` | Reorder DISTINCT keys to avoid sorts |
| `md5_password_warnings` | Warn on MD5 password use (PG 18) |

## Context Legend

| context | Reload behavior |
|---------|-----------------|
| postmaster | Restart required |
| sighup | pg_reload_conf() |
| superuser | SET by superuser |
| user | SET by any user |

```sql
SELECT name, setting, unit, context, short_desc
FROM pg_settings
WHERE name = 'work_mem';
```

## Related

- [Knowledge Base Index](../INDEX.md)
- [Cheat Sheets Index](README.md)
- [postgresql.conf](../02-configuration/postgresql-conf.md)
- [Data Directory](../02-configuration/data-directory.md)
- [Backup & Archive](../02-configuration/backup-archive-directories.md)
- [Log Directory](../02-configuration/log-directory.md)
- [PITR](../04-backup-recovery/point-in-time-recovery.md)
- [Tuning Parameters](../06-performance/tuning-parameters.md)
- [pgbench](../06-performance/pgbench.md)
