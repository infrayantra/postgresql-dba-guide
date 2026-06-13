# Physical Backup

Physical backups copy data files and WAL — required for **PITR** and fast recovery of large databases.

> **Compare with logical:** [Logical vs Physical](../01-getting-started/logical-vs-physical.md) · [Logical Backup](logical-backup.md)  
> **Paths:** [Data Directory](../02-configuration/data-directory.md) · [Backup & Archive](../02-configuration/backup-archive-directories.md)  
> **Deep dives:** [pg_basebackup](pg-basebackup.md) · [pgBackRest](pg-backrest.md) · [PITR](point-in-time-recovery.md)

## Methods Overview

| Method | Tool | Downtime | PITR |
|--------|------|----------|------|
| File system snapshot | LVM/ZFS/EBS | Brief freeze optional | Yes with WAL |
| pg_basebackup | built-in | None (online) | Yes |
| pgBackRest | third-party | None | Yes |
| Barman | third-party | None | Yes |
| tar/cp (stopped) | manual | Full stop required | Partial |

## pg_basebackup

Built-in online backup and standby bootstrap. Full guide: **[pg_basebackup](pg-basebackup.md)**.

```bash
pg_basebackup -h primary -U replicator -D /var/lib/pgsql/18/data -Fp -Xs -P -R
```

## Standby from Base Backup

After `pg_basebackup -R`:

```bash
# PG 12+: standby.signal file created by -R
cat >> /backup/postgresql.auto.conf <<EOF
primary_conninfo = 'host=primary port=5432 user=replicator password=... sslmode=require'
EOF

pg_ctl -D /backup start
```

Verify:

```sql
SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();
```

## Filesystem Snapshot Backup

```bash
# 1. Optional: start backup label
psql -c "SELECT pg_start_backup('snapshot_20250614', false);"

# 2. Snapshot $PGDATA (LVM example)
lvcreate -L 50G -s -n pg_snap /dev/vg/pgdata

# 3. End backup
psql -c "SELECT pg_stop_backup();"

# 4. Mount snapshot elsewhere or backup copy
```

**PG 15+:** use `pg_backup_start()` / `pg_backup_stop()` instead of deprecated `pg_start_backup()`.

```sql
SELECT pg_backup_start(label => 'snap1', fast => false);
-- take snapshot
SELECT * FROM pg_backup_stop();
```

## What Must Be Included

- Entire `$PGDATA` directory consistently
- All WAL needed from backup start to stop
- `tablespace` symlinks if used

## Recovery Configuration

```ini
# postgresql.conf on restored host
restore_command = 'cp /archive/%f %p'
recovery_target_time = '2025-06-14 10:30:00 UTC'   # optional PITR
recovery_target_action = 'promote'
```

PG 12+ recovery settings go in `postgresql.auto.conf` or `recovery.signal` file present during recovery.

## Verify Backup Integrity

```bash
# pg_verifybackup (PG 13+) for tar format
pg_verifybackup /backup/base

# Restore to test instance regularly
```

## Backup Frequency Guidelines

| RPO need | Strategy |
|----------|----------|
| 24 hours | Nightly base backup |
| 1 hour | Base + continuous WAL archive |
| Minutes | Streaming replication + periodic base |

## Related

- [pg_basebackup](pg-basebackup.md)
- [PITR](point-in-time-recovery.md)
- [pgBackRest](pg-backrest.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
