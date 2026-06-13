# DBA Health Checks & Monitoring Queries

Copy-paste SQL and shell checks for **daily automation** or **on-call** triage on **PostgreSQL 18**.

> Alerts wiring: [Metrics Exporters](metrics-exporters.md) · **Checklists:** [DBA Runbook](../09-maintenance/dba-runbook-checklists.md)

---

## Quick Status (30 seconds)

```sql
SELECT version();
SELECT pg_is_in_recovery() AS standby,
       pg_postmaster_start_time(),
       current_setting('cluster_name') AS cluster;
SELECT count(*) AS connections,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE wait_event IS NOT NULL) AS waiting
FROM pg_stat_activity
WHERE pid <> pg_backend_pid();
```

```bash
pg_isready -h localhost -p 5432
df -h /data/pgdata /data/pgarchive /data/pglog 2>/dev/null
sudo -u postgres pgbackrest --stanza=main check 2>/dev/null || true
```

---

## 1. Availability & Recovery

```sql
-- Standby lag (on primary)
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_lag
FROM pg_stat_replication;

-- Standby perspective
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp(),
       now() - pg_last_xact_replay_timestamp() AS replay_delay;
```

**Alert if:** replay delay > SLA (e.g. 60s) or lag bytes growing unbounded.

---

## 2. WAL Archive (PITR readiness)

```sql
SELECT archived_count, failed_count,
       last_archived_wal, last_archived_time,
       last_failed_wal, last_failed_time
FROM pg_stat_archiver;
```

**Alert if:** `failed_count` > 0 or `last_archived_time` stale > 15 min on busy system.

```bash
pgbackrest --stanza=main info | grep -E 'full backup|status'
```

---

## 3. Replication Slots

```sql
SELECT slot_name, slot_type, active, temporary,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_wal_bytes,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots
ORDER BY retained_wal_bytes DESC NULLS LAST;
```

**Alert if:** inactive slot with retained WAL > 1 GB (disk fill risk).

See [Replication Slots](../05-replication-ha/replication-slots.md).

---

## 4. Disk & Database Size

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database ORDER BY pg_database_size(datname) DESC;

SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total,
       pg_size_pretty(pg_relation_size(relid)) AS heap
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;
```

```bash
df -h | awk '$5+0 > 80 {print}'   # filesystems > 80%
du -sh $PGDATA/pg_wal
```

---

## 5. Connections & Locks

```sql
SELECT datname, usename, state, wait_event_type, wait_event,
       now() - state_change AS state_age,
       left(query, 100) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY state_change;

-- Blockers
SELECT blocked.pid AS blocked_pid,
       blocking.pid AS blocking_pid,
       left(blocked.query, 60) AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- Lock count
SELECT mode, count(*) FROM pg_locks GROUP BY mode ORDER BY count DESC;
```

**Alert if:** connections > 80% `max_connections`; long `idle in transaction` > 5 min.

---

## 6. Vacuum & Bloat

```sql
SELECT schemaname, relname, n_dead_tup, n_live_tup,
       last_vacuum, last_autovacuum, last_analyze,
       round(n_dead_tup * 100.0 / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC LIMIT 15;

-- XID wraparound risk
SELECT datname, age(datfrozenxid) AS xid_age,
       current_setting('autovacuum_freeze_max_age')::bigint AS max_age
FROM pg_database ORDER BY age(datfrozenxid) DESC;
```

**Alert if:** `xid_age` > 200M (investigate); > 1.5B critical.

---

## 7. Performance — Cache & I/O

```sql
SELECT datname,
       round(blks_hit * 100.0 / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct
FROM pg_stat_database WHERE datname NOT LIKE 'template%';

SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint,
       buffers_clean, maxwritten_clean, checkpoint_write_time
FROM pg_stat_bgwriter;
```

**Alert if:** cache hit < 95% on OLTP (after warmup); `checkpoints_req` dominating.

```sql
-- PG 18 AIO
SELECT * FROM pg_aios;
SELECT * FROM pg_stat_io LIMIT 20;
```

---

## 8. Slow Queries (pg_stat_statements)

```sql
SELECT calls, round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows, left(query, 120) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 15;

SELECT calls, temp_blks_written, left(query, 100)
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC LIMIT 10;
```

---

## 9. Invalid & Unused Indexes

```sql
SELECT indexrelid::regclass AS index, indisvalid, indisready
FROM pg_index WHERE NOT indisvalid;

SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexrelname NOT LIKE 'pg_toast%'
ORDER BY pg_relation_size(indexrelid) DESC LIMIT 15;
```

---

## 10. Security Spot Checks

```sql
SELECT rolname, rolsuper, rolcreatedb, rolreplication, rolcreaterole
FROM pg_roles WHERE rolsuper AND rolname NOT LIKE 'pg_%';

SHOW password_encryption;
SELECT rolname, rolpassword LIKE 'md5%' AS is_md5 FROM pg_authid WHERE rolcanlogin;
```

---

## Health Report Script

```bash
#!/bin/bash
# /usr/local/bin/pg-health.sh
OUT=/var/log/pg-health-$(date +%Y%m%d).log
{
  echo "=== $(date) ==="
  pg_isready
  psql -X -c "SELECT version();"
  psql -X -c "SELECT * FROM pg_stat_archiver;"
  psql -X -c "SELECT * FROM pg_stat_replication;"
  psql -X -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) FROM pg_replication_slots;"
  psql -X -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
  df -h /data/pgdata /data/pgarchive 2>/dev/null
  pgbackrest --stanza=main info 2>/dev/null | head -20
} >> "$OUT" 2>&1
```

Cron: `0 */6 * * * postgres /usr/local/bin/pg-health.sh`

---

## Alert Threshold Summary

| Metric | Warning | Critical |
|--------|---------|----------|
| Disk usage | 80% | 90% |
| Replication lag | > 30s | > 5 min |
| Archive failures | any in 1h | sustained |
| Connections | 80% max | 95% max |
| Cache hit (OLTP) | < 97% | < 90% |
| xid_age | > 200M | > 1B |
| Slot retained WAL | > 500 MB | > 5 GB |
| Last full backup | > 8 days | > 14 days |

---

## Related

- [DBA Runbook Checklists](../09-maintenance/dba-runbook-checklists.md)
- [pg_stat_statements](pg-stat-statements.md)
- [Slow Query Investigation](../11-troubleshooting/slow-queries.md)
- [System Catalogs](system-catalogs.md)
