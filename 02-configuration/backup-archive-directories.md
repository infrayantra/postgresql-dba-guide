# Backup Directory & Archive Mode

Configure **where backups live**, enable **WAL archiving** for **PITR**, and integrate with **pgBackRest** or filesystem archive. Targets **PostgreSQL 18**.

> See also: [PITR](../04-backup-recovery/point-in-time-recovery.md) · [pgBackRest](../04-backup-recovery/pg-backrest.md) · [pg_basebackup](../04-backup-recovery/pg-basebackup.md)

---

## Directory Layout (Recommended Production)

```
/data/pgdata/18/          ← PGDATA (data directory)
/data/pgarchive/          ← WAL archive (filesystem archive_command)
/data/pgbackup/           ← pg_basebackup tar output / manual copies
/var/lib/pgbackrest/      ← pgBackRest repo (default)
```

Create with correct ownership:

```bash
sudo mkdir -p /data/pgdata/18 /data/pgarchive /data/pgbackup /var/lib/pgbackrest
sudo chown postgres:postgres /data/pgdata/18 /data/pgarchive /data/pgbackup /var/lib/pgbackrest
sudo chmod 700 /data/pgdata/18
sudo chmod 750 /data/pgarchive /data/pgbackup /var/lib/pgbackrest
```

---

## Backup Directory — pg_basebackup Output

PostgreSQL has **no single `backup_directory` GUC** — you choose the path when running backup tools.

### Scheduled base backup to dedicated directory

```bash
BACKUP_DIR=/data/pgbackup/base-$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"

sudo -u postgres pg_basebackup \
  -h localhost \
  -U replicator \
  -D "$BACKUP_DIR" \
  -Fp -Xs -P -j 4

# Optional: pg_verifybackup for tar format
# pg_basebackup ... -Ft -z -D "$BACKUP_DIR"
# pg_verifybackup "$BACKUP_DIR"
```

### Retention script (example)

```bash
#!/bin/bash
# /usr/local/bin/pg-backup-retention.sh
find /data/pgbackup -maxdepth 1 -type d -mtime +14 -name 'base-*' -exec rm -rf {} +
```

### pgBackRest repo (preferred for production)

Backup directory is **`repo1-path`** in pgBackRest config — not in PostgreSQL:

```ini
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-path=/var/lib/pgbackrest
# or repo1-type=s3 for off-site

[main]
pg1-path=/data/pgdata/18
```

See [pgBackRest guide](../04-backup-recovery/pg-backrest.md).

---

## Archive Mode — Overview

| Setting | Purpose |
|---------|---------|
| `archive_mode` | Enable WAL segment archiving |
| `archive_command` | Shell command to copy each WAL segment |
| `archive_timeout` | Force WAL switch if idle (bounds RPO) |
| `wal_level` | Must be `replica` or `logical` |

```
Primary WAL write ──► pg_wal/ ──► archive_command ──► /data/pgarchive/ or S3
                                                      │
                                                      └── used by PITR restore_command
```

---

## Enable Archive Mode

### postgresql.conf

```ini
wal_level = replica
archive_mode = on
archive_timeout = 300          # seconds; 0 = disable forced switch
archive_command = 'test ! -f /data/pgarchive/%f && cp %p /data/pgarchive/%f'
```

**Restart required** for `archive_mode` and `wal_level` changes:

```bash
sudo systemctl restart postgresql-18
```

Reload is **not** enough for first-time `archive_mode = on`.

### pgBackRest archive_command (production)

```ini
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_timeout = 60
```

Initialize stanza after enabling:

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main check
```

### archive_command placeholders

| Token | Meaning |
|-------|---------|
| `%p` | Full path to WAL file in `pg_wal/` |
| `%f` | WAL file name only (e.g. `000000010000000000000001`) |

Command must return **exit 0** on success. Non-zero causes PostgreSQL to **retry indefinitely** and eventually fill `pg_wal/`.

### S3 archive (aws cli example)

```ini
archive_command = 'aws s3 cp %p s3://my-bucket/pg-wal/%f --only-show-errors'
```

---

## Verify Archiving

```sql
SHOW archive_mode;
SHOW archive_command;

SELECT archived_count, failed_count,
       last_archived_wal, last_archived_time,
       last_failed_wal, last_failed_time,
       stats_reset
FROM pg_stat_archiver;
```

```bash
# Force WAL switch and test archive
sudo -u postgres psql -c "SELECT pg_switch_wal();"
ls -la /data/pgarchive/ | tail -5

# pgBackRest
sudo -u postgres pgbackrest --stanza=main info
```

Expected: `failed_count = 0`, `last_archived_wal` advancing.

---

## Archive Directory Sizing

| Factor | Estimate |
|--------|----------|
| WAL rate | Depends on write workload |
| Retention | Match PITR window (e.g. 14–30 days) |
| Segment size | Default 16 MB per file |

```
Daily WAL ≈ (write throughput MB/s) × 86400 / 16 MB segments
```

Monitor disk:

```bash
df -h /data/pgarchive
du -sh /data/pgarchive
```

pgBackRest: use `repo1-retention-archive` and `repo1-retention-archive-type=time`.

---

## Standby Archiving

By default standbys **do not** archive their own WAL. Primary archives. After promotion, new primary must have:

```ini
archive_mode = on
archive_command = '...'
```

Patroni sets this automatically on primary role.

---

## Disable / Change Archive Mode

```ini
# To disable (requires restart)
archive_mode = off
```

Before disabling, ensure you no longer need PITR for that window. Existing archived WAL remains usable for restore.

To change archive path:

```ini
archive_command = 'test ! -f /new/archive/%f && cp %p /new/archive/%f'
SELECT pg_reload_conf();
```

---

## Patroni Example

```yaml
postgresql:
  parameters:
    archive_mode: 'on'
    archive_command: 'test ! -f /data/pgarchive/%f && cp %p /data/pgarchive/%f'
    archive_timeout: '300'
    wal_level: replica
  recovery_conf:
    restore_command: 'cp /data/pgarchive/%f %p'
```

On replica, `restore_command` fetches WAL during recovery; primary uses `archive_command`.

---

## Monitoring Checklist

- [ ] `archive_mode = on` on primary
- [ ] `pg_stat_archiver.failed_count = 0`
- [ ] Archive disk / S3 lifecycle within retention policy
- [ ] `pgbackrest check` passes (if using pgBackRest)
- [ ] Base backup + archive tested together (PITR drill)

---

## Related

- [Point-in-Time Recovery](../04-backup-recovery/point-in-time-recovery.md)
- [Data Directory](data-directory.md)
- [postgresql.conf — WAL section](postgresql-conf.md)
- [DC/DR Drill](../04-backup-recovery/dc-dr-drill.md)
