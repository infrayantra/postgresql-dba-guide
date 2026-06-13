# Auditing & Compliance

## pgAudit Extension

> **Full guide:** [pgAudit (dedicated doc)](../10-advanced/pgaudit.md)

Industry standard for detailed audit logging.

```ini
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'write, ddl, role'
pgaudit.log_catalog = off
pgaudit.log_parameter = on
pgaudit.log_relation = on
pgaudit.log_statement_once = on
```

```sql
CREATE EXTENSION pgaudit;

-- Role-specific audit
ALTER ROLE app_user SET pgaudit.log = 'write';
```

Logs appear in PostgreSQL log — ship to SIEM (Splunk, ELK, CloudWatch).

## Native Logging Audit Trail

```ini
log_statement = 'ddl'        # or 'mod' for DML
log_connections = on
log_disconnections = on
log_line_prefix = '%t [%p]: %u@%d '
```

## Trigger-Based Audit

```sql
CREATE TABLE audit_log (
  id bigserial PRIMARY KEY,
  table_name text,
  operation text,
  old_data jsonb,
  new_data jsonb,
  changed_by text DEFAULT current_user,
  changed_at timestamptz DEFAULT now()
);

CREATE OR REPLACE FUNCTION audit_trigger_fn() RETURNS trigger AS $$
BEGIN
  INSERT INTO audit_log (table_name, operation, old_data, new_data)
  VALUES (TG_TABLE_NAME, TG_OP,
          CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
          CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_audit
  AFTER INSERT OR UPDATE OR DELETE ON orders
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_fn();
```

## Logical Decoding for Change Capture

Stream changes to external systems (Debezium, Kafka):

```sql
SELECT pg_create_logical_replication_slot('audit_slot', 'pgoutput');
-- Use Debezium PostgreSQL connector
```

## Compliance Checklist

| Requirement | Implementation |
|-------------|----------------|
| Who accessed what | pgAudit + connection logging |
| Data changes | Triggers or logical decoding |
| Retention | Log archive policy (1–7 years per regulation) |
| Encryption | TLS + disk encryption |
| Least privilege | Role separation, RLS |
| Backup audit | pgBackRest logs, backup test records |

## PCI / HIPAA / SOC2 Notes

- Disable `trust` authentication
- Encrypt data in transit and at rest
- Regular access reviews (`\du`, `pg_policies`)
- Monitor superuser usage
- Document break-glass procedures

## Query Audit Tables

```sql
SELECT changed_by, operation, count(*)
FROM audit_log
WHERE changed_at > now() - interval '24 hours'
GROUP BY changed_by, operation;
```

## Related

- [Logging](../07-monitoring/logging.md)
- [Row-Level Security](row-level-security.md)
- [Authentication](authentication.md)
