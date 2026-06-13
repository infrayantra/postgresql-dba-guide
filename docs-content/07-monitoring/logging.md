# Logging Configuration

> **Dedicated log path setup:** [Log Directory](../02-configuration/log-directory.md)

## Core Settings

```ini
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_truncate_on_rotation = off

log_line_prefix = '%m [%p] %u@%d %a %h %x '
# %m timestamp  %p pid  %u user  %d db  %a app  %h host  %x xid

log_timezone = 'UTC'
log_min_messages = warning
log_min_error_statement = error
```

## Query Logging

```ini
# Log queries exceeding duration (ms)
log_min_duration_statement = 500

# Log all statements (dev only — high volume)
# log_statement = 'all'    # none | ddl | mod | all

log_duration = off
log_statement_sample_rate = 1.0   # PG 14+ fraction of statements
```

Per-role override:

```sql
ALTER ROLE analyst SET log_min_duration_statement = 100;
```

## Connections & Auth

```ini
log_connections = on
log_disconnections = on
log_hostname = on
log_password_error = on   # PG 14+ — does not log password
```

## Locks & Deadlocks

```ini
log_lock_waits = on
deadlock_timeout = 1s     # time before checking deadlock
```

Deadlocks appear automatically in log.

## Checkpoints & Autovacuum

```ini
log_checkpoints = on
log_autovacuum_min_duration = 0   # log all autovacuum runs
```

## CSV Log for pgBadger

```ini
log_destination = 'csvlog'
logging_collector = on
```

```bash
pgbadger /var/lib/pgsql/18/data/log/postgresql-*.csv -o report.html
```

## JSON Logging (PG 15+)

```ini
log_destination = 'jsonlog'
```

Structured logs for ELK, Loki, CloudWatch.

## auto_explain

Log execution plans for slow queries:

```ini
shared_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '1s'
auto_explain.log_analyze = true
auto_explain.log_buffers = true
auto_explain.log_nested_statements = true
```

## Log Analysis Queries (from csvlog table — if loaded)

Or use external tools: pgBadger, pganalyze, Grafana Loki.

## What to Alert On

| Log pattern | Severity |
|-------------|----------|
| `PANIC` / `FATAL` | Critical |
| `ERROR: duplicate key` | App bug or retry storm |
| `deadlock detected` | Review transaction order |
| `canceling statement due to statement timeout` | Tune query or timeout |
| `out of memory` | Memory tuning |
| `could not write to file` | Disk full |
| `archive command failed` | Backup broken |

## Log Rotation (logrotate)

```
/var/lib/pgsql/18/data/log/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
    postrotate
        su postgres -c "pg_ctl -D /var/lib/pgsql/18/data reload"
    endscript
}
```

## Related

- [Log Directory](../02-configuration/log-directory.md)
- [postgresql.conf](../02-configuration/postgresql-conf.md)
- [pg_stat_statements](pg-stat-statements.md)
- [Troubleshooting](../11-troubleshooting/common-errors.md)
