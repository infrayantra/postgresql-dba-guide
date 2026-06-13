# Query Optimization & EXPLAIN

## EXPLAIN Basics

```sql
EXPLAIN SELECT * FROM orders WHERE customer_id = 123;

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.*, c.name
FROM orders o
JOIN customers c ON c.id = o.customer_id
WHERE o.created_at > now() - interval '30 days';
```

| Option | Purpose |
|--------|---------|
| ANALYZE | Actually runs query — real timings |
| BUFFERS | Shared/local block hits & reads |
| VERBOSE | Column details |
| WAL | WAL records generated (PG 13+) |
| SETTINGS | Modified planner settings |
| FORMAT JSON | Machine-readable for tools |

## Reading a Plan

```
Nested Loop  (cost=0.43..16.48 rows=1 width=100) (actual time=0.020..0.025 rows=1 loops=1)
  ->  Index Scan using orders_customer_idx on orders  (cost=0.43..8.45 rows=1 width=80)
        Index Cond: (customer_id = 123)
  ->  Index Scan using customers_pkey on customers  (cost=0.15..8.17 rows=1 width=20)
        Index Cond: (id = 123)
```

| Node | Meaning |
|------|---------|
| Seq Scan | Full table scan |
| Index Scan | Index lookup + heap fetch |
| Index Only Scan | Satisfied from index + VM |
| Bitmap Index/Heap Scan | Multiple index matches combined |
| Nested Loop | For each outer row, scan inner |
| Hash Join | Build hash on inner, probe outer |
| Merge Join | Sorted inputs merged |
| Sort | Explicit sort |
| Aggregate | GROUP BY / aggregates |

**Red flags:** Seq Scan on large tables, high actual vs. estimated rows, nested loop with huge outer rows.

## Fix Bad Estimates

```sql
ANALYZE orders;

-- Extended statistics
CREATE STATISTICS orders_stats (dependencies, ndistinct)
  ON customer_id, status FROM orders;
ANALYZE orders;

-- Increase stats target
ALTER TABLE orders ALTER COLUMN status SET STATISTICS 1000;
ANALYZE orders;
```

## Enable/Disable Plan Types (Testing)

```sql
SET enable_seqscan = off;   -- force index use (debug only)
SET enable_nestloop = off;
RESET ALL;
```

## pg_stat_statements

```sql
CREATE EXTENSION pg_stat_statements;

SELECT queryid, calls,
       round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

Reset stats: `SELECT pg_stat_statements_reset();`

## Common Optimizations

### 1. Missing Index

```sql
CREATE INDEX CONCURRENTLY ON orders (created_at) WHERE status = 'pending';
```

### 2. SELECT * Avoidance

Fetch only needed columns; enables index-only scans.

### 3. Pagination

```sql
-- Bad: OFFSET 100000
-- Better: keyset pagination
SELECT * FROM orders WHERE id > 100000 ORDER BY id LIMIT 50;
```

### 4. Function on Column

```sql
-- Bad: WHERE lower(email) = 'x@y.com'  (no index)
-- Good: WHERE email = 'X@Y.com' with functional index, or store normalized
```

### 5. OR Conditions

```sql
-- May need UNION ALL instead of OR for index use
SELECT * FROM t WHERE a = 1
UNION ALL
SELECT * FROM t WHERE b = 2 AND a <> 1;
```

## Join Order & Statistics

PostgreSQL chooses join order automatically. For complex queries:

```sql
-- PG 12+ explicit join order (CTE materialization changed PG 12)
WITH big AS MATERIALIZED (SELECT ... heavy ...)
SELECT ... FROM big JOIN ...;
```

## Prepared Statements

```sql
PREPARE get_order(bigint) AS SELECT * FROM orders WHERE id = $1;
EXECUTE get_order(123);
```

Generic vs. custom plans: `plan_cache_mode = force_custom_plan` for skewed params.

## auto_explain

```ini
shared_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '1s'
auto_explain.log_analyze = true
auto_explain.log_buffers = true
```

## Tools

- **explain.depesz.com** — visual EXPLAIN
- **pev2** — PostgreSQL Explain Visualizer
- **pgMustard** — plan analysis hints

## Related

- [Indexing](indexing.md)
- [Slow Queries](../11-troubleshooting/slow-queries.md)
- [pg_stat_statements](../07-monitoring/pg-stat-statements.md)
