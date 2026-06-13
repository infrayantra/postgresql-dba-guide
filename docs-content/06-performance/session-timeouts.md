# Session & Timeout Tuning

Prevent runaway queries, idle transactions, and lock pile-ups on **PostgreSQL 18** production clusters.

> See also: [postgresql.conf](../02-configuration/postgresql-conf.md) · [Connection Pooling](../10-advanced/connection-pooling.md) · [Locking](../10-advanced/locking-concurrency.md)

---

## Key Parameters

| Parameter | Scope | Default | Purpose |
|-----------|-------|---------|---------|
| `statement_timeout` | Session/role/db | 0 (off) | Kill queries exceeding duration |
| `lock_timeout` | Session | 0 | Fail if lock not acquired in time |
| `idle_in_transaction_session_timeout` | Session | 0 | Kill idle sessions inside open tx |
| `idle_session_timeout` | Session | 0 | Kill idle sessions (PG 14+, not in tx) |
| `transaction_timeout` | Session | 0 | Max transaction duration (PG 17+) |

All accept ms suffix: `'30s'`, `'5000'`, `'1min'`.

---

## Recommended Production Defaults

```ini
# postgresql.conf — global safety net
statement_timeout = 0              # off globally; set per role
lock_timeout = 0
idle_in_transaction_session_timeout = 0
idle_session_timeout = 0
```

```sql
-- Application role
ALTER ROLE app_user SET statement_timeout = '30s';
ALTER ROLE app_user SET lock_timeout = '5s';
ALTER ROLE app_user SET idle_in_transaction_session_timeout = '60s';

-- Reporting / batch (higher limits)
ALTER ROLE analyst SET statement_timeout = '30min';
ALTER ROLE analyst SET lock_timeout = '30s';

-- Migration role (change window only)
ALTER ROLE migrator SET statement_timeout = '0';
ALTER ROLE migrator SET lock_timeout = '10s';
```

---

## statement_timeout

Aborts running query after limit.

```sql
SET statement_timeout = '5s';
SELECT pg_sleep(10);   -- ERROR: canceling statement due to statement timeout
```

**PgBouncer note:** In transaction pooling, use role-level `ALTER ROLE ... SET` so each server connection inherits settings.

---

## lock_timeout

Prevents indefinite wait on locks.

```sql
SET lock_timeout = '3s';
BEGIN;
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;  -- fails fast if blocked
```

Useful for online DDL with fallback:

```sql
SET lock_timeout = '2s';
ALTER TABLE orders ADD COLUMN foo int;  -- retry if fails
```

---

## idle_in_transaction_session_timeout

Kills sessions that hold a transaction open without activity — **critical for OLTP**.

```sql
ALTER ROLE app_user SET idle_in_transaction_session_timeout = '60s';
```

Common app bug: open transaction after SELECT, connection returned to pool with tx open → blocks vacuum, holds locks.

Monitor:

```sql
SELECT pid, usename, state, xact_start, state_change,
       now() - xact_start AS tx_age, left(query, 60)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_start;
```

---

## idle_session_timeout (PG 14+)

Closes completely idle connections (not in transaction). Use for leaked connections.

```sql
ALTER ROLE app_user SET idle_session_timeout = '10min';
```

---

## transaction_timeout (PG 17+)

Hard cap on total transaction wall time including locks and idle.

```sql
ALTER ROLE app_user SET transaction_timeout = '5min';
```

---

## Session vs Global

```sql
-- Session override
SET LOCAL statement_timeout = '120s';  -- transaction-scoped with SET LOCAL

-- Check effective value
SELECT name, setting, unit, source
FROM pg_settings
WHERE name LIKE '%timeout%';
```

Priority: session > role > database > global.

---

## PgBouncer Integration

```ini
; pgbouncer.ini
server_idle_timeout = 600
client_idle_timeout = 0
query_timeout = 0        ; prefer PG statement_timeout
```

Transaction mode resets session state — rely on `ALTER ROLE ... SET` not session `SET` in app.

---

## Monitoring

```sql
SELECT pid, usename, state, wait_event,
       now() - query_start AS query_age,
       left(query, 80)
FROM pg_stat_activity
WHERE state = 'active' AND query_start < now() - interval '30 seconds';
```

Alert on log pattern: `canceling statement due to statement timeout` spike → tune query or raise role limit.

---

## Related

- [Cluster Management](../03-administration/cluster-management.md)
- [Investigation Runbook](../11-troubleshooting/investigation-runbook.md)
- [Slow Queries](../11-troubleshooting/slow-queries.md)
