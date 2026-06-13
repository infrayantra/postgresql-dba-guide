# Log Directory — Setup & Configuration

PostgreSQL logs connection events, errors, slow queries, checkpoints, and autovacuum activity. This guide covers **setting a dedicated log directory** on **PostgreSQL 18**.

> Deep logging options: [Logging Configuration](../07-monitoring/logging.md) · [postgresql.conf](postgresql-conf.md)

---

## Default vs Dedicated Log Path

| Mode | `log_directory` | Actual path |
|------|-----------------|-------------|
| Default (relative) | `'log'` | `$PGDATA/log/` |
| Dedicated (absolute) | `'/data/pglog'` | `/data/pglog/` |
| CSV / JSON | same directory | `postgresql-*.csv` or `.json` |

**Production recommendation:** absolute path on separate disk or volume from PGDATA.

---

## Create Log Directory

```bash
sudo mkdir -p /data/pglog
sudo chown postgres:postgres /data/pglog
sudo chmod 750 /data/pglog
```

---

## postgresql.conf Settings

```ini
# Enable log collector (required for file logging)
logging_collector = on

# Dedicated directory (absolute path)
log_directory = '/data/pglog'

# File naming
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_truncate_on_rotation = off

# Line format (production)
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_timezone = 'UTC'

# What to log
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_min_duration_statement = 1000    # ms — slow queries

# Severity
log_min_messages = warning
log_min_error_statement = error
```

Apply:

```bash
# logging_collector change requires RESTART
sudo systemctl restart postgresql-18

# Most other log settings: reload
sudo -u postgres psql -c "SELECT pg_reload_conf();"
```

---

## Verify Log Directory

```sql
SHOW logging_collector;
SHOW log_directory;
SHOW log_filename;
SHOW log_destination;
```

```bash
# After restart, logs appear in new directory
ls -la /data/pglog/
tail -f /data/pglog/postgresql-*.log

# Confirm not writing to old location
ls -la /var/lib/pgsql/18/data/log/ 2>/dev/null || true
```

```bash
# Generate test log entry
sudo -u postgres psql -c "SELECT 1;"
grep "SELECT 1" /data/pglog/postgresql-*.log
```

---

## Change Log Directory on Running Cluster

1. Create new directory (ownership `postgres`)
2. Update `log_directory` in `postgresql.conf`
3. **Restart** PostgreSQL (`logging_collector` reads path at start)
4. Optionally archive old logs from `$PGDATA/log/`

```bash
sudo systemctl stop postgresql-18
# Edit postgresql.conf: log_directory = '/data/pglog'
sudo systemctl start postgresql-18
```

No need to move PGDATA — only log output path changes.

---

## CSV Log (pgBadger)

```ini
logging_collector = on
log_directory = '/data/pglog'
log_destination = 'csvlog'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
```

```bash
pgbadger /data/pglog/postgresql-*.csv -o /tmp/pgreport.html
```

---

## JSON Log (PG 15+, ELK/Loki)

```ini
log_destination = 'jsonlog'
log_directory = '/data/pglog'
logging_collector = on
```

Ship with Filebeat, Fluent Bit, or Promtail to centralized logging.

---

## syslog Instead of Files

```ini
logging_collector = off
log_destination = 'syslog'
syslog_facility = 'LOCAL0'
syslog_ident = 'postgres'
```

```bash
# rsyslog
echo 'local0.*    /var/log/postgresql/postgresql-18.log' >> /etc/rsyslog.d/postgresql.conf
systemctl restart rsyslog
```

---

## Patroni / HA

```yaml
postgresql:
  parameters:
    logging_collector: 'on'
    log_directory: /data/pglog
    log_filename: postgresql-%Y-%m-%d.log
    log_rotation_age: 1d
    log_min_duration_statement: 1000
```

Ensure `/data/pglog` exists on **every** node with same ownership.

---

## Log Rotation

### Built-in (logging_collector)

```ini
log_rotation_age = 1d
log_rotation_size = 100MB
log_truncate_on_rotation = off
```

### logrotate (supplement)

```
/data/pglog/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        su postgres -c "/usr/pgsql-18/bin/pg_ctl -D /data/pgdata/18 reload"
    endscript
}
```

**Do not** delete active log file without reload — use `copytruncate` or PostgreSQL rotation only.

---

## Docker

```yaml
environment:
  POSTGRES_INITDB_ARGS: "--data-checksums"
command: >
  postgres
  -c logging_collector=on
  -c log_directory=/var/log/postgresql
  -c log_filename=postgresql.log
volumes:
  - pglogs:/var/log/postgresql
```

---

## Disk Space Monitoring

```bash
du -sh /data/pglog
df -h /data/pglog

# Alert if > 80% full — long queries + log_statement=all can fill disk quickly
```

| Setting | Volume impact |
|---------|---------------|
| `log_statement = all` | Very high |
| `log_min_duration_statement = 0` | High |
| `log_min_duration_statement = 1000` | Moderate |
| Default warnings only | Low |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No log files created | `logging_collector = on`; restart required |
| Permission denied | `chown postgres:postgres /data/pglog` |
| Logs still in PGDATA/log | Relative path used; set absolute `log_directory` |
| Empty logs | Check `log_min_messages`; test with `log_statement=ddl` temporarily |
| Duplicate logs | Both csvlog and stderr enabled — pick one destination |

---

## Related

- [Logging Configuration](../07-monitoring/logging.md)
- [postgresql.conf](postgresql-conf.md)
- [Data Directory](data-directory.md)
- [Archive Mode](backup-archive-directories.md)
