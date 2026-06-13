# Logical Replication

Replicates **data changes** at the logical level (row changes) — selective tables, cross-version upgrades, bi-directional patterns.

Requires `wal_level = logical`.

> **Compare with physical streaming:** [Logical vs Physical](../01-getting-started/logical-vs-physical.md) · [Streaming Replication](streaming-replication.md)

## Publisher Setup

```sql
-- Primary
CREATE PUBLICATION app_pub FOR TABLE orders, customers, products;

-- All tables in schema
CREATE PUBLICATION app_pub FOR ALL TABLES IN SCHEMA public;

-- With row filter (PG 15+)
CREATE PUBLICATION active_orders_pub FOR TABLE orders WHERE (status = 'active');

-- With column list (PG 15+)
CREATE PUBLICATION slim_pub FOR TABLE customers (id, name, email);
```

```sql
CREATE ROLE repl_user REPLICATION LOGIN PASSWORD '...';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_user;
-- PG 15+: default privileges for future tables
```

## Subscriber Setup

```sql
-- Subscriber (can be different PG major version)
CREATE SUBSCRIPTION app_sub
  CONNECTION 'host=primary port=5432 dbname=app_db user=repl_user password=...'
  PUBLICATION app_pub
  WITH (copy_data = true, create_slot = true);

-- Monitor
SELECT * FROM pg_subscription;
SELECT * FROM pg_stat_subscription;
```

## Initial Sync vs. Ongoing

1. `copy_data = true` — table snapshot then streaming
2. `create_slot = true` — creates logical slot on publisher
3. Changes applied via apply workers on subscriber

```sql
-- Disable / enable
ALTER SUBSCRIPTION app_sub DISABLE;
ALTER SUBSCRIPTION app_sub ENABLE;

-- Refresh table schema after DDL
ALTER SUBSCRIPTION app_sub REFRESH PUBLICATION;
```

## DDL Replication

Logical replication does **not** replicate DDL automatically.

Workflow:
1. Apply DDL on subscriber (or use event triggers)
2. `ALTER SUBSCRIPTION ... REFRESH PUBLICATION`

## Conflict Handling (Bi-directional)

Subscriber writes can conflict with incoming changes:

```sql
-- Subscriber
ALTER SUBSCRIPTION app_sub SET (disable_on_error = off);
-- Handle via triggers or avoid dual writes to same rows
```

## Logical vs. Physical

Full comparison: **[Logical vs Physical](../01-getting-started/logical-vs-physical.md)** — backup and replication matrices, decision guide, upgrade patterns.

| Aspect | Physical | Logical |
|--------|----------|---------|
| Granularity | Entire cluster | Selected tables |
| Standby queries | Yes (hot standby) | Subscriber is writable |
| DDL | Automatic | Manual |
| Version | Same major typically | Cross-major supported |
| Sequences | Replicated | **Not** replicated (use IDENTITY or sync) |

## Upgrade Pattern (PG 17 → 18)

1. Create logical publication on PG 17
2. Create subscription on PG 18 (`copy_data=true`)
3. Wait until caught up; cutover apps to PG 18

See [Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md).

## Monitor Lag

```sql
-- Publisher
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots WHERE slot_type = 'logical';

-- Subscriber
SELECT subname, received_lsn, latest_end_lsn, last_msg_receipt_time
FROM pg_stat_subscription;
```

## Drop Cleanly

```sql
ALTER SUBSCRIPTION app_sub DISABLE;
DROP SUBSCRIPTION app_sub;  -- drops remote slot if created by subscription
```

## Related

- [Streaming Replication](streaming-replication.md)
- [Upgrades](../09-maintenance/upgrades.md)
