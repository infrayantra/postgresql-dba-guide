# Capacity Planning — Disk, RAM & Connections

Sizing guidance for **PostgreSQL 18** production clusters: memory, disk, WAL, connections, and growth forecasting.

> See also: [Production Cluster Layout](production-cluster-layout.md) · [Tuning Parameters](../06-performance/tuning-parameters.md) · [In-Memory Features](../06-performance/in-memory-features-integration.md)

---

## Memory

### Rule of thumb (dedicated DB server)

```
shared_buffers       = 25% RAM (cap ~8–32 GB practical on Linux)
effective_cache_size = 50–75% RAM
maintenance_work_mem = 5–10% RAM (cap ~2–4 GB)
work_mem             = (RAM - shared_buffers) / (max_connections × 3)
```

| Workload | shared_buffers note |
|----------|---------------------|
| OLTP | 25% RAM |
| Analytics / large sorts | Lower shared_buffers, higher work_mem per role |
| Mixed | 25%; raise work_mem for reporting roles only |

### Container / K8s limits

```
memory limit ≥ shared_buffers + (max_connections × 10 MB) + 2 GB OS headroom
```

---

## Disk — PGDATA

### Estimate database size

```sql
SELECT pg_size_pretty(sum(pg_database_size(datname))) AS cluster_size
FROM pg_database;

SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;
```

### Growth planning

```
Required PGDATA disk = current_size × (1 + growth_rate)^years × 1.3
```

Factor **1.3** covers bloat, WAL transient files, temp files, and index growth.

| Component | Typical % of data |
|-----------|-------------------|
| Indexes | 50–100% of heap (varies) |
| TOAST | 5–20% for JSON/text heavy |
| Bloat headroom | 20–30% without pg_repack |

---

## Disk — WAL & Archive

| Item | Size driver |
|------|-------------|
| `pg_wal/` active | `max_wal_size` × 2–3 minimum free |
| Archive retention | WAL generated/day × retention days |
| Replication slots | Unarchived WAL if slot lagging |

```sql
-- WAL generation rate (approximate, reset stats periodically)
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));
SELECT * FROM pg_stat_archiver;
```

**Archive disk:**

```
archive_disk = daily_wal_gb × retention_days × 1.2
```

Example: 50 GB WAL/day, 30-day retention → ~1.8 TB archive storage.

---

## Disk — Backups

| Method | Space |
|--------|-------|
| pgBackRest full | ~100% database size (compressed ~30–70%) |
| pgBackRest incr/diff | 2–10% daily typical OLTP |
| pg_dump | Similar to DB; single file |

```
backup_disk = full_size × retention_full_copies + incremental_headroom
```

Off-site S3: use lifecycle policies; pgBackRest repo retention aligns with compliance.

---

## Disk — Logs

```
log_disk ≈ 100 MB – 2 GB/day depending on log_min_duration_statement and traffic
```

With `log_min_duration_statement = 1000` on OLTP: ~200–500 MB/day typical.

---

## Connections

| Pattern | Sizing |
|---------|--------|
| Direct to PostgreSQL | `max_connections` = peak app sessions + admin + replication |
| With PgBouncer | `max_connections` = pool_size + 20 overhead; clients unlimited at pooler |
| Replication | +1 per standby + walsender slots |
| pgBackRest / backup | +2 during backup |

```
PgBouncer default_pool_size ≈ (CPU_cores × 2) to (CPU_cores × 4)  # OLTP
PostgreSQL max_connections = pool_size + replication + 15% buffer
```

---

## CPU

| Cores | Guidance |
|-------|----------|
| 4–8 | Small OLTP, dev/staging |
| 8–16 | Production OLTP with replicas |
| 16–32 | Heavy analytics, parallel queries |
| 32+ | Warehouse, many parallel workers |

```ini
max_worker_processes = CPU cores
max_parallel_workers = CPU cores / 2
max_parallel_workers_per_gather = 2–4
```

---

## IOPS & Throughput

| Storage | random_page_cost | effective_io_concurrency |
|---------|------------------|--------------------------|
| HDD | 4.0 | 2–4 |
| SSD | 1.1–1.5 | 100–200 |
| NVMe | 1.1 | 200–1000 |

PG 18 `io_method = worker` improves sequential scan throughput on NVMe.

---

## Table: Single-Node Sizing Examples

| Profile | RAM | CPU | PGDATA disk | Archive (30d) |
|---------|-----|-----|-------------|---------------|
| Small app | 8 GB | 4 | 100 GB | 50 GB |
| Mid OLTP | 32 GB | 8 | 500 GB | 200 GB |
| Large OLTP | 64 GB | 16 | 2 TB | 1 TB |
| Analytics | 128 GB | 32 | 5 TB | 500 GB |

Adjust from measured `pg_database_size` and WAL/archive rates.

---

## Forecast Script (Monthly)

```sql
-- Save monthly for trending
SELECT now() AS captured_at,
       pg_size_pretty(sum(pg_database_size(datname))) AS total,
       sum(pg_database_size(datname)) AS bytes
FROM pg_database;
```

```bash
# Disk
df -h /data/pgdata /data/pgarchive /data/pglog /var/lib/pgbackrest
du -sh /data/pgdata/18
```

---

## Related

- [Production Cluster Layout](production-cluster-layout.md)
- [Tablespaces](tablespaces.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
- [DBA Health Checks](../07-monitoring/dba-health-checks.md)
