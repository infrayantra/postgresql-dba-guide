# Row-Level Security (RLS)

Restrict which rows users see/modify based on policy expressions.

## Enable RLS

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- applies to table owner too
```

Without policies, **no rows** are visible to non-owner/non-superuser.

## Create Policies

```sql
-- Tenant isolation
CREATE POLICY tenant_isolation ON orders
  FOR ALL
  TO app_user
  USING (tenant_id = current_setting('app.tenant_id')::int)
  WITH CHECK (tenant_id = current_setting('app.tenant_id')::int);

-- Read-only analyst
CREATE POLICY analyst_read ON orders
  FOR SELECT
  TO analyst
  USING (created_at > now() - interval '90 days');

-- Manager sees own team
CREATE POLICY manager_team ON employees
  FOR ALL
  TO manager
  USING (department_id = (SELECT department_id FROM employees WHERE id = current_user_id()));
```

## Set Session Context

```sql
SET app.tenant_id = '42';
-- or in connection startup:
ALTER ROLE app_user SET app.tenant_id = '42';  -- rarely — usually set per session
```

Application must set context on each connection (or use `SET LOCAL` in transaction).

## Policy Types

| Command | Clauses |
|---------|---------|
| SELECT | USING |
| INSERT | WITH CHECK |
| UPDATE | USING + WITH CHECK |
| DELETE | USING |
| ALL | Both |

## Bypass RLS

```sql
ALTER ROLE admin BYPASSRLS;
-- Superusers always bypass unless FORCE ROW LEVEL SECURITY
```

## Inspect Policies

```sql
\d+ orders
SELECT * FROM pg_policies WHERE tablename = 'orders';
```

## Performance

Policies add predicates to every query — **index policy columns**.

```sql
CREATE INDEX ON orders (tenant_id);
```

Use `EXPLAIN` to verify policy filters use indexes.

## Multi-Tenant Patterns

| Pattern | Implementation |
|---------|----------------|
| Shared table + tenant_id | RLS on tenant_id |
| Schema per tenant | Separate schemas, connection routing |
| DB per tenant | Database-level isolation |

RLS is ideal for shared-table multi-tenancy.

## Related

- [User Roles](../03-administration/user-roles.md)
- [Auditing](auditing.md)
