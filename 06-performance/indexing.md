# Indexing Strategies

## Index Types

| Type | Best for | Operator class |
|------|----------|----------------|
| B-tree (default) | `=`, `<`, `>`, `BETWEEN`, `LIKE 'prefix%'` | default |
| Hash | Equality only | — |
| GIN | jsonb, arrays, full-text | `jsonb_ops`, `jsonb_path_ops` |
| GiST | Geometry, ranges, exclusion | varies |
| BRIN | Large sorted tables (timestamps) | minmax, bloom |
| SP-GiST | Text patterns, IP networks | — |

## Create Indexes

```sql
-- Standard
CREATE INDEX idx_orders_customer ON orders (customer_id);

-- Composite (column order matters)
CREATE INDEX idx_orders_cust_date ON orders (customer_id, created_at DESC);

-- Partial — index subset of rows
CREATE INDEX idx_orders_open ON orders (created_at)
  WHERE status IN ('pending', 'processing');

-- Expression
CREATE INDEX idx_users_lower_email ON users (lower(email));

-- Covering index (INCLUDE — PG 11+)
CREATE INDEX idx_orders_cover ON orders (customer_id) INCLUDE (total, status);

-- Concurrently (no write blocking — use in production)
CREATE INDEX CONCURRENTLY idx_orders_status ON orders (status);
```

## When to Index

- WHERE, JOIN, ORDER BY columns with high selectivity
- Foreign key columns (PostgreSQL does **not** auto-index FKs)
- Columns used in partial index predicates

## When NOT to Index

- Small tables (seq scan cheaper)
- Low selectivity (boolean flags) — use partial index instead
- Write-heavy tables with unused indexes

```sql
-- Find unused indexes
SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexrelname NOT LIKE '%pkey%'
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Duplicate / Redundant Indexes

```sql
-- idx (a,b) makes idx (a) redundant in many cases
SELECT indexrelid::regclass, indrelid::regclass, indkey
FROM pg_index JOIN pg_class ON indexrelid = pg_class.oid;
```

## Index Maintenance

```sql
REINDEX INDEX CONCURRENTLY idx_orders_status;
REINDEX TABLE CONCURRENTLY orders;   -- PG 12+
```

B-tree bloat: check with `pgstatindex`.

## Full-Text Search

```sql
ALTER TABLE articles ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))) STORED;

CREATE INDEX idx_articles_fts ON articles USING gin (search_vector);

SELECT * FROM articles WHERE search_vector @@ to_tsquery('english', 'postgresql & tuning');
```

## JSONB Indexing

```sql
CREATE INDEX idx_data_gin ON events USING gin (payload jsonb_path_ops);
SELECT * FROM events WHERE payload @> '{"type": "click"}';

CREATE INDEX idx_data_path ON events ((payload->>'user_id'));
```

## BRIN for Time-Series

```sql
CREATE INDEX idx_logs_time ON logs USING brin (logged_at)
  WITH (pages_per_range = 128);
```

Tiny index size vs. B-tree on billions of rows.

## Exclusion Constraints

```sql
CREATE EXTENSION btree_gist;
CREATE TABLE reservations (
  room_id int,
  during tstzrange,
  EXCLUDE USING gist (room_id WITH =, during WITH &&)
);
```

## Related

- [Query Optimization](query-optimization.md)
- [Partitioning](../10-advanced/partitioning.md)
