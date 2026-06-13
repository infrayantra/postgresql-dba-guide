# Point-in-Time Recovery (PITR)

Restore a PostgreSQL cluster to **any moment** between a base backup and the latest archived WAL — e.g. before an accidental `DROP TABLE` or bad migration.

**PostgreSQL 18** — requires `archive_mode = on`, working `archive_command`, and at least one base backup.

> Setup: [Backup & Archive Directories](../02-configuration/backup-archive-directories.md) · [pgBackRest](pg-backrest.md) · [pg_basebackup](pg-basebackup.md)

---

## How PITR Works

```
Timeline ─────────────────────────────────────────────────────►

  t0              t1                    t2              t3
  │← base backup →│← archived WAL ─────►│← live WAL ───►│ now
                  │                     │
                  └── recovery_target ──┘
                      (stop replay here, then promote)
```

1. **Base backup** — consistent snapshot of data files at time t1
2. **Archived WAL** — all changes from t1 toward t3 stored off-server
3. **Recovery** — replay WAL until `recovery_target_*`, then promote to read/write

Without archived WAL, you can only restore to **end of base backup** (not true PITR).

---

## Prerequisites Checklist

- [ ] `wal_level = replica` (or `logical`)
- [ ] `archive_mode = on` on primary (since before target time)
- [ ] `archive_command` succeeding — `pg_stat_archiver.failed_count = 0`
- [ ] Base backup covering period **before** recovery target
- [ ] Archived WAL continuous from base backup through recovery target
- [ ] Recovery host with PostgreSQL 18 same major version as backup

```sql
SELECT archived_count, failed_count, last_archived_wal, last_archived_time
FROM pg_stat_archiver;
```

---

## Configure Archiving (If Not Done)

See [Backup & Archive Directories](../02-configuration/backup-archive-directories.md).

**Filesystem:**

```ini
archive_mode = on
archive_command = 'test ! -f /data/pgarchive/%f && cp %p /data/pgarchive/%f'
archive_timeout = 300
```

**pgBackRest:**

```ini
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
```

Restart PostgreSQL after enabling `archive_mode`.

---

## Recovery Targets

| Parameter | Example | Use when |
|-----------|---------|----------|
| `recovery_target_time` | `'2025-06-14 10:29:00+00'` | Known bad event time |
| `recovery_target_name` | `'before_migration'` | `pg_create_restore_point()` used |
| `recovery_target_lsn` | `'0/1A2B3C4D'` | Precise WAL position |
| `recovery_target_xid` | `'1234567'` | Transaction boundary |
| `recovery_target = 'immediate'` | — | End of backup only (no WAL replay) |
| (none) | — | Replay all available WAL |

Supporting parameters:

| Parameter | Values | Meaning |
|-----------|--------|---------|
| `recovery_target_inclusive` | `true` / `false` | Include target WAL record |
| `recovery_target_action` | `promote` / `pause` / `shutdown` | After target reached |
| `recovery_target_timeline` | `1`, `2`, … | Specific timeline |

Create named restore point **before** risky change:

```sql
SELECT pg_create_restore_point('before_schema_v2_deploy');
-- Returns LSN; WAL must be archived for PITR to reach it
```

---

## PITR Method A — pgBackRest (Recommended)

### Restore to timestamp

```bash
sudo systemctl stop postgresql-18

sudo -u postgres rm -rf /data/pgdata/18/*
sudo -u postgres mkdir -p /data/pgdata/18

sudo -u postgres pgbackrest --stanza=main --type=time \
  --target='2025-06-14 10:29:00+00' \
  --target-action=promote \
  --delta restore

sudo systemctl start postgresql-18
```

pgBackRest sets `restore_command` and recovery config automatically.

### Restore to named point

```bash
sudo -u postgres pgbackrest --stanza=main \
  --type=name --target='before_migration' \
  --target-action=promote \
  --delta restore
```

### Verify

```bash
tail -f /data/pglog/postgresql*.log
# Look for: "recovery stopping before commit time ..."
```

```sql
SELECT pg_is_in_recovery();   -- false after promote
SELECT now(), pg_postmaster_start_time();
```

---

## PITR Method B — Manual (pg_basebackup + WAL archive)

### Step 1 — Stop and prepare

```bash
sudo systemctl stop postgresql-18
sudo mv /data/pgdata/18 /data/pgdata/18.before-pitr
sudo mkdir -p /data/pgdata/18
sudo chown postgres:postgres /data/pgdata/18
```

### Step 2 — Restore base backup

```bash
# Copy latest base backup taken BEFORE recovery target time
sudo -u postgres cp -a /data/pgbackup/base-20250614/* /data/pgdata/18/
# Or pg_basebackup output directory
```

### Step 3 — Recovery configuration

```bash
sudo -u postgres touch /data/pgdata/18/recovery.signal
```

```ini
# /data/pgdata/18/postgresql.auto.conf

restore_command = 'test -f /data/pgarchive/%f && cp /data/pgarchive/%f %p'

recovery_target_time = '2025-06-14 10:29:00+00'
recovery_target_action = 'promote'
recovery_target_inclusive = false
```

**pgBackRest restore_command variant:**

```ini
restore_command = 'pgbackrest --stanza=main archive-get %f %p'
```

### Step 4 — Start and monitor

```bash
sudo systemctl start postgresql-18
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
```

Logs show WAL replay progress until target reached.

---

## PITR to Isolated Instance (Production-Safe Drill)

Never PITR over production data — restore to **separate host**:

```bash
# DR host — empty PG 18 install
pgbackrest --stanza=main --pg1-path=/pitr-test/data \
  --type=time --target='2025-06-14 10:29:00+00' \
  --target-action=promote --delta restore

pg_ctl -D /pitr-test/data -o "-p 5433" start
psql -p 5433 -c "SELECT count(*) FROM app.orders;"
```

Extract data with `pg_dump` or `COPY`, then load into production.

---

## Partial Recovery (Single Table / Database)

PITR restores **entire cluster**. For one table:

1. PITR to temp instance on port 5433
2. Export object:

```bash
pg_dump -h localhost -p 5433 -t public.orders -Fc -f orders_recovered.dump
pg_restore -h prod -d app_db -t orders orders_recovered.dump
```

Or use `COPY (SELECT ...) TO STDOUT` for selective rows.

---

## Timeline Forks

Failover and incomplete recovery create new **timelines**. WAL filenames include timeline ID.

```bash
ls /data/pgarchive/
# 00000002.history — timeline switch
# 0000000200000001000000AB — timeline 2 segment

pg_waldump /data/pgarchive/0000000200000001000000AB | head -20
```

If recovery stops early:

- Missing WAL segment — gap in archive; check `last_archived_wal` vs needed file
- Wrong timeline — set `recovery_target_timeline = 'latest'` or specific ID

---

## Tablespaces

All tablespace paths from backup must exist on recovery host with same paths, or use symlinks:

```sql
-- On backup source
SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;
```

```bash
mkdir -p /mnt/fast/pgts
chown postgres:postgres /mnt/fast/pgts
```

---

## RPO / RTO

| Metric | Definition | Drivers |
|--------|------------|---------|
| **RPO** (max data loss) | Time between last recoverable point and failure | `archive_timeout`, archive lag, replication |
| **RTO** (max downtime) | Time to restore service | Backup size, restore automation, drill practice |

| archive_timeout | Max RPO (no writes) |
|-----------------|---------------------|
| 300s | ~5 min + archive lag |
| 60s | ~1 min + archive lag |
| 0 (disabled) | Until next WAL segment fills (~16 MB writes) |

With streaming replication: RPO ≈ replication lag; PITR still needed for logical errors (bad DELETE).

---

## Common Failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `could not find redo location` | Base backup too old / wrong dir | Use correct backup before target |
| `requested WAL segment ... has already been removed` | Archive gap | Restore missing WAL from off-site; fix archive_command |
| Recovery never ends | No recovery_target set | Set target or use `promote` manually |
| Recovery past target | `recovery_target_inclusive = true` | Set `false` |
| Wrong data after recovery | Recovered to wrong time (timezone) | Use `+00` UTC in target |
| `archive command failed` on primary | Broken archive | Fix before you need PITR |

```sql
-- Find recovery progress (during recovery)
SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
```

---

## Monthly PITR Test Script (Outline)

```bash
#!/bin/bash
set -e
TARGET_TIME="$(date -u -d '1 hour ago' '+%Y-%m-%d %H:%M:%S+00')"
TEST_DIR=/pitr-drill/$(date +%Y%m%d)

mkdir -p "$TEST_DIR"
pgbackrest --stanza=main --pg1-path="$TEST_DIR/data" \
  --type=time --target="$TARGET_TIME" \
  --target-action=promote --delta restore

pg_ctl -D "$TEST_DIR/data" -o "-p 5434" start
psql -p 5434 -c "SELECT pg_is_in_recovery();"  # expect f
psql -p 5434 -c "SELECT count(*) FROM pg_database;"
pg_ctl -D "$TEST_DIR/data" stop
echo "PITR drill OK to $TARGET_TIME"
```

Document duration and row checksums in DR log. See [DC/DR Drill](dc-dr-drill.md).

---

## Quick Reference

```ini
# Primary — enable PITR capability
wal_level = replica
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'

# Recovery host — postgresql.auto.conf
restore_command = 'pgbackrest --stanza=main archive-get %f %p'
recovery_target_time = '2025-06-14 10:29:00+00'
recovery_target_action = 'promote'
# + recovery.signal file (PG 12+)
```

---

## Related

- [Backup & Archive Directories](../02-configuration/backup-archive-directories.md)
- [Data Directory](../02-configuration/data-directory.md)
- [pgBackRest](pg-backrest.md)
- [pg_basebackup](pg-basebackup.md)
- [Physical Backup](physical-backup.md)
- [DC/DR Drill](dc-dr-drill.md)
- [Corruption Recovery](../11-troubleshooting/corruption-recovery.md)
