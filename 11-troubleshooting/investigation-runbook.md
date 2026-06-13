# Investigation Runbook — Where to Start

Systematic triage when something is wrong with **PostgreSQL 18**. Follow layers top-down; stop when root cause is found.

> **Queries:** [DBA Health Checks](../07-monitoring/dba-health-checks.md) · [Slow Queries](slow-queries.md) · [Common Errors](common-errors.md)

---

## Decision Flow

```
Alert / ticket
      │
      ▼
┌─────────────┐     No      ┌──────────────┐
│ pg_isready? │────────────►│ Logs + disk  │──► won't start → corruption-recovery
└──────┬──────┘             └──────────────┘
       │ Yes
       ▼
┌─────────────┐
│ Scope?      │
└──┬──┬──┬──┘
   │  │  │
   │  │  └── One query slow ──► slow-queries.md + EXPLAIN
   │  │
   │  └───── All queries slow ──► locks / disk / checkpoints / memory
   │
   └──────── App can't connect ──► connections / hba / pgbouncer / ssl
```

---

## Layer 1 — Infrastructure (2 min)

```bash
pg_isready -h $PGHOST -p $PGPORT
df -h $PGDATA /data/pgarchive /data/pglog 2>/dev/null
free -h
uptime
tail -50 /data/pglog/postgresql-$(date +%Y-%m-%d).log 2>/dev/null || tail -50 $PGDATA/log/*.log
```

| Finding | Next step |
|---------|-----------|
| Disk > 90% | [common-errors](common-errors.md) — WAL, slots, temp |
| OOM in dmesg | Reduce connections/work_mem; [in-memory](../06-performance/in-memory-features-integration.md) |
| PANIC in log | [corruption-recovery](corruption-recovery.md) |

---

## Layer 2 — Connections (5 min)

```sql
SELECT count(*), state, wait_event_type
FROM pg_stat_activity GROUP BY state, wait_event_type;

SELECT setting FROM pg_settings WHERE name = 'max_connections';
```

| Finding | Next step |
|---------|-----------|
| Near max_connections | PgBouncer; terminate idle; [connection pooling](../10-advanced/connection-pooling.md) |
| Many `idle in transaction` | App bug; `idle_in_transaction_session_timeout` |
| `active` + Lock wait | Layer 3 locks |
| `active` + IO/CPU | Layer 4 performance |

```sql
-- Emergency idle cleanup (change window)
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND state_change < now() - interval '10 minutes';
```

---

## Layer 3 — Locks & Blocking (5 min)

```sql
SELECT pid, usename, pg_blocking_pids(pid) AS blockers,
       wait_event_type, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

SELECT l.locktype, l.mode, l.granted, a.query
FROM pg_locks l JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted;
```

| Finding | Next step |
|---------|-----------|
| DDL blocking app | Wait or cancel DDL; schedule off-peak |
| Deadlock in log | Fix transaction order in app |
| Row lock storm | Long tx holding rows; [locking](../10-advanced/locking-concurrency.md) |

---

## Layer 4 — Performance (10 min)

```sql
-- Cache
SELECT datname, blks_hit, blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS hit_pct
FROM pg_stat_database WHERE datname = current_database();

-- Checkpoints
SELECT * FROM pg_stat_bgwriter;

-- Top queries
SELECT calls, mean_exec_time, total_exec_time, left(query, 100)
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

| Finding | Next step |
|---------|-----------|
| Low cache hit | shared_buffers, missing indexes, cold cache |
| checkpoints_req high | Increase max_wal_size |
| One query dominates | EXPLAIN ANALYZE; [indexing](../06-performance/indexing.md) |
| temp_blks_written high | Increase work_mem for role |

---

## Layer 5 — Replication & Archive (5 min)

```sql
SELECT * FROM pg_stat_replication;
SELECT * FROM pg_stat_archiver;
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
FROM pg_replication_slots;
```

| Finding | Next step |
|---------|-----------|
| No replicas connected | Network, HBA, replicator password |
| Lag growing | Load on primary; network; standby disk |
| archive failures | [backup-archive](../02-configuration/backup-archive-directories.md) |
| Inactive slot + WAL | [replication-slots](../05-replication-ha/replication-slots.md) |

---

## Layer 6 — Data Integrity

```sql
SELECT datname, age(datfrozenxid) FROM pg_database;
SELECT schemaname, relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;

SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
```

| Finding | Next step |
|---------|-----------|
| xid_age high | Force vacuum; [autovacuum](../09-maintenance/autovacuum.md) |
| Invalid index | REINDEX |
| Corruption error | [corruption-recovery](corruption-recovery.md) + PITR |

---

## Scenario Quick Links

| Scenario | Primary doc |
|----------|-------------|
| Accidental DELETE/DROP | [PITR](../04-backup-recovery/point-in-time-recovery.md) — temp restore |
| Failover needed | [Failover](../05-replication-ha/failover.md) |
| Upgrade failed | [Major upgrade](../09-maintenance/major-version-upgrade.md) |
| Security incident | [Auditing](../08-security/auditing.md); rotate passwords |
| Backup restore | [pgBackRest](../04-backup-recovery/pg-backrest.md) |

---

## Post-Investigation

1. Document root cause and fix
2. Add monitoring alert if missing ([health checks](../07-monitoring/dba-health-checks.md))
3. Update [DBA runbook](../09-maintenance/dba-runbook-checklists.md) if new pattern

---

## Related

- [Slow Query Investigation](slow-queries.md)
- [Common Errors & Fixes](common-errors.md)
- [Corruption Recovery](corruption-recovery.md)
- [DBA Health Checks](../07-monitoring/dba-health-checks.md)
