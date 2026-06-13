# Logical Backup — pg_dump & pg_restore

Logical backups export SQL or custom-format object definitions and data. Portable across PG versions (usually same or newer major).

> **Compare with physical:** [Logical vs Physical](../01-getting-started/logical-vs-physical.md) · [Physical Backup](physical-backup.md)

## pg_dump Formats

| Flag | Format | Use case |
|------|--------|----------|
| plain (default) | `.sql` text | Small DBs, human-readable |
| `-Fc` | custom | **Recommended** — parallel restore, selective |
| `-Fd` | directory | Parallel dump/restore, large DBs |
| `-Ft` | tar | Legacy |

## Common Commands

```bash
# Single database — custom format
pg_dump -h localhost -U postgres -Fc -f app_db.dump app_db

# Parallel dump (directory format)
pg_dump -h localhost -U postgres -Fd -j 4 -f app_db_dir app_db

# Schema only
pg_dump -s -Fc -f schema.dump app_db

# Data only
pg_dump -a -Fc -f data.dump app_db

# Specific tables
pg_dump -t orders -t customers -Fc -f partial.dump app_db

# Exclude tables
pg_dump --exclude-table='staging_*' -Fc -f app.dump app_db

# Full cluster (roles + tablespaces + all DBs)
pg_dumpall -h localhost -U postgres -f cluster.sql
pg_dumpall --roles-only -f roles.sql
pg_dumpall --globals-only -f globals.sql
```

## Restore

```bash
# Plain SQL
psql -d app_db -f app_db.sql

# Custom format — parallel
pg_restore -d app_db -j 4 app_db.dump

# Clean before restore (drop objects)
pg_restore -d app_db --clean --if-exists app_db.dump

# Schema only
pg_restore -d app_db --schema-only app_db.dump

# Single table
pg_restore -d app_db -t orders app_db.dump

# No data, just create objects
pg_restore -d app_db --section=pre-data app_db.dump
```

## Important Options

| Option | Purpose |
|--------|---------|
| `--verbose` | Progress output |
| `-Z 0-9` | Compression level (custom/dir) |
| `--serializable-deferrable` | Consistent snapshot without long locks |
| `--no-owner --no-acl` | Skip ownership/ACL (restore as local user) |
| `--single-transaction` | Plain dump restore in one tx |

## Consistent Backups Without Blocking Writes

pg_dump uses MVCC snapshot — no exclusive locks on tables (except brief at start).

For very large DBs, consider:
- Directory format + `-j` for speed
- Physical backup + WAL for production DR

## Limitations

- Does **not** backup roles (use pg_dumpall --globals)
- Does **not** backup tablespaces location metadata usefully for restore to different paths
- Slow for multi-TB compared to physical
- Cannot do PITR by itself
- Large objects included but can be slow

## Cron Example

```bash
#!/bin/bash
BACKUP_DIR=/backups/logical
DATE=$(date +%Y%m%d_%H%M)
pg_dump -Fc -f "$BACKUP_DIR/app_db_$DATE.dump" app_db
find "$BACKUP_DIR" -name '*.dump' -mtime +7 -delete
```

## Verify Backup

```bash
pg_restore -l app_db.dump | head
pg_restore -d test_restore --schema-only app_db.dump
```

## Related

- [Logical vs Physical](../01-getting-started/logical-vs-physical.md)
- [Physical Backup](physical-backup.md)
- [PITR](point-in-time-recovery.md)
- [Upgrades](../09-maintenance/upgrades.md)
