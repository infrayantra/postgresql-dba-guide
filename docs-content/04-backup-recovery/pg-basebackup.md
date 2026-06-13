# pg_basebackup — Physical Base Backup

**pg_basebackup** is PostgreSQL's built-in tool for **online physical backups** and **standby bootstrap**. Required for PITR when combined with WAL archiving. Ships with **PostgreSQL 18** at `/usr/pgsql-18/bin/pg_basebackup`.

> See also: [Physical Backup Overview](physical-backup.md) · [pgBackRest](pg-backrest.md) · [PITR](point-in-time-recovery.md)

---

## What pg_basebackup Does

```
Primary (running)                    Target directory
┌─────────────────┐                 ┌──────────────────┐
│ Data files      │ ──stream/copy──►│ base/            │
│ WAL (optional)  │ ──-Xs stream───►│ pg_wal/ (partial)│
│                 │ ──-R flag──────►│ standby.signal   │
│                 │                 │ postgresql.auto.conf
└─────────────────┘                 └──────────────────┘
```

| Output | Use |
|--------|-----|
| Plain directory (`-Fp`) | Standby data dir, manual restore |
| Tar (`-Ft`) | Portable archive; `pg_verifybackup` |
| With `-R` | Auto-configure streaming replica (PG 12+) |

---

## Prerequisites

### Replication user

```sql
CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD 'strong-password';
```

### pg_hba.conf

```
# TYPE  DATABASE  USER         ADDRESS        METHOD
hostssl replication replicator  10.0.0.0/8     scram-sha-256
```

### postgresql.conf (primary)

```ini
max_wal_senders = 10
max_replication_slots = 10
wal_level = replica    # or logical if also using logical replication
```

Reload after changes:

```bash
pg_ctl reload -D /var/lib/pgsql/18/data
```

---

## Basic Commands

### Plain-format backup (most common for standbys)

```bash
export PGPASSWORD='strong-password'

pg_basebackup \
  -h primary.example.com \
  -p 5432 \
  -U replicator \
  -D /var/lib/pgsql/18/data \
  -Fp \
  -Xs \
  -P \
  -R
```

| Flag | Meaning |
|------|---------|
| `-Fp` | Plain format (copy files as-is) |
| `-Ft` | Tar format (one tar per tablespace + manifest) |
| `-Xs` | Stream WAL into backup (required for consistent plain backup while running) |
| `-P` | Progress reporting |
| `-R` | Write `standby.signal` + `primary_conninfo` to `postgresql.auto.conf` |
| `-z` | gzip (tar only) |
| `-j N` | Parallel backup (tar only, PG 15+) |
| `-S slotname` | Use existing replication slot |
| `-C -S slotname` | Create temporary slot (auto-dropped when backup completes) |
| `--waldir=WALDIR` | Separate WAL directory (PG 15+) |

### Tar format with verification

```bash
pg_basebackup -h primary -U replicator -D /backup/base-$(date +%Y%m%d) \
  -Ft -z -Xs -P -j 4

# PG 13+: verify manifest checksums
pg_verifybackup /backup/base-20250614
```

### Replication slot (prevent WAL removal during long backup)

```sql
-- On primary — permanent slot for scheduled backups
SELECT pg_create_physical_replication_slot('basebackup_slot');
```

```bash
pg_basebackup -h primary -U replicator -D /backup/standby \
  -Fp -Xs -P -R -S basebackup_slot
```

Monitor slot lag:

```sql
SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
FROM pg_replication_slots;
```

---

## Bootstrap a Standby (PG 12+)

```bash
# Stop if reusing directory
sudo systemctl stop postgresql-18

# Empty target (preserve if fresh OS install)
sudo rm -rf /var/lib/pgsql/18/data/*
sudo mkdir -p /var/lib/pgsql/18/data
sudo chown postgres:postgres /var/lib/pgsql/18/data

sudo -u postgres pg_basebackup \
  -h 10.0.1.11 \
  -U replicator \
  -D /var/lib/pgsql/18/data \
  -Fp -Xs -P -R \
  -S standby1_slot
```

Edit connection info if password not in `.pgpass`:

```bash
# /var/lib/pgsql/18/data/postgresql.auto.conf
# primary_conninfo = 'host=10.0.1.11 port=5432 user=replicator password=... sslmode=require'
```

Start standby:

```bash
sudo systemctl start postgresql-18
```

Verify:

```sql
SELECT pg_is_in_recovery();              -- true
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();
SELECT status, conninfo FROM pg_stat_wal_receiver;
```

On primary:

```sql
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;
```

---

## pg_basebackup vs pgBackRest

| Aspect | pg_basebackup | pgBackRest |
|--------|---------------|------------|
| Install | Built-in | Separate package |
| Incremental | No | Yes (block-level) |
| Retention policy | Manual | Built-in |
| S3/cloud repo | Manual scripting | Native |
| Encryption | Relies on disk/TLS | Built-in cipher |
| Standby bootstrap | Excellent | `restore` + replication |
| Fleet management | Per-script | Stanza-based |

**Use pg_basebackup when:** bootstrapping replicas, ad-hoc backups, minimal tooling, CI/CD clone.

**Use pgBackRest when:** production retention, incrementals, encrypted off-site repo, automated PITR.

Many sites use **both**: pgBackRest for backups, pg_basebackup for new standbys.

---

## PITR from pg_basebackup

Base backup alone is a **point-in-time snapshot** at backup completion. For PITR you need **continuous WAL archive**.

### 1. Take base backup

```bash
pg_basebackup -h primary -U replicator -D /archive/base/full-20250614 -Fp -Xs -P
```

### 2. Ensure WAL archiving on primary

```ini
archive_mode = on
archive_command = 'test ! -f /wal_archive/%f && cp %p /wal_archive/%f'
# Production: use pgBackRest archive-push instead
```

### 3. Restore on recovery host

```bash
systemctl stop postgresql-18
rm -rf /var/lib/pgsql/18/data/*
cp -a /archive/base/full-20250614/* /var/lib/pgsql/18/data/

touch /var/lib/pgsql/18/data/recovery.signal   # PG 12+
```

```ini
# postgresql.conf or postgresql.auto.conf
restore_command = 'cp /wal_archive/%f %p'
recovery_target_time = '2025-06-14 10:30:00+00'
recovery_target_action = 'promote'
```

```bash
systemctl start postgresql-18
```

Monitor:

```sql
SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();
-- Logs: "recovery stopping before commit time ..."
```

Full walkthrough: [Point-in-Time Recovery](point-in-time-recovery.md)

---

## Tablespaces

pg_basebackup follows tablespace symlinks. Ensure target paths exist with correct ownership:

```bash
pg_basebackup ... -D /data --tablespace-mapping=/old/ts1=/new/ts1
```

List tablespaces before backup:

```sql
SELECT oid, spcname, pg_tablespace_location(oid) FROM pg_tablespace;
```

---

## Security

```bash
# ~/.pgpass for replicator (mode 600)
primary.example.com:5432:replication:replicator:strong-password

# Force SSL
pg_basebackup -h primary -U replicator -D /backup -Fp -Xs -P \
  --config-file=/path/to/.pg_service.conf
```

In `postgresql.auto.conf` on standby, prefer `sslmode=verify-full` and cert auth for production.

---

## Patroni / HA Integration

Patroni bootstraps replicas automatically — you rarely run pg_basebackup manually:

```yaml
# patroni.yml — Patroni invokes pg_basebackup internally
postgresql:
  create_replica_methods:
    - basebackup
  basebackup:
    max-rate: '100M'
    checkpoint: fast
    slot: 'patroni_replica_slot'
```

Manual rebuild when Patroni state is broken:

```bash
systemctl stop patroni
rm -rf /var/lib/pgsql/18/data/*
sudo -u postgres pg_basebackup -h other-node -U replicator \
  -D /var/lib/pgsql/18/data -Fp -Xs -P -R -S rebuild_slot
systemctl start patroni
```

See [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md).

---

## Scheduling with cron

```bash
# /etc/cron.d/pg-basebackup — weekly tar to NFS (example)
0 2 * * 0 postgres pg_basebackup -h localhost -U replicator \
  -D /backup/weekly/$(date +\%Y\%m\%d) -Ft -z -Xs -P -j 4 && \
  pg_verifybackup /backup/weekly/$(date +\%Y\%m\%d)
```

Prefer pgBackRest for scheduled production backups with retention.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `permission denied for replication` | User lacks `REPLICATION` | `ALTER ROLE ... REPLICATION` |
| `no pg_hba.conf entry` | HBA missing replication line | Add `hostssl replication ...` |
| `could not connect` | Firewall / wrong host | Open 5432; check `-h` |
| `WAL segment has already been removed` | Backup too slow, no slot | Use `-C -S tempslot` or permanent slot |
| `directory exists but is not empty` | Target has files | Empty `-D` directory |
| `pg_verifybackup: checksum mismatch` | Corrupt transfer/storage | Re-run backup; check disk/NFS |

```sql
-- On primary during backup
SELECT * FROM pg_stat_progress_basebackup;
```

---

## Monitoring Checklist

- [ ] Replication user uses SCRAM, SSL in production
- [ ] Slot lag monitored if using `-S`
- [ ] `pg_verifybackup` on tar backups (PG 13+)
- [ ] Monthly restore test to isolated instance
- [ ] Backup duration < WAL retention window

---

## Related

- [Physical Backup Overview](physical-backup.md)
- [pgBackRest](pg-backrest.md)
- [Point-in-Time Recovery](point-in-time-recovery.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
- [DC/DR Drill](dc-dr-drill.md)
- [Major Version Upgrade](../09-maintenance/major-version-upgrade.md)
