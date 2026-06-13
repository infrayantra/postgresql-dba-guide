# postgresql.conf — Main Configuration

> **Paths:** [Data Directory](data-directory.md) · [Backup & Archive](backup-archive-directories.md) · [Log Directory](log-directory.md) · [PITR](../04-backup-recovery/point-in-time-recovery.md)

> **PostgreSQL 18:** Defaults include checksums at initdb, new AIO settings (`io_method`), and MD5 deprecation. See [postgresql-18.md](../01-getting-started/postgresql-18.md) and [VERSION.md](../VERSION.md).

## File Location & Reload

```sql
SHOW config_file;
SHOW data_directory;
```

```bash
# Reload without dropping connections (most GUCs)
pg_ctl reload -D $PGDATA
# or
SELECT pg_reload_conf();

# Restart required for:
# shared_buffers, max_connections, wal_level, shared_preload_libraries, etc.
SELECT name, context FROM pg_settings WHERE context = 'postmaster';
```

## Configuration Includes (PG 12+)

```ini
# postgresql.conf
include_dir = 'conf.d'
```

Place overrides in `$PGDATA/conf.d/*.conf` for modular management.

---

## Connection & Authentication

```ini
listen_addresses = '*'          # or specific IPs; default 'localhost'
port = 5432
max_connections = 200           # balance with PgBouncer if higher needed
superuser_reserved_connections = 3

# SSL
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_min_protocol_version = 'TLSv1.2'
```

---

## Memory

```ini
# Primary cache — 25% RAM typical on dedicated DB server
shared_buffers = 4GB

# Planner hint only (not allocated)
effective_cache_size = 12GB

# Per-operation memory (multiply by concurrent sorts!)
work_mem = 64MB                 # 64MB × 100 sorts = 6.4GB possible

# VACUUM, CREATE INDEX, ALTER TABLE ADD FK
maintenance_work_mem = 1GB

# Temp tables per session
temp_buffers = 32MB

# WAL buffer (-1 = auto, 1/32 of shared_buffers)
wal_buffers = 64MB
```

**Sizing work_mem:**

```
safe_work_mem = (RAM - shared_buffers) / (max_connections × 2)
```

---

## WAL & Durability

```ini
wal_level = replica           # minimal | replica | logical
max_wal_size = 4GB            # triggers checkpoint
min_wal_size = 1GB
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min

# Durability vs performance
synchronous_commit = on       # off/local/remote_apply for async
full_page_writes = on         # disable only with care + filesystem snapshots
wal_compression = on          # PG 15+ lz4/zstd options

# Archiving (PITR) — see backup-archive-directories.md for full setup
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
# Filesystem: 'test ! -f /data/pgarchive/%f && cp %p /data/pgarchive/%f'
```

---

## Replication Settings

```ini
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB             # was wal_keep_segments pre-PG 13
hot_standby = on                # on standby
hot_standby_feedback = on       # reduces primary query conflicts
max_standby_streaming_delay = 30s
```

---

## Query Planner

```ini
random_page_cost = 1.1          # SSD default; 4.0 for HDD
effective_io_concurrency = 200  # SSD/NVMe
seq_page_cost = 1.0
default_statistics_target = 100 # higher = better plans, slower ANALYZE

# Parallelism (PG 10+)
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_worker_processes = 8
parallel_setup_cost = 100
parallel_tuple_cost = 0.01
```

---

## Autovacuum

```ini
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 30s
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.05
autovacuum_vacuum_cost_delay = 2ms
autovacuum_vacuum_cost_limit = 1000

# Anti-wraparound urgency
autovacuum_freeze_max_age = 200000000
```

---

## Asynchronous I/O — PG 18+

```ini
io_method = worker              # none | worker | io_uring (Linux, if supported)
io_combine_limit = 128kB
io_max_combine_limit = 1MB
```

Improves sequential scans, bitmap heap scans, and VACUUM. Monitor with `SELECT * FROM pg_aios;`.

See [PostgreSQL 18 Reference](../01-getting-started/postgresql-18.md).

---

## Logging

```ini
logging_collector = on
log_directory = '/data/pglog'    # absolute path recommended; see log-directory.md
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_timezone = 'UTC'

log_connections = on
log_disconnections = on
log_duration = off
log_min_duration_statement = 1000   # ms; log slow queries
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0                  # log all temp file usage
log_autovacuum_min_duration = 0

# CSV logs for pgBadger
log_destination = 'csvlog'
```

---

## Extensions (shared_preload_libraries)

```ini
shared_preload_libraries = 'pg_stat_statements,auto_explain'
```

Requires **restart**. Then in SQL:

```sql
CREATE EXTENSION pg_stat_statements;
```

---

## Locale & Formatting

```ini
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
```

---

## Alter Settings at Runtime

```sql
-- Session
SET work_mem = '256MB';

-- Role
ALTER ROLE app_user SET work_mem = '32MB';

-- Database
ALTER DATABASE app_db SET log_min_duration_statement = 500;

-- View all
SELECT name, setting, unit, source, context
FROM pg_settings
WHERE name LIKE '%work_mem%';
```

---

## Production Template (8 GB RAM, SSD, OLTP)

```ini
shared_buffers = 2GB
effective_cache_size = 6GB
work_mem = 32MB
maintenance_work_mem = 512MB
max_connections = 100
wal_level = replica
max_wal_size = 4GB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200
log_min_duration_statement = 500
shared_preload_libraries = 'pg_stat_statements'
```

Scale proportionally for larger instances.

## Related

- [Knowledge Base Index](../INDEX.md)
- [Data Directory](data-directory.md)
- [Backup & Archive Directories](backup-archive-directories.md)
- [Log Directory](log-directory.md)
- [Parameters Quick Reference](../cheat-sheets/parameters-quick-ref.md)
- [Tuning Parameters](../06-performance/tuning-parameters.md)
- [pg_hba.conf](pg-hba-conf.md)
