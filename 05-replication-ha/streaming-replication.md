# Streaming (Physical) Replication

> **PostgreSQL 18** — standard streaming replication; use `scram-sha-256` for replication users. HA setup: [PG 18 HA Runbook](postgresql-18-ha-setup-runbook.md).

> **Compare with logical replication:** [Logical vs Physical](../01-getting-started/logical-vs-physical.md) · [Logical Replication](logical-replication.md)

Binary replication of WAL from primary to one or more standby servers. Standbys are read-only (hot standby).

## Requirements

```ini
# Primary postgresql.conf
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB
archive_mode = on   # recommended for PITR
```

```sql
CREATE ROLE replicator LOGIN REPLICATION PASSWORD '...';
SELECT pg_create_physical_replication_slot('standby1');
```

```
# pg_hba.conf on primary
hostssl replication replicator 10.0.2.0/24 scram-sha-256
```

## Standby Setup (pg_basebackup)

Full guide: [pg_basebackup](../04-backup-recovery/pg-basebackup.md)

```bash
pg_basebackup -h primary -U replicator -D $PGDATA -Fp -Xs -P -R
```

Edit `postgresql.auto.conf`:

```ini
primary_conninfo = 'host=primary port=5432 user=replicator password=... sslmode=require'
primary_slot_name = 'standby1'
```

```bash
touch $PGDATA/standby.signal   # created by -R in PG 12+
pg_ctl -D $PGDATA start
```

## Monitor Replication

**On primary:**

```sql
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes
FROM pg_replication_slots;
```

**On standby:**

```sql
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp(),
       now() - pg_last_xact_replay_timestamp() AS replay_delay;
```

## Synchronous Replication

```ini
synchronous_commit = on
synchronous_standby_names = 'FIRST 1 (standby1, standby2)'
# or: 'ANY 2 (standby1, standby2, standby3)'
```

```sql
-- Standby application_name must match
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (standby1)';
SELECT pg_reload_conf();
```

Trade-off: zero data loss on primary failure vs. write latency.

## Replication Slots

Prevent WAL removal until consumer replays:

```sql
SELECT * FROM pg_replication_slots;

-- Danger: inactive slot causes WAL bloat on primary
-- Monitor pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
```

## Cascading Replication

Standby can stream to downstream standbys:

```ini
# intermediate standby
max_wal_senders = 10
hot_standby = on
```

## Hot Standby Conflicts

Long queries on standby can block WAL replay:

```sql
-- Standby
SELECT * FROM pg_stat_database_conflicts;

-- Mitigation on standby
hot_standby_feedback = on
max_standby_streaming_delay = 30s
```

Or cancel conflicting queries on standby.

## Read-Only Queries on Standby

```sql
-- Default: standbys accept reads
hot_standby = on
```

Use connection routing (PgPool, HAProxy, app config) to send SELECTs to replicas.

## WAL Shipping vs. Streaming

| Method | Transport | Lag |
|--------|-----------|-----|
| Streaming | TCP walsender/walreceiver | Seconds |
| Archive + restore | archive_command + restore_command | Minutes |

Streaming is standard for HA; archiving adds PITR capability.

See [Replication Slots](replication-slots.md) for inactive slot disk fill.

## Related

- [Replication Slots](replication-slots.md)
- [Logical Replication](logical-replication.md)
- [Failover](failover.md)
- [Physical Backup](../04-backup-recovery/physical-backup.md)
