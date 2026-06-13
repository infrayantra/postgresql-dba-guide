# pg_ident.conf & Connection Settings

## pg_ident.conf

Maps external user names (OS username, TLS certificate CN) to PostgreSQL role names.

```sql
SHOW ident_file;
```

### Format

```
MAPNAME       SYSTEM-USERNAME    PG-USERNAME
```

### Example

```
# pg_ident.conf
devmap    postgres           admin
devmap    ubuntu             app_user
certmap   /.*@example.com     \1   # regex capture (PG 12+)
```

```
# pg_hba.conf
local   all   all                    peer map=devmap
hostssl all   all   0.0.0.0/0        cert  map=certmap
```

## Connection Service File (~/.pg_service.conf)

Avoid embedding credentials in scripts:

```ini
[myapp]
host=db.example.com
port=5432
dbname=app_db
user=app_user
# password in .pgpass, not here ideally
```

```bash
psql service=myapp
pg_dump service=myapp -Fc -f backup.dump
```

## Password File (~/.pgpass)

```
hostname:port:database:username:password
```

```bash
chmod 600 ~/.pgpass

# Wildcards
*:*:app_db:app_user:secretpass
```

## libpq Connection Parameters

| Parameter | Example | Notes |
|-----------|---------|-------|
| `host` | `db.example.com` | |
| `port` | `5432` | |
| `dbname` | `mydb` | |
| `user` | `app_user` | |
| `sslmode` | `verify-full` | disable/allow/prefer/require/verify-ca/verify-full |
| `sslrootcert` | `/path/ca.crt` | |
| `sslcert` | `/path/client.crt` | |
| `sslkey` | `/path/client.key` | |
| `connect_timeout` | `10` | seconds |
| `application_name` | `my-app` | Shows in pg_stat_activity |
| `options` | `-c statement_timeout=30s` | |

### SSL Modes

| Mode | Encrypted | Verifies CA | Verifies hostname |
|------|-----------|-------------|-------------------|
| disable | No | — | — |
| require | Yes | No | No |
| verify-ca | Yes | Yes | No |
| verify-full | Yes | Yes | Yes |

## JDBC / Application Connection Strings

```
postgresql://user:pass@host:5432/db?sslmode=verify-full&application_name=billing-service
```

## Timeouts (postgresql.conf or per-session)

```ini
statement_timeout = 30s
lock_timeout = 10s
idle_in_transaction_session_timeout = 5min
tcp_keepalives_idle = 60
tcp_keepalives_interval = 10
```

```sql
ALTER ROLE app_user SET statement_timeout = '60s';
```

## max_connections Planning

```
app_connections + admin + replication_slots + overhead ≤ max_connections
```

Use **PgBouncer** when app servers open many connections:

```
100 app servers × 20 pool size = 2000 client connections
→ PgBouncer with pool_mode=transaction, default_pool_size=50
→ PostgreSQL max_connections=100
```

## Related

- [pg_hba.conf](pg-hba-conf.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
