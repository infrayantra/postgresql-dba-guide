# Logical vs Physical — Replication & Backup

PostgreSQL offers **two fundamentally different approaches** to copying and synchronizing data. **Physical** methods copy bytes (data files + WAL). **Logical** methods copy **decoding changes** (SQL rows, DDL as objects via dump).

This guide helps DBAs choose the right tool for **HA**, **DR**, **backups**, and **upgrades** on **PostgreSQL 18**.

> Deep dives: [Physical Backup](04-backup-recovery/physical-backup.md) · [Logical Backup](04-backup-recovery/logical-backup.md) · [Streaming Replication](05-replication-ha/streaming-replication.md) · [Logical Replication](05-replication-ha/logical-replication.md)

---

## At a Glance

```
PHYSICAL                          LOGICAL
────────                          ───────
Copy disk blocks / WAL bytes      Decode WAL → row changes OR export SQL
Entire cluster                    Selected DBs / tables / objects
Same major version (typical)      Cross-major often supported
Fast for large DBs                Slower for multi-TB full dumps
PITR with WAL archive             Point-in-time via dump timestamp only*
Standby read-only (streaming)     Subscriber can be writable

* Logical backup has no native PITR; combine with WAL logical decoding or use physical PITR + pg_dump extract.
```

---

## Terminology

| Term | Layer | Examples |
|------|-------|----------|
| **Physical backup** | File/block | `pg_basebackup`, pgBackRest, filesystem snapshot |
| **Logical backup** | Object/SQL | `pg_dump`, `pg_dumpall`, `pg_restore` |
| **Physical replication** | WAL streaming | Streaming replication, standby, Patroni HA |
| **Logical replication** | Row changes | `PUBLICATION` / `SUBSCRIPTION` |

Physical backup and physical replication both use **WAL** — but backup is a **point-in-time snapshot + archive**, replication is **continuous sync**.

---

## Backup Comparison

### How each works

**Physical backup**

```
Running cluster ──► copy $PGDATA files + stream WAL ──► backup repo
                    (pg_basebackup / pgBackRest / snapshot)
Later: restore files + replay archived WAL ──► PITR
```

**Logical backup**

```
Running cluster ──► pg_dump reads tables via SQL/MVCC snapshot ──► .dump / .sql
Later: pg_restore recreates objects + inserts rows (new cluster, any path)
```

### Feature matrix — backup

| Capability | Physical | Logical |
|------------|----------|---------|
| **Tool** | pg_basebackup, pgBackRest, Barman, snapshot | pg_dump, pg_dumpall |
| **Scope** | Whole cluster (all DBs) | Per database, table, schema |
| **Speed (TB scale)** | Fast (parallel, incremental) | Slow (single-threaded per table unless `-j`) |
| **PITR** | Yes (with `archive_mode`) | No (restore to dump time only) |
| **Cross PG major** | Same major for restore* | Dump from N, restore to N+ often works |
| **Partial restore** | Whole cluster only** | Table/schema selective |
| **Roles/globals** | Included in cluster files | `pg_dumpall --globals-only` separate |
| **Tablespaces** | Exact paths preserved | Awkward to relocate |
| **Version portability** | Low | High |
| **Corruption detection** | Page checksums (PG 18 default) | Re-executes SQL on restore |
| **Impact on production** | Moderate I/O | MVCC snapshot; long tx on huge tables |
| **Off-site / encryption** | pgBackRest S3 + cipher | File copy / gzip |

\* Major upgrade via physical restore requires same major or pg_upgrade path.  
\*\* Partial recovery: PITR to temp instance → pg_dump table (hybrid).

### When to use — backup

| Scenario | Choose |
|----------|--------|
| Production DR, RPO < 1 hour | **Physical** + WAL archive (pgBackRest) |
| Nightly full + hourly incremental | **Physical** (pgBackRest diff/incr) |
| Clone one app database to dev | **Logical** (`pg_dump -Fc`) |
| Migrate PG 17 → 18 with schema change | **Logical** dump/restore or logical replication |
| Export one table for audit | **Logical** (`pg_dump -t`) |
| 10 TB warehouse DR | **Physical** (pgBackRest); logical too slow |
| Schema-only to Git | **Logical** (`pg_dump -s`) |
| Compliance archive (readable SQL) | **Logical** (plain SQL) or logical + sign |

### Typical production combo

```
Physical (pgBackRest)     ──► DR, PITR, fast full restore
Logical (pg_dump weekly)  ──► portable copy, dev refresh, major upgrade path
```

---

## Replication Comparison

### How each works

**Physical (streaming) replication**

```
Primary WAL ──stream──► Standby replays byte-for-byte
Standby = copy of entire cluster, read-only (hot standby)
Failover: promote standby ──► new primary
```

**Logical replication**

```
Primary WAL ──decode──► row INSERT/UPDATE/DELETE ──► Subscriber tables
Publisher: PUBLICATION (selected tables)
Subscriber: SUBSCRIPTION (can differ PG version, writable)
```

### Feature matrix — replication

| Capability | Physical (streaming) | Logical |
|------------|---------------------|---------|
| **Granularity** | Entire cluster | Selected tables/schemas |
| **Standby reads** | Yes (hot standby) | Subscriber is normal DB (writable) |
| **Failover / HA** | Patroni, repmgr, manual promote | Not automatic HA — manual cutover |
| **DDL replication** | Automatic | **Manual** on subscriber + REFRESH |
| **Sequences** | Replicated | **Not** replicated — sync separately |
| **Large objects** | Replicated | Not via standard pub/sub |
| **Cross major version** | Same major only | Supported (upgrade pattern) |
| **Bi-directional** | No (single primary) | Possible (conflict-prone) |
| **Row filters / columns** | No | Yes (PG 15+) |
| **Lag monitoring** | `pg_stat_replication` | `pg_stat_subscription`, logical slots |
| **wal_level** | `replica` | `logical` |
| **Slot type** | Physical replication slot | Logical replication slot |
| **UNLOGGED tables** | Not replicated to standby | Not in publication by default |
| **Conflict handling** | N/A (read-only standby) | Subscriber conflicts on dual writes |

### When to use — replication

| Scenario | Choose |
|----------|--------|
| HA automatic failover (Patroni) | **Physical** streaming |
| Read replica for reporting | **Physical** standby |
| Zero-downtime major upgrade | **Logical** pub/sub |
| Replicate 3 of 50 tables to warehouse | **Logical** |
| Geo-DR read-only secondary | **Physical** |
| Filter rows to edge DB (active only) | **Logical** (PG 15+ row filter) |
| Multi-primary same data | Neither alone — careful logical bi-dir or Citus |
| CDC to Kafka/external | **Logical** decoding (pgoutput) |

---

## wal_level Requirements

| wal_level | Physical backup PITR | Streaming replication | Logical replication |
|-----------|---------------------|----------------------|---------------------|
| `minimal` | No archive for PITR | No | No |
| `replica` | Yes | Yes | No |
| `logical` | Yes | Yes | Yes |

```ini
# HA + logical pub/sub on same primary
wal_level = logical    # superset; slightly more WAL than replica
```

**Restart required** to change `wal_level`.

---

## PITR: Physical Only (Native)

| Method | PITR |
|--------|------|
| pgBackRest + archive | Yes — `recovery_target_time` |
| pg_basebackup + WAL archive | Yes |
| pg_dump | **No** — restore point = dump start snapshot |
| Logical replication | **No** — continuous forward only; use physical PITR for rewind |

**Recover deleted table:** PITR to temp cluster → pg_dump table → restore to prod (physical path).  
**Or:** logical backup if you have recent pg_dump.

---

## Major Version Upgrade Paths

| Path | Type | Downtime |
|------|------|----------|
| pg_upgrade | Physical files in-place | Minutes |
| pg_dump / pg_restore | Logical | Hours–days |
| Logical replication cutover | Logical | Minimal app cutover |
| pgBackRest + new major restore | Physical (same major restore only) | N/A cross-major |

See [Major Version Upgrade](../09-maintenance/major-version-upgrade.md).

**Logical replication upgrade flow (PG 17 → 18):**

```
PG 17 primary ──PUBLICATION──► PG 18 subscriber (copy_data=true)
Wait lag = 0 ──► stop writes ──► drop subscription ──► promote PG 18
```

---

## Architecture Patterns

### Pattern 1 — Standard production HA + DR

```
                    ┌── physical standby (streaming)
Primary ──WAL───────┤
    │               └── pgBackRest ──► S3 (PITR)
    │
    └── pg_dump (weekly) ──► dev / compliance
```

### Pattern 2 — Upgrade with logical replication

```
PG 17 (publisher) ──logical sub──► PG 18 (subscriber)
Cutover when caught up
```

### Pattern 3 — Partial warehouse sync

```
OLTP primary ──logical pub (orders, customers)──► Analytics PG (writable transforms)
Physical standby still used for HA on OLTP
```

### Pattern 4 — DR without standby (backup only)

```
Primary ──archive_command──► WAL archive
       ──pgBackRest full/diff──► repo
DR site: pgBackRest restore + PITR (no streaming replica)
```

---

## Decision Matrix (Quick Reference)

| Need | Physical | Logical |
|------|:--------:|:-------:|
| Automatic failover | ✓ | |
| Read replica | ✓ | |
| PITR | ✓ | |
| Incremental backup | ✓ | |
| Table-level copy | | ✓ |
| Cross-major migration | | ✓ |
| Writable replica | | ✓ |
| Whole cluster clone | ✓ | |
| Portable SQL backup | | ✓ |
| Minimal WAL overhead | ✓ (replica) | |

---

## Tool Mapping

| Goal | Physical tool | Logical tool |
|------|---------------|--------------|
| Online backup | pg_basebackup, pgBackRest | pg_dump |
| Continuous sync | Streaming replication | PUBLICATION/SUBSCRIPTION |
| PITR restore | pgBackRest `--type=time` | — |
| Bootstrap standby | pg_basebackup `-R` | Initial COPY via subscription |
| Globals/roles | In cluster backup | pg_dumpall `--globals-only` |
| Verify backup | pg_verifybackup, pgbackrest check | pg_restore `-l` |

---

## Common Mistakes

| Mistake | Reality |
|---------|---------|
| "pg_dump is enough for DR" | No PITR; slow restore at TB scale |
| "Logical replication = HA" | No auto-failover; not a standby replacement |
| "Physical standby for one table" | Whole cluster; use logical for subset |
| "wal_level replica is enough for logical pub" | Need `wal_level = logical` |
| "Sequences sync automatically in logical rep" | Must sync sequences before cutover |
| "Restore pg_dump over production for PITR" | Destructive; use temp instance |

---

## Monitoring Cheat Sheet

```sql
-- Physical replication lag (primary)
SELECT application_name, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- Logical replication lag (publisher)
SELECT slot_name, active,
       pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS lag
FROM pg_replication_slots WHERE slot_type = 'logical';

-- Archive (physical PITR readiness)
SELECT archived_count, failed_count, last_archived_wal FROM pg_stat_archiver;

-- Logical backup freshness (external)
-- check pg_dump file mtime / backup catalog
```

---

## Related

### Backup
- [Physical Backup](04-backup-recovery/physical-backup.md)
- [Logical Backup](04-backup-recovery/logical-backup.md)
- [pg_basebackup](04-backup-recovery/pg-basebackup.md)
- [pgBackRest](04-backup-recovery/pg-backrest.md)
- [PITR](04-backup-recovery/point-in-time-recovery.md)

### Replication
- [Streaming Replication](05-replication-ha/streaming-replication.md)
- [Logical Replication](05-replication-ha/logical-replication.md)
- [Failover](05-replication-ha/failover.md)
- [PG 18 HA Runbook](05-replication-ha/postgresql-18-ha-setup-runbook.md)

### Other
- [Architecture](01-getting-started/architecture.md)
- [Major Version Upgrade](09-maintenance/major-version-upgrade.md)
- [WAL Internals](10-advanced/wal-internals.md)
