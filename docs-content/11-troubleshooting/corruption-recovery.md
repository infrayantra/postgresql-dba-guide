# Corruption Detection & Recovery

## Prevention

1. Enable **data checksums** at initdb (cannot enable later without rebuild)
2. Use ECC RAM on database servers
3. Reliable storage (avoid non-journaled mounts for `$PGDATA`)
4. Graceful shutdown — avoid `kill -9` on postmaster
5. Test backups and PITR regularly

```sql
SHOW data_checksums;  -- should be on
```

## Detection

### Checksum Failures (if enabled)

```
ERROR: invalid page in block 12345 of relation base/16384/16385
WARNING: page verification failed, calculated checksum ...
```

Logged automatically; query fails.

### amcheck Extension

```sql
CREATE EXTENSION amcheck;

-- Verify btree index structure
SELECT bt_index_check(index => c.oid, heapallindexed => true)
FROM pg_class c
JOIN pg_index i ON i.indexrelid = c.oid
JOIN pg_am am ON c.relam = am.oid
WHERE am.amname = 'btree' AND c.relnamespaces != 0
LIMIT 10;

-- PG 14+: table verify
SELECT verify_heapam(oid) FROM pg_class WHERE relname = 'orders';
```

Schedule during maintenance windows on critical indexes.

### External Tools

- `pg_verify_checksums` (offline, PG 12+)
- `pg_dump` — may fail on corrupt pages

## Corruption Scenarios

| Scenario | Response |
|----------|----------|
| Single page corruption | Restore table from backup; zero_damaged_pages last resort |
| Index corruption | `REINDEX INDEX CONCURRENTLY idx_name` |
| Widespread corruption | PITR or full restore from backup |
| File system damage | Restore from replica or backup |

## zero_damaged_pages (Emergency Only)

```ini
# postgresql.conf — causes **data loss** on damaged pages
zero_damaged_pages = on
```

Restart, run query to touch damaged area — zeros out page. **Last resort.**

## Recovery Workflow

```
1. Stop writes (prevent further damage)
2. Assess scope (one table? index? whole cluster?)
3. Try REINDEX if index-only
4. pg_dump unaffected tables if partial
5. PITR to point before corruption event
6. Failover to clean standby if available
7. Engage PostgreSQL community/support with logs + pg_waldump
```

## PITR for Point-Before-Corruption

```bash
pgbackrest --stanza=main --type=time \
  --target='2025-06-13 22:00:00' \
  --target-action=promote restore
```

## Standby as Recovery Source

If primary corrupted but standby clean:

```bash
# Planned: pg_ctl promote on standby
# Rebuild primary from standby pg_basebackup
```

## pg_waldump for Forensics

```bash
pg_waldump -p $PGDATA/pg_wal -s 0/1000000 -e 0/2000000 | grep INSERT
```

## After Recovery

```sql
ANALYZE;
-- amcheck full run
-- Review logs for root cause (hardware, FS bug, admin error)
-- Document incident
```

## Related

- [PITR](../04-backup-recovery/point-in-time-recovery.md)
- [Physical Backup](../04-backup-recovery/physical-backup.md)
- [Failover](../05-replication-ha/failover.md)
