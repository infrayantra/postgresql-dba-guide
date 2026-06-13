# Table Partitioning

Split large tables into smaller physical pieces for manageability and query performance.

## Declarative Partitioning (PG 10+)

### Range Partitioning (Time-Series)

```sql
CREATE TABLE measurements (
  id bigint GENERATED ALWAYS AS IDENTITY,
  sensor_id int NOT NULL,
  recorded_at timestamptz NOT NULL,
  value numeric NOT NULL
) PARTITION BY RANGE (recorded_at);

CREATE TABLE measurements_2025_06
  PARTITION OF measurements
  FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');

CREATE TABLE measurements_2025_07
  PARTITION OF measurements
  FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');

CREATE TABLE measurements_default
  PARTITION OF measurements DEFAULT;
```

### List Partitioning

```sql
CREATE TABLE orders (
  id bigint,
  region text NOT NULL,
  total numeric
) PARTITION BY LIST (region);

CREATE TABLE orders_us PARTITION OF orders FOR VALUES IN ('US', 'CA');
CREATE TABLE orders_eu PARTITION OF orders FOR VALUES IN ('UK', 'DE', 'FR');
```

### Hash Partitioning

```sql
CREATE TABLE events (...)
PARTITION BY HASH (tenant_id);

CREATE TABLE events_p0 PARTITION OF events FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE events_p1 PARTITION OF events FOR VALUES WITH (MODULUS 4, REMAINDER 1);
-- p2, p3 ...
```

## Partition Pruning

Planner skips irrelevant partitions when WHERE matches partition key:

```sql
EXPLAIN SELECT * FROM measurements
WHERE recorded_at >= '2025-06-15' AND recorded_at < '2025-06-16';
-- Only scans measurements_2025_06
```

Requires `constraint_exclusion = partition` (default on).

## Indexes on Partitioned Tables

```sql
CREATE INDEX ON measurements (sensor_id);
-- Creates index on each partition automatically
```

## Attach / Detach

```sql
-- Pre-create table matching structure
CREATE TABLE measurements_2025_08 (LIKE measurements INCLUDING ALL);
ALTER TABLE measurements ATTACH PARTITION measurements_2025_08
  FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');

-- Archive old partition
ALTER TABLE measurements DETACH PARTITION measurements_2024_01;
-- export, drop, or move to cold storage
```

## Partition Maintenance Automation

Use **pg_partman** extension:

```sql
CREATE EXTENSION pg_partman;
SELECT partman.create_parent(
  p_parent_table => 'public.measurements',
  p_control => 'recorded_at',
  p_type => 'native',
  p_interval => 'monthly'
);
```

## When to Partition

| Good candidates | Poor candidates |
|-----------------|-----------------|
| Time-series (>100M rows) | Small tables |
| Archival retention policies | Heavy cross-partition joins |
| Sliding window deletes (detach drop) | No query pattern on partition key |

## Related

- [Indexing](../06-performance/indexing.md)
- [Query Optimization](../06-performance/query-optimization.md)
