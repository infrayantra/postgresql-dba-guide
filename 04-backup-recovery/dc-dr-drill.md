# DC / DR Drill Runbook

Structured disaster recovery exercises for PostgreSQL — validate backups, failover, and cross-site recovery before a real incident.

> **Goal:** Prove you can meet **RPO** (max acceptable data loss) and **RTO** (max acceptable downtime) documented in your DR plan.

---

## Definitions

| Term | Meaning | Example target |
|------|---------|----------------|
| **DC** (Data Center) | Primary production site | Region A, on-prem DC1 |
| **DR** (Disaster Recovery) | Secondary site for failover | Region B, on-prem DC2 |
| **RPO** | Recovery Point Objective — max data loss | 15 minutes |
| **RTO** | Recovery Time Objective — max downtime | 1 hour |
| **Drill** | Controlled test — no real disaster | Quarterly |

---

## Architecture Patterns

### Pattern A — Patroni HA (same DC)

3 nodes in one site; protects **node** failure, not **site** failure.

```
DC1: pg-node1 (leader) + pg-node2 + pg-node3 + etcd
DR:  cold standby OR logical replica OR backup restore target
```

**Drill focus:** Failover within DC; separate DR restore from backups.

### Pattern B — Cross-Region Streaming Replica

```
DC1 (primary) ──streaming replication──► DR (async standby)
```

**Drill focus:** Promote DR standby; repoint apps; rebuild DC1 later.

### Pattern C — Backup + WAL Archive (PITR)

```
DC1 (primary) ──archive_command──► S3/NFS (/Backup_PG)
DR: empty PG instance + pgBackRest/Barman restore
```

**Drill focus:** Restore to DR host at specific timestamp.

### Pattern D — Logical Replication to DR

```
DC1 (publisher) ──logical replication──► DR (subscriber, PG 18)
```

**Drill focus:** Cutover with minimal downtime; verify lag at switch.

---

## Drill Schedule

| Drill type | Frequency | Duration | Impact |
|------------|-----------|----------|--------|
| **Tabletop** | Quarterly | 1–2 hours | None — walkthrough only |
| **Backup restore test** | Monthly | 2–4 hours | None — isolated host |
| **PITR restore test** | Quarterly | 2–4 hours | None — isolated host |
| **Patroni failover** | Monthly | 15–30 min | Brief write pause if switchover |
| **Full DR failover** | Annually | 4–8 hours | Planned maintenance window |
| **Game day** | Annually | Full day | Simulated site loss |

---

## Pre-Drill Checklist

- [ ] DR plan document current (contacts, IPs, passwords in vault)
- [ ] Last successful backup verified (`pgBackRest info` / `pg_stat_archiver`)
- [ ] Replication lag baseline recorded
- [ ] Stakeholders notified (app team, management)
- [ ] Rollback procedure documented
- [ ] Isolated DR environment OR maintenance window approved
- [ ] Monitoring alerts snoozed or DR-specific dashboards ready

---

## Drill 1 — Backup Restore (Monthly)

**Objective:** Restore latest backup to an isolated server; verify data integrity.

### Steps

```bash
# 1. Provision DR test host (PG 18, same major as production)

# 2. Restore from pgBackRest
sudo -u postgres pgbackrest --stanza=main --delta restore

# Or from pg_basebackup archive:
# restore_command + recovery.signal

# 3. Start PostgreSQL
sudo systemctl start postgresql-18   # or patroni on DR test cluster

# 4. Verify
psql -c "SELECT version();"
psql -c "SELECT count(*) FROM critical_table;"
psql -c "SELECT max(updated_at) FROM orders;"   # compare to production
```

### Pass criteria

| Check | Expected |
|-------|----------|
| Cluster starts clean | No PANIC in logs |
| Row counts | Match production ± known lag |
| Application read test | Sample queries succeed |
| Time to restore | < documented RTO for backup-only scenario |

### Record

```
Drill date: ___________
Backup used: ___________
Restore duration: ___________
Data timestamp at restore: ___________
Issues found: ___________
```

---

## Drill 2 — Point-in-Time Recovery (Quarterly)

**Objective:** Restore to a **specific timestamp** before a simulated "bad DELETE".

### Setup (production — do NOT run destructive SQL on prod for drill; use staging)

```sql
-- On staging clone at T0
SELECT pg_create_restore_point('dr_drill_start');
-- Simulate oops: DELETE FROM orders WHERE created_at > '2025-01-01';
-- Note exact time: T_bad = 2026-06-14 10:15:32 UTC
```

### PITR restore on DR host

```bash
sudo systemctl stop postgresql-18
sudo -u postgres rm -rf /data/pgdata/*
sudo -u postgres pgbackrest --stanza=main --delta restore

# recovery.signal + postgresql.auto.conf
cat >> /data/pgdata/postgresql.auto.conf <<EOF
restore_command = 'pgbackrest --stanza=main archive-get %f %p'
recovery_target_time = '2026-06-14 10:15:00 UTC'
recovery_target_action = 'promote'
EOF
touch /data/pgdata/recovery.signal

sudo systemctl start postgresql-18
```

### Pass criteria

- Restored data exists **before** simulated bad transaction
- Bad DELETE rows **absent**
- Recovery completed within RPO window

---

## Drill 3 — Patroni Failover (Monthly)

**Objective:** Automatic or manual leader election; HAProxy routes correctly.

Reference: [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md) §14.7

```bash
# Planned switchover
patronictl -c /etc/patroni/patroni.yml switchover \
  --leader pg-node1 --candidate pg-node2 --force

patronictl list

# Application test via HAProxy
psql -h 10.0.1.11 -p 5000 -U postgres -c "SELECT pg_is_in_recovery();"
# Must return f

INSERT INTO ha_drill_log (event, at) VALUES ('failover_drill', now());
```

### Simulate hard failure

```bash
# On current leader — simulate crash (maintenance window only)
sudo systemctl stop patroni

# Watch promotion on another node (< 30–60s typical)
patronictl list
```

### Pass criteria

| Metric | Target |
|--------|--------|
| Detection + promotion | < 60 seconds |
| HAProxy routes to new leader | `pg_is_in_recovery()` = false |
| Data writable after failover | INSERT succeeds |
| Old leader rejoins as replica | `patronictl reinit` if needed |

---

## Drill 4 — Full DR Site Failover (Annual)

**Objective:** Production traffic runs from DR site; DC1 simulated as lost.

### Scenario

> DC1 (primary region) is unavailable. Activate DR region with last replicated data or backup.

### Option A — Promote DR streaming standby

```bash
# On DR standby
sudo -u postgres pg_ctl -D /data/pgdata promote
# or: patronictl failover on DR Patroni cluster

# Update DNS / HAProxy / connection strings to DR IPs
# Verify apps connect to DR endpoint
```

### Option B — Restore backup at DR + logical catch-up

If DR is behind, use logical replication cutover from surviving read replica in a third AZ.

### Cutover checklist

- [ ] Stop writes to DC1 (or confirm DC1 down)
- [ ] Promote DR / restore backup
- [ ] Update DNS (`db.example.com` → DR load balancer)
- [ ] Update connection pools (PgBouncer, app config)
- [ ] Sync sequences manually if logical replication used
- [ ] Re-enable backups from DR site
- [ ] Notify stakeholders — DR active

### Failback (DC1 recovery)

1. Rebuild DC1 as replica of DR (pg_basebackup or pgBackRest)
2. Verify replication lag = 0
3. Planned switchover back to DC1
4. Re-point DNS

---

## Drill 5 — Tabletop (Quarterly, no systems)

Walk through with team:

1. DC1 fire — who declares disaster?
2. Who promotes DR?
3. Who updates DNS and app configs?
4. Communication plan — status page, customers?
5. When is failback authorized?
6. Where are passwords / break-glass credentials?

Document gaps in runbooks.

---

## DR Drill Report Template

```markdown
# DR Drill Report — YYYY-MM-DD

## Summary
- Drill type: [ ] Backup restore [ ] PITR [ ] Patroni failover [ ] Full DR
- Result: PASS / FAIL / PARTIAL
- Participants: ...

## Metrics
| Metric | Target | Actual |
|--------|--------|--------|
| RPO | | |
| RTO | | |
| Failover time | | |
| Data loss (rows/time) | | |

## Issues found
1. ...
2. ...

## Action items
| Item | Owner | Due |
|------|-------|-----|
| | | |

## Sign-off
DBA: ______  Manager: ______
```

---

## Automation Hooks

```bash
#!/bin/bash
# dr-drill-restore-test.sh — run monthly via cron on DR test host
set -euo pipefail
STANZA=main
LOG=/var/log/pg-dr-drill-$(date +%F).log

{
  echo "=== DR drill start $(date) ==="
  pgbackrest --stanza=$STANZA info
  pgbackrest --stanza=$STANZA --delta restore
  systemctl start postgresql-18
  psql -c "SELECT version();"
  psql -d app_db -c "SELECT count(*) FROM orders;"
  echo "=== DR drill PASS $(date) ==="
} >> "$LOG" 2>&1
```

Alert if script exits non-zero (PagerDuty, email).

---

## Common Drill Failures

| Failure | Cause | Fix |
|---------|-------|-----|
| Restore fails — missing WAL | Archive gap | Fix `archive_command`; backfill WAL |
| Promoted standby diverged | Split-brain | Never write to two primaries; use fencing |
| HAProxy still on old leader | Health check wrong | Fix `/primary` check on Patroni 8008 |
| App can't connect after DR | DNS/TLS cert hostname | DR-specific cert or SAN |
| Sequences out of sync | Logical replication | `setval()` at cutover |
| pgBackRest stanza wrong on DR | Config not replicated | Maintain stanza config in git |

---

## Related

- [Physical Backup](physical-backup.md)
- [PITR](point-in-time-recovery.md)
- [pgBackRest](pg-backrest.md)
- [Failover](../05-replication-ha/failover.md)
- [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md)
