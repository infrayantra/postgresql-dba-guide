# DBA Runbook — Daily, Weekly & Monthly Checklists

Operational tasks for **PostgreSQL 18** production clusters. Adjust frequency to your SLA and automation level.

> **Queries:** [DBA Health Checks](../07-monitoring/dba-health-checks.md) · **DR:** [DC/DR Drill](../04-backup-recovery/dc-dr-drill.md)

---

## Daily (5–15 min, or automated)

| Task | Action |
|------|--------|
| Cluster up | `pg_isready`; alert on failure |
| Archive health | `SELECT * FROM pg_stat_archiver` — `failed_count = 0` |
| Replication lag | `pg_stat_replication` — lag within SLA |
| Disk space | `df -h` on PGDATA, archive, logs, backup repo |
| Connections | Not near `max_connections`; check idle-in-transaction |
| Error logs | Scan `/data/pglog` for `PANIC`, `FATAL`, `archive command failed` |
| Blocking | No long block chains (`pg_blocking_pids`) |

```bash
# One-liner daily cron
pg_isready && psql -X -c "SELECT failed_count FROM pg_stat_archiver;" \
  && df -h /data/pgdata | tail -1
```

---

## Weekly (30–60 min)

| Task | Action |
|------|--------|
| Backup verify | `pgbackrest --stanza=main info` — full age within policy |
| pgBackRest check | `pgbackrest --stanza=main check` |
| Database growth | Record `pg_database_size`; trend vs capacity plan |
| Top slow queries | Review `pg_stat_statements` top 10 by total time |
| Dead tuples | Tables with high `n_dead_tup`; autovacuum keeping up |
| Replication slots | Inactive slots retaining WAL — drop or activate |
| Unused indexes | `idx_scan = 0` on large indexes — review |
| Certificate expiry | TLS cert on server and clients if applicable |
| PgBouncer | `SHOW POOLS; SHOW STATS` — wait time, cl_waiting |

```sql
-- Reset pg_stat_statements weekly after review (optional)
SELECT pg_stat_statements_reset();
```

---

## Monthly (2–4 hours)

| Task | Action |
|------|--------|
| **PITR drill** | Restore to isolated host with `recovery_target_time` — document RTO |
| **Failover drill** | Patroni switchover or manual promote on standby (change window) |
| Index bloat review | `pgstattuple` on largest tables |
| Vacuum/analyze stats | Tables never autovacuumed; adjust autovacuum per-table if needed |
| Role audit | Superusers, unused roles, password MD5 → SCRAM migration |
| Config review | `pg_settings` where `source != default` — document drift |
| Capacity forecast | Update growth spreadsheet; order disk if > 70% in 90 days |
| Patch level | PG minor release; OS security patches |
| pgBackRest full | Ensure full backup in retention window |
| Compliance | Export audit logs; backup encryption key rotation check |

---

## Quarterly

| Task | Action |
|------|--------|
| Full DR drill | [DC/DR Runbook](../04-backup-recovery/dc-dr-drill.md) — restore at DR site |
| HA runbook refresh | Update IPs, passwords vault refs, contact list |
| Major upgrade planning | Review [version history](../01-getting-started/version-history.md) EOL |
| Disaster scenario table-top | Walk through corruption, region loss, ransomware |
| Performance baseline | `pgbench` or app load test; store TPS/latency |

---

## After-Incident Checklist

| Step | Action |
|------|--------|
| 1 | Root cause documented |
| 2 | Timeline of WAL/archive/replication state |
| 3 | Data loss quantified (RPO actual) |
| 4 | Restore method noted (PITR time, pgBackRest, logical) |
| 5 | Preventive action (monitoring alert, config change) |
| 6 | Update runbook |

---

## New Deployment Sign-Off

Use [Production Cluster Layout](production-cluster-layout.md) sign-off checklist before go-live.

---

## Change Window Template

```markdown
## Change: _______________
Date/Time: _______________
Cluster: _______________

Pre-checks:
- [ ] Backup completed (pgbackrest info)
- [ ] Replication lag 0
- [ ] Rollback plan documented

Change steps:
1.
2.

Post-checks:
- [ ] pg_isready
- [ ] pg_stat_archiver failed_count = 0
- [ ] Application smoke test
- [ ] Monitor 30 min

Rollback:
1.
```

---

## On-Call Quick Escalation

| Symptom | First action | Doc |
|---------|--------------|-----|
| Disk full | Free WAL if slot lag; extend volume | [common-errors](../11-troubleshooting/common-errors.md) |
| Archive failing | Fix archive_command; check disk/S3 | [backup-archive](../02-configuration/backup-archive-directories.md) |
| Replication broken | Check HBA, replicator password, network | [streaming-replication](../05-replication-ha/streaming-replication.md) |
| DB won't start | Logs in pglog; `pg_ctl start` verbose | [corruption-recovery](../11-troubleshooting/corruption-recovery.md) |
| Slow everything | Locks, checkpoints, disk I/O | [slow-queries](../11-troubleshooting/slow-queries.md) |
| Need data back | **Don't** overwrite prod — PITR to temp | [PITR](../04-backup-recovery/point-in-time-recovery.md) |

---

## Related

- [Production Cluster Layout](../03-administration/production-cluster-layout.md)
- [DBA Health Checks](../07-monitoring/dba-health-checks.md)
- [Capacity Planning](../03-administration/capacity-planning.md)
- [Investigation Runbook](../11-troubleshooting/investigation-runbook.md)
