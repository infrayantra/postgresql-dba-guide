# pgAudit — Audit Logging Extension

**pgAudit** provides detailed session and object audit logging through PostgreSQL's standard logging — essential for compliance (PCI-DSS, HIPAA, SOC2, GDPR).

> See also [Auditing overview](../08-security/auditing.md) for trigger-based and logical decoding alternatives.

---

## What pgAudit Logs

| Class | Events |
|-------|--------|
| **READ** | SELECT, COPY FROM |
| **WRITE** | INSERT, UPDATE, DELETE, TRUNCATE, COPY TO |
| **DDL** | CREATE, ALTER, DROP |
| **ROLE** | GRANT, REVOKE, CREATE/ALTER/DROP ROLE |
| **FUNCTION** | FUNCTION/DO block execution |
| **MISC** | DISCARD, FETCH, CHECKPOINT, etc. |
| **MISC_SET** | SET, RESET |
| **ALL** | Everything above |

---

## Install

### RHEL / PGDG

```bash
sudo dnf install -y pgaudit18_18    # or postgresql18-pgaudit
```

### Debian / Ubuntu

```bash
sudo apt install -y postgresql-18-pgaudit
```

### Configure postgresql.conf

```ini
shared_preload_libraries = 'pgaudit,pg_stat_statements'

# Global defaults (adjust per environment)
pgaudit.log = 'write, ddl, role'
pgaudit.log_catalog = off              # reduce noise on system catalogs
pgaudit.log_parameter = on             # log bind parameters (PII risk — review)
pgaudit.log_relation = on              # log relation names
pgaudit.log_statement_once = on        # one log line per statement
pgaudit.log_level = log                # log | notice | warning
```

**Restart required** after `shared_preload_libraries` change.

### Enable in database

```sql
CREATE EXTENSION pgaudit;
```

Repeat for each database requiring audit, or add to `template1` for new DBs.

---

## Per-Role Audit Policies

Fine-grained control — audit app writes but not monitoring reads:

```sql
-- App user: audit writes only
ALTER ROLE app_user SET pgaudit.log = 'write';

-- DBA: audit everything
ALTER ROLE dba_admin SET pgaudit.log = 'all';

-- Read-only analyst: audit reads (heavy volume!)
ALTER ROLE analyst SET pgaudit.log = 'read';

-- Disable for replication user
ALTER ROLE replicator SET pgaudit.log = 'none';
```

Session override:

```sql
SET pgaudit.log = 'ddl';
CREATE TABLE audit_test (id int);
RESET pgaudit.log;
```

---

## Object-Level Audit

Audit specific tables only:

```sql
-- Audit all DML on sensitive table
ALTER TABLE customers SET (pgaudit.log = 'write');

-- Audit reads on PII table
ALTER TABLE payment_cards SET (pgaudit.log = 'read, write');
```

---

## Log Output Example

With `log_line_prefix` and CSV logging:

```ini
log_destination = 'csvlog'
logging_collector = on
log_directory = '/data/pglog'
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
```

Sample log line:

```
AUDIT: SESSION,WRITE,WRITE,"pg_catalog.pgaudit","public.orders",<not logged>,
  "INSERT INTO orders (customer_id, total) VALUES ($1, $2)",<not logged>
```

Ship CSV logs to SIEM: Splunk, ELK, Loki, CloudWatch.

---

## Production Configuration (Recommended)

```ini
# postgresql.conf — balanced compliance / volume
pgaudit.log = 'write, ddl, role'
pgaudit.log_catalog = off
pgaudit.log_parameter = off          # ON only if required — may log PII/passwords
pgaudit.log_relation = on
pgaudit.log_statement_once = on
log_connections = on
log_disconnections = on
```

```sql
-- Sensitive tables get explicit object audit
ALTER TABLE users SET (pgaudit.log = 'read, write');
ALTER TABLE audit_log SET (pgaudit.log = 'none');  -- avoid recursive noise
```

---

## HA / Patroni

Include pgaudit in Patroni bootstrap parameters:

```yaml
bootstrap:
  dcs:
    postgresql:
      parameters:
        shared_preload_libraries: "pgaudit,pg_stat_statements"
        pgaudit.log: "write, ddl, role"
```

After failover, audit config follows PostgreSQL config on new leader — verify `shared_preload_libraries` identical on all nodes.

---

## Cloud / Managed Postgres

| Platform | pgAudit |
|----------|---------|
| RDS PostgreSQL | `rds_pgaudit` in shared_preload + parameter group |
| Aurora | Similar to RDS |
| Azure Flexible | Extension available |
| Cloud SQL | Check audit alternatives (Cloud Audit Logs) |

**RDS example:**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name pg18-audit \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pgaudit,ApplyMethod=pending-reboot" \
    "ParameterName=pgaudit.log,ParameterValue=write,ddl,role,ApplyMethod=immediate"
```

```sql
CREATE EXTENSION pgaudit;
```

---

## Security Considerations

| Risk | Mitigation |
|------|------------|
| PII in `log_parameter` | Keep off unless mandated; mask in app |
| Log volume / disk fill | Log rotation + central shipping; audit READ selectively |
| Tampering | Ship logs off-host immediately; immutable storage (S3 Object Lock) |
| Superuser bypass | Audit ROLE class; restrict superuser; use pgAudit on all app roles |

---

## Verify pgAudit Active

```sql
SHOW shared_preload_libraries;
SHOW pgaudit.log;

CREATE TABLE pgaudit_test (id int);
INSERT INTO pgaudit_test VALUES (1);
DROP TABLE pgaudit_test;
-- Check log file for AUDIT lines
```

```bash
grep AUDIT /data/pglog/postgresql-*.log | tail -5
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| No AUDIT lines | Extension not created; library not preloaded; restart needed |
| Too verbose | Reduce `pgaudit.log`; set `log_catalog=off` |
| Role setting ignored | Check `ALTER ROLE ... SET pgaudit.log` |
| Extension missing after upgrade | Reinstall package; `ALTER EXTENSION pgaudit UPDATE` |

---

## Related

- [Auditing](../08-security/auditing.md)
- [Logging](../07-monitoring/logging.md)
- [Extensions Overview](extensions.md)
- [Row-Level Security](../08-security/row-level-security.md)
