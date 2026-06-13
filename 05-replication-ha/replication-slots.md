# Replication Slots — Management & Troubleshooting

**Replication slots** guarantee WAL retention for standbys, logical subscribers, and backup tools. Misconfigured slots are a **top cause of disk full** on PostgreSQL primaries.

> **PostgreSQL 18** — physical and logical slots. See [Streaming Replication](streaming-replication.md) · [Logical Replication](logical-replication.md)

---

## Slot Types

| Type | Created by | Purpose |
|------|------------|---------|
| **Physical** | `pg_create_physical_replication_slot`, pg_basebackup `-S`, Patroni | Streaming standby WAL stream |
| **Logical** | `pg_create_logical_replication_slot`, SUBSCRIPTION | Logical decoding / CDC |

---

## View All Slots

```sql
SELECT slot_name, slot_type, active, temporary, database,
       restart_lsn, confirmed_flush_lsn,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC NULLS LAST;
```

| Column | Meaning |
|--------|---------|
| `active` | Consumer currently connected |
| `temporary` | Dropped when session ends (pg_basebackup `-C`) |
| `restart_lsn` | Earliest WAL still needed |
| `confirmed_flush_lsn` | Logical: last confirmed by consumer |

---

## Create Physical Slot

```sql
SELECT pg_create_physical_replication_slot('standby1');
-- Idempotent PG 17+:
SELECT pg_create_physical_replication_slot('standby1', true, false);
```

Use with standby:

```ini
primary_slot_name = 'standby1'
```

Or pg_basebackup:

```bash
pg_basebackup ... -S standby1
# Temporary slot during backup:
pg_basebackup ... -C -S tmp_backup_slot
```

---

## Create Logical Slot

```sql
SELECT pg_create_logical_replication_slot('app_sub_slot', 'pgoutput');
```

Usually created automatically by `CREATE SUBSCRIPTION ... WITH (create_slot = true)`.

---

## Drop Slot (Free WAL)

```sql
-- Confirm inactive and consumer gone
SELECT * FROM pg_replication_slots WHERE slot_name = 'old_standby';

SELECT pg_drop_replication_slot('old_standby');
```

**Warning:** Dropping an active slot breaks the connected replica/subscriber.

---

## Inactive Slot — Disk Fill Scenario

```
Symptom: pg_wal/ growing, disk full, archive OK
Cause:   inactive slot with old restart_lsn — WAL cannot be recycled
```

```sql
-- Find culprit
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_held
FROM pg_replication_slots
WHERE NOT active AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 1073741824;
```

**Fix:**

1. If replica abandoned → `pg_drop_replication_slot`
2. If replica should exist → rebuild standby or fix connectivity
3. Never delete WAL files manually while slots exist

---

## max_slot_wal_keep_size (PG 13+)

Limits WAL retained for inactive slots — slot becomes invalid if exceeded.

```ini
max_slot_wal_keep_size = 4GB   # or -1 unlimited (default pre-PG 13 behavior via wal_keep)
```

Monitor invalidation:

```sql
SELECT slot_name, active, invalidation_reason
FROM pg_replication_slots;   -- PG 17+ invalidation_reason
```

After invalidation, replica needs **rebuild** (pg_basebackup / pgBackRest).

---

## Patroni Slots

Patroni creates and manages `patroni` slots on replicas. Do not drop manually during normal operation.

```bash
patronictl list
patronictl show-config
```

---

## Logical Slot Lag

```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

High lag → subscriber down or slow; WAL accumulates on primary.

**Fix:** Start subscriber, or drop subscription/slot if abandoned.

---

## Monitoring Alerts

| Condition | Severity |
|-----------|----------|
| Inactive slot + retained > 1 GB | Warning |
| Inactive slot + retained > 10 GB | Critical |
| Logical lag > 1 GB | Warning |
| Slot count near `max_replication_slots` | Warning |

```sql
SHOW max_replication_slots;
SELECT count(*) FROM pg_replication_slots;
```

---

## Best Practices

- [ ] One permanent physical slot per standby
- [ ] Name slots clearly (`standby1`, `dc2_dr`, not `slot1`)
- [ ] Drop slots when decommissioning replicas
- [ ] Monitor weekly in [DBA checklist](../09-maintenance/dba-runbook-checklists.md)
- [ ] Set `max_slot_wal_keep_size` to bound runaway retention
- [ ] Document slots in infrastructure inventory

---

## Related

- [Streaming Replication](streaming-replication.md)
- [Logical Replication](logical-replication.md)
- [pg_basebackup](../04-backup-recovery/pg-basebackup.md)
- [DBA Health Checks](../07-monitoring/dba-health-checks.md)
- [Common Errors — disk full](../11-troubleshooting/common-errors.md)
