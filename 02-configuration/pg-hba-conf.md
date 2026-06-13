# pg_hba.conf — Client Authentication

Controls **who** can connect, **from where**, to **which database**, using **which auth method**.

```sql
SHOW hba_file;
```

## Rule Format

```
TYPE  DATABASE  USER  ADDRESS  METHOD  [OPTIONS]
```

| Field | Values |
|-------|--------|
| TYPE | `local`, `host`, `hostssl`, `hostnossl`, `hostgssenc`, `hostnogssenc` |
| DATABASE | Name, `all`, `sameuser`, `samerole`, `replication` |
| USER | Name, `all`, `+group` |
| ADDRESS | IP/CIDR, `samehost`, `samenet` (host lines only) |
| METHOD | See below |

**First matching rule wins.** Order matters.

## Authentication Methods

| Method | Description |
|--------|-------------|
| `scram-sha-256` | **Recommended** password auth (PG 10+) |
| `md5` | Legacy password hash; upgrade to SCRAM |
| `password` | Plaintext over wire — avoid |
| `trust` | No password — **dev only** |
| `reject` | Deny connection |
| `peer` | Unix socket; OS user must match DB user |
| `ident` | RFC 1413 ident lookup |
| `cert` | TLS client certificate |
| `gss` / `sspi` | Kerberos / Windows SSPI |
| `ldap` | LDAP bind authentication |
| `radius` | RADIUS |
| `pam` | PAM modules |

## Example Configurations

### Development (Local Only)

```
local   all   all                 peer
host    all   all   127.0.0.1/32  scram-sha-256
host    all   all   ::1/128       scram-sha-256
```

### Production Application Server

```
# Reject all by default at end
hostssl all   all   0.0.0.0/0     reject

# App subnet
hostssl app_db  app_user  10.0.1.0/24  scram-sha-256

# Admin from bastion
hostssl all     dba_team  10.0.0.5/32  scram-sha-256

# Replication from standby
hostssl replication  replicator  10.0.2.10/32  scram-sha-256
```

### Certificate Authentication

```
hostssl all  all  10.0.0.0/8  cert  clientcert=verify-full
```

Requires mapping CN to DB user via `pg_ident.conf` or matching names.

## Replication Entries

```
# Physical replication
hostssl replication  replicator  10.0.2.0/24  scram-sha-256

# Logical replication (regular connection to database)
hostssl mydb  repl_user  10.0.2.0/24  scram-sha-256
```

## Reload After Changes

```bash
pg_ctl reload -D $PGDATA
# Invalid rules may prevent reload — test syntax carefully
```

## Upgrade Passwords to SCRAM

```sql
-- Check current hash type
SELECT rolname, rolpassword FROM pg_authid WHERE rolname = 'app_user';

ALTER ROLE app_user PASSWORD 'new_password';
-- password_encryption = scram-sha-256 (default in PG 18)
SHOW password_encryption;
```

```ini
# postgresql.conf — reject md5 after migration
password_encryption = scram-sha-256
```

## pg_hba.conf vs. pg_ident.conf

`pg_ident.conf` maps OS or cert names to PostgreSQL users:

```
# MAPNAME  SYSTEM-USERNAME  PG-USERNAME
mymap     john              john_db
mymap     jane              jane_db
```

```
# pg_hba.conf
local  all  all  peer  map=mymap
```

## Troubleshooting Auth Failures

```bash
# Check PostgreSQL log for:
# "password authentication failed for user"
# "no pg_hba.conf entry for host"
```

| Error | Cause |
|-------|-------|
| `no pg_hba.conf entry` | Missing or wrong IP/rule order |
| `password authentication failed` | Wrong password or wrong method |
| `certificate verify failed` | TLS/cert mismatch |
| `Peer authentication failed` | OS user ≠ PG user on local socket |

```sql
-- Test from psql
\c "host=db.example.com port=5432 dbname=app_db user=app_user sslmode=require"
```

## Security Best Practices

1. Use `hostssl` for all remote connections
2. Prefer `scram-sha-256` over `md5`
3. Narrow IP ranges; avoid `0.0.0.0/0`
4. Separate replication users with minimal privileges
5. Use `.pgpass` or connection pooler secrets — never embed passwords in apps in plaintext config repos
6. End rules with explicit `reject`
7. Implement TLS — see [SSL/TLS Implementation](ssl-tls-implementation.md)

## Related

- [Authentication](../08-security/authentication.md)
- [Encryption](../08-security/encryption.md)
- [pg_ident.conf](pg-ident-conf.md)
