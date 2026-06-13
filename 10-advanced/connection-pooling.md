# Connection Pooling (PgBouncer & pgpool)

PostgreSQL backends are **one process per connection** — expensive at scale. Connection poolers multiplex many clients onto fewer server connections.

## PgBouncer (Recommended)

Lightweight, single-purpose pooler.

### Install & Config

```ini
; /etc/pgbouncer/pgbouncer.ini
[databases]
app_db = host=127.0.0.1 port=5432 dbname=app_db

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 50
max_client_conn = 1000
reserve_pool_size = 10
server_reset_query = DISCARD ALL
```

### Pool Modes

| Mode | Connection held | Best for |
|------|-------------------|----------|
| session | Entire client session | Prepared statements, temp tables, SET |
| transaction | Single transaction | **Most OLTP apps** |
| statement | Single statement | Rare; breaks multi-statement tx |

### userlist.txt

```
"app_user" "SCRAM-SHA-256$4096:..."
```

Generate hash: `echo -n 'passwordapp_user' | md5sum` or use `pgbouncer` SCRAM from PG.

### Application Connection

```
postgresql://app_user:pass@pgbouncer-host:6432/app_db
```

**Note:** Transaction mode — no session-level `SET` without `SET LOCAL`; use `DISCARD ALL` on release.

## Pgpool-II

See [Patroni & pgpool](../05-replication-ha/patroni-pgpool.md) for HA + pooling combined.

## When to Pool

| Connections | Recommendation |
|-------------|----------------|
| < 100 | Direct to PostgreSQL often OK |
| 100–500 | PgBouncer transaction mode |
| 500+ | PgBouncer required; tune pool size |

## Pool Sizing

```
PostgreSQL max_connections = pool_size + admin + replication + buffer
default_pool_size ≈ (CPU cores × 2) to (CPU cores × 4) for OLTP
```

Too many server connections → context switching, memory pressure.

## Prepared Statements with Pooling

Transaction pooling breaks named prepared statements (connection reused).

Solutions:
- Use unnamed prepared statements
- Session pooling for ORMs that rely on prepares (PgBouncer 1.21+ supports prepare in tx mode)
- ORM setting: disable prepared statements

## Monitoring PgBouncer

```bash
psql -p 6432 -U pgbouncer pgbouncer
SHOW POOLS;
SHOW STATS;
SHOW CLIENTS;
SHOW SERVERS;
```

## RDS Proxy / Cloud Alternatives

Managed poolers with IAM auth integration — AWS RDS Proxy, Azure Connection Pooling (preview).

## Related

- [pg_ident.conf & Connections](../02-configuration/pg-ident-conf.md)
- [Tuning Parameters](../06-performance/tuning-parameters.md)
