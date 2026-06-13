# Tablespaces

Tablespaces map database objects to specific filesystem locations — useful for tiered storage (NVMe for hot data, HDD for archive).

## Create Tablespace

```sql
CREATE TABLESPACE fast_ts LOCATION '/mnt/nvme/pg_ts';
CREATE TABLESPACE slow_ts LOCATION '/mnt/hdd/pg_archive';
```

**Requirements:**
- Directory must exist and be empty
- Owned by `postgres` OS user
- Must **not** be inside `$PGDATA`
- PostgreSQL needs read/write permissions

```bash
sudo mkdir -p /mnt/nvme/pg_ts
sudo chown postgres:postgres /mnt/nvme/pg_ts
sudo chmod 700 /mnt/nvme/pg_ts
```

## Assign Objects

```sql
-- New objects
CREATE TABLE hot_data (...) TABLESPACE fast_ts;
CREATE INDEX ON hot_data (col) TABLESPACE fast_ts;

-- Move existing
ALTER TABLE big_table SET TABLESPACE fast_ts;
ALTER INDEX big_table_pkey SET TABLESPACE fast_ts;

-- Database default for new objects
CREATE DATABASE analytics TABLESPACE slow_ts;
```

## Move All Objects (Maintenance)

```sql
-- Generate ALTER statements
SELECT format('ALTER TABLE %I.%I SET TABLESPACE fast_ts;',
              schemaname, tablename)
FROM pg_tables WHERE schemaname = 'public';
```

Moving large tables locks exclusively — plan maintenance window or use pg_repack.

## Monitor Usage

```sql
SELECT t.spcname,
       pg_tablespace_location(t.oid) AS location,
       pg_size_pretty(pg_tablespace_size(t.spcname)) AS size
FROM pg_tablespace t;

SELECT relname, reltablespace,
       pg_tablespace.spcname
FROM pg_class
JOIN pg_tablespace ON pg_class.reltablespace = pg_tablespace.oid
WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace;
```

## Drop Tablespace

```sql
-- Must be empty of objects first
DROP TABLESPACE fast_ts;
```

## Default Tablespaces

| OID | Name | Location |
|-----|------|----------|
| 1663 | pg_default | `$PGDATA/base` |
| 1664 | pg_global | `$PGDATA/global` |

## Cloud / Managed Postgres Note

Many managed services (RDS, Cloud SQL, Azure) **do not expose** tablespaces — use storage tier selection at instance level instead.

## Related

- [Cluster Management](cluster-management.md)
- [Performance Tuning](../06-performance/tuning-parameters.md)
