# WAL & Checkpoint Internals

## WAL Purpose

Write-Ahead Logging guarantees **durability** and supports replication/PITR. Data file changes are logged before being applied to heap pages.

## WAL Segment Files

- Location: `$PGDATA/pg_wal/`
- Default size: **16 MB** per segment (`wal_segment_size`)
- Naming: `TTTTTTTTLLLLLLLLSSSSSSSS` (timeline, log, segment)

```bash
pg_waldump -p $PGDATA/pg_wal 000000010000000100000000 | head -50
```

## WAL Levels

| wal_level | Content | Use |
|-----------|---------|-----|
| minimal | Minimal WAL for crash recovery | Standalone, no replication |
| replica | + hot standby + archiving | Physical replication, PITR |
| logical | + logical decoding info | Logical replication, CDC |

## Checkpoint Process

Checkpoints flush dirty buffers and create recovery starting point.

```ini
checkpoint_timeout = 15min
max_wal_size = 4GB              # triggers checkpoint when WAL exceeds
min_wal_size = 1GB
checkpoint_completion_target = 0.9   # spread writes over 90% of interval
checkpoint_warning = 30s
```

```sql
CHECKPOINT;  -- manual (requires superuser)
```

## full_page_writes

After checkpoint, first page modification writes full page image to WAL — protects against partial page writes (torn pages).

```ini
full_page_writes = on   # keep on unless using reliable atomic writes + snapshots
```

## synchronous_commit Spectrum

| Value | Behavior |
|-------|----------|
| on | Wait for WAL flush to disk (default) |
| remote_apply | Wait for standby to apply |
| remote_write | Wait for standby to receive |
| local | Don't wait for replica |
| off | Async commit — risk last ~600ms transactions on crash |

## WAL Archiving Flow

```
Insert/Update/Delete
  → WAL record in memory (wal_buffers)
  → walwriter flushes to pg_wal/
  → on segment complete + archive_mode: archive_command
  → checkpointer → recycle old segments (if not held by slot)
```

```sql
SELECT * FROM pg_stat_archiver;
SELECT pg_switch_wal();  -- force segment rotation
```

## Replication Slot WAL Retention

Slots prevent removal of WAL still needed by standby or logical consumer:

```sql
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
FROM pg_replication_slots;
```

**Danger:** inactive slot → primary disk fill.

## Monitor WAL Generation Rate

```sql
SELECT pg_current_wal_lsn(),
       pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS total_bytes;

-- pg_stat_wal (PG 14+)
SELECT * FROM pg_stat_wal;
```

## wal_compression

```ini
wal_compression = on    # PG 15+: lz4, zstd
```

Reduces WAL volume for bulk loads — CPU tradeoff.

## Recovery Process

On crash/restart:
1. Read last checkpoint record
2. Replay WAL from checkpoint REDO point
3. Rollback uncommitted transactions

## Related

- [Physical Backup](../04-backup-recovery/physical-backup.md)
- [PITR](../04-backup-recovery/point-in-time-recovery.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
