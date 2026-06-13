# Authentication Methods

## Password Authentication (SCRAM-SHA-256)

Default in PG 18 (and PG 14+). Secure challenge-response; password never sent in clear. **MD5 is deprecated in PG 18** — migrate all roles to SCRAM.

```sql
SET password_encryption = 'scram-sha-256';
CREATE ROLE app_user LOGIN PASSWORD 'secure_password';
```

## OAuth 2.0 Authentication (PG 18+)

Native SSO integration via OAuth 2.0 bearer tokens — useful for enterprise identity providers.

```ini
# postgresql.conf
oauth_validator_libraries = 'oauth_validator'
```

```
# pg_hba.conf (method name and options per your validator library)
hostssl all all 0.0.0.0/0 oauth
```

Requires a loaded OAuth validator shared library and TLS. See [PostgreSQL 18 docs — OAuth](https://www.postgresql.org/docs/18/auth-oauth.html) and [postgresql-18.md](../01-getting-started/postgresql-18.md).

## MD5 Deprecation (PG 18+)

MD5 password authentication is **deprecated** and will be removed in a future major release.

```sql
-- Migrate roles to SCRAM
ALTER ROLE app_user PASSWORD 'new_password';  -- with password_encryption = scram-sha-256

-- Temporary: suppress deprecation warnings during migration
SET md5_password_warnings = off;
```

## Certificate Authentication

```ini
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'
```

```
# pg_hba.conf
hostssl all all 0.0.0.0/0 cert clientcert=verify-full
```

Generate certs with easy-rsa or cfssl. Client cert CN must map to PG role.

## LDAP / Active Directory

```
# pg_hba.conf
hostssl all all 0.0.0.0/0 ldap ldapserver=ldap.example.com ldapport=389
  ldapbasedn="dc=example,dc=com" ldapbinddn="cn=pg,dc=example,dc=com"
  ldapbindpasswd=secret ldapsearchattribute=uid
```

## GSSAPI / Kerberos

```
# pg_hba.conf
hostgssenc all all 0.0.0.0/0 gss include_realm=0
```

Requires Kerberos keytab for postgres service principal.

## Peer (Local Socket)

```
local all postgres peer
local all all peer map=appmap
```

OS username must match or map via pg_ident.conf.

## OAuth / External IdP

Not native — use:
- PgBouncer with auth_query + external auth
- Cloud IAM (RDS IAM auth, Cloud SQL IAM)
- pg_hba + custom auth extensions

## AWS RDS IAM Authentication

```bash
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname mydb.xxx.rds.amazonaws.com --port 5432 --username iam_user)
psql "host=mydb.xxx.rds.amazonaws.com sslmode=require user=iam_user dbname=postgres"
```

## Security Hardening Checklist

- [ ] SCRAM-SHA-256 for all password roles (MD5 deprecated in PG 18)
- [ ] TLS 1.2+ for all remote connections
- [ ] Revoke PUBLIC privileges on public schema (PG 15 default)
- [ ] Separate roles: app, migration, admin, replication, monitoring
- [ ] No superuser for applications
- [ ] Rotate credentials; use secrets manager
- [ ] Audit failed logins (`log_connections`)

## Related

- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
- [Encryption Overview](encryption.md)
- [SSL/TLS Implementation](ssl-tls-implementation.md)
- [TDE at Rest](tde-implementation.md)
- [Row-Level Security](row-level-security.md)
