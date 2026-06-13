# Users, Roles & Privileges

PostgreSQL uses a unified **role** model — `CREATE USER` is an alias for `CREATE ROLE ... LOGIN`.

## Create Roles

```sql
-- Login role (application)
CREATE ROLE app_user LOGIN PASSWORD 'secure_pass' CONNECTION LIMIT 50;

-- Group role (no login)
CREATE ROLE read_only NOLOGIN;
CREATE ROLE read_write NOLOGIN;

-- Inherit group permissions
GRANT read_only TO app_user;
GRANT read_write TO deploy_user;

-- Superuser (avoid for apps)
CREATE ROLE admin LOGIN SUPERUSER PASSWORD '...';

-- Replication
CREATE ROLE replicator LOGIN REPLICATION PASSWORD '...';
```

## Privilege Hierarchy

```
CLUSTER → DATABASE → SCHEMA → TABLE/COLUMN → ROW (RLS)
```

## Database-Level

```sql
GRANT CONNECT ON DATABASE app_db TO app_user;
REVOKE CONNECT ON DATABASE app_db FROM PUBLIC;
```

## Schema-Level

```sql
GRANT USAGE ON SCHEMA public TO app_user;
GRANT CREATE ON SCHEMA app TO app_user;
```

## Table & Column

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

-- Column-level
GRANT SELECT (id, name) ON customers TO analyst;
```

## Role Attributes

| Attribute | Meaning |
|-----------|---------|
| SUPERUSER | Bypass all permission checks |
| CREATEDB | Create databases |
| CREATEROLE | Create/alter roles |
| REPLICATION | Streaming/ logical replication |
| LOGIN | Can connect |
| BYPASSRLS | Bypass row-level security |
| CONNECTION LIMIT | Max concurrent sessions |

```sql
ALTER ROLE app_user SET statement_timeout = '30s';
ALTER ROLE app_user VALID UNTIL '2026-12-31';
```

## Predefined Roles (PG 14+)

```sql
GRANT pg_read_all_data TO analyst;
GRANT pg_write_all_data TO etl_user;
GRANT pg_monitor TO monitoring;
GRANT pg_read_all_settings TO monitoring;
GRANT pg_read_all_stats TO monitoring;
GRANT pg_stat_scan_tables TO monitoring;
GRANT pg_signal_backend TO ops;  -- cancel queries
```

## Membership & SET ROLE

```sql
GRANT read_write TO app_user;
SET ROLE read_write;
-- run DDL/DML with group privileges
RESET ROLE;
```

## Inspect Privileges

```sql
-- Table privileges
\dp mytable
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'orders';

-- Role attributes
\du+
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin FROM pg_roles;
```

## Application User Pattern (Least Privilege)

```sql
CREATE ROLE app_migrator LOGIN PASSWORD '...';  -- DDL only in CI
CREATE ROLE app_runtime LOGIN PASSWORD '...';   -- DML only

REVOKE ALL ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA app TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE app_migrator IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_runtime;
```

## Password Policies

```sql
SHOW password_encryption;  -- scram-sha-256

-- Expire password
ALTER ROLE app_user VALID UNTIL '2025-12-31';

-- Lock by removing login
ALTER ROLE compromised_user NOLOGIN;
```

## Drop Role Safely

```sql
-- Reassign owned objects
REASSIGN OWNED BY old_user TO new_user;
DROP OWNED BY old_user;
DROP ROLE old_user;
```

## Related

- [Row-Level Security](../08-security/row-level-security.md)
- [Authentication](../08-security/authentication.md)
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
