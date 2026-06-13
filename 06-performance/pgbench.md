# pgbench — Load Testing & Benchmarking

**pgbench** ships with PostgreSQL client tools. Use it to measure **TPS**, **latency**, and regression-test tuning changes on **PostgreSQL 18**.

> Binary path (RHEL PGDG): `/usr/pgsql-18/bin/pgbench`

---

## When to Use pgbench

| Scenario | Approach |
|----------|----------|
| Baseline after install | Default TPC-B-like workload |
| Before/after tuning | Same scale factor, clients, duration |
| HA failover impact | Run during/after Patroni switchover |
| PG version upgrade | Compare PG 17 vs PG 18 on identical hardware |
| Connection pool sizing | Sweep `-c` with PgBouncer in front |

**Not for:** realistic application query mixes — use custom scripts or tools like HammerDB, sysbench, or replay from `pg_stat_statements`.

---

## Quick Start

```bash
# Create test database
createdb -h localhost -p 5432 pgbench_test

# Initialize schema (creaters pgbench_accounts, branches, tellers, history)
pgbench -i -s 50 pgbench_test
# -s 50 ≈ 7.5M rows in pgbench_accounts (~1 GB data)

# Run 60-second benchmark: 10 clients, 2 threads
pgbench -c 10 -j 2 -T 60 pgbench_test
```

Sample output:

```
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 50
query mode: simple
number of clients: 10
number of threads: 2
duration: 60 s
number of transactions actually processed: 45231
latency average = 13.245 ms
initial connection time = 8.412 ms
tps = 753.821 (without initial connection time)
```

---

## Initialize (`-i`) Options

```bash
pgbench -i \
  -s 100 \              # scale factor (rows in accounts = 100000 × s)
  --fillfactor=90 \     # leave page headroom like production tables
  --unlogged \          # faster init; tables not crash-safe
  --foreign-keys \      # add FK constraints (more realistic, slower)
  pgbench_test
```

| Scale factor | ~accounts rows | ~DB size |
|--------------|----------------|----------|
| 10 | 1M | ~150 MB |
| 50 | 5M | ~750 MB |
| 100 | 10M | ~1.5 GB |
| 1000 | 100M | ~15 GB |

```sql
-- Verify init
SELECT relname, n_live_tup, pg_size_pretty(pg_total_relation_size(oid))
FROM pg_stat_user_tables
JOIN pg_class USING (relname)
WHERE schemaname = 'public' AND relname LIKE 'pgbench%';
```

---

## Run Options

### Duration vs transaction count

```bash
pgbench -c 32 -j 8 -T 300 pgbench_test    # 5 minutes
pgbench -c 32 -j 8 -t 10000 pgbench_test  # exactly 10k xacts per client
```

### Client / thread tuning

```bash
# Rule: threads ≤ CPU cores; clients = expected concurrent sessions
pgbench -c 64 -j 16 -T 120 pgbench_test
```

### Connection modes

```bash
pgbench --protocol=simple pgbench_test   # default; one query per round trip
pgbench --protocol=extended pgbench_test # parse/bind/execute (PgBouncer friendly)
pgbench --protocol=prepared pgbench_test # prepared statements
```

Use **`extended`** or **`prepared`** when benchmarking through PgBouncer in transaction pooling mode.

### Rate limiting

```bash
# Cap at 500 TPS (useful for steady load tests)
pgbench -c 20 -j 4 -T 60 --rate=500 pgbench_test
```

### Progress reporting

```bash
pgbench -c 16 -j 4 -T 300 -P 5 pgbench_test   # report every 5 seconds
```

### Logging

```bash
pgbench -c 10 -j 2 -T 60 -l pgbench_test
# Creates pgbench_log.NNN with per-transaction latency (ms)
```

Analyze latencies:

```bash
sort -n pgbench_log.123 | awk '
  { a[NR]=$1; sum+=$1 }
  END {
    print "count", NR, "avg", sum/NR
    print "p50", a[int(NR*0.50)]
    print "p95", a[int(NR*0.95)]
    print "p99", a[int(NR*0.99)]
  }'
```

---

## Custom Workloads

### Single SQL file

```bash
cat > /tmp/select_only.sql <<'EOF'
\set aid random(1, 100000 * :scale)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
EOF

pgbench -c 20 -j 4 -T 60 -f /tmp/select_only.sql -n pgbench_test
# -n = no vacuum/analyze between runs
```

### Weighted transaction mix

```bash
cat > /tmp/read.sql <<'EOF'
\set aid random(1, 100000 * :scale)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
EOF

cat > /tmp/write.sql <<'EOF'
\set aid random(1, 100000 * :scale)
\set delta random(-5000, 5000)
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
END;
EOF

pgbench -c 32 -j 8 -T 120 \
  -f /tmp/read.sql@8 \
  -f /tmp/write.sql@2 \
  pgbench_test
# @8 @2 = 80% reads, 20% writes
```

### Built-in variables

| Variable | Meaning |
|----------|---------|
| `:scale` | Init scale factor |
| `:client_id` | Client number |
| `random(min, max)` | Inclusive random integer |
| `random(1, 100000 * :scale)` | Standard account key range |

---

## Benchmark Methodology (Production-Safe)

1. **Never run heavy pgbench on production** without change window — use a clone or staging cluster.
2. **Warm cache:** run a short throwaway test before the measured run.
3. **Fix variables:** same `-s`, `-c`, `-j`, `-T`, hardware, `postgresql.conf`.
4. **Reset stats** between A/B tests:

```sql
SELECT pg_stat_reset_shared('bgwriter');
SELECT pg_stat_reset();
-- Or restart cluster for clean buffer state
```

5. **Capture context:**

```bash
pgbench -c 32 -j 8 -T 300 -P 10 pgbench_test 2>&1 | tee pgbench_$(date +%Y%m%d).log
```

```sql
-- During run
SELECT * FROM pg_stat_database WHERE datname = 'pgbench_test';
SELECT * FROM pg_stat_bgwriter;
SELECT * FROM pg_aios;   -- PG 18 AIO activity
```

---

## Tuning Experiments with pgbench

### Before/after shared_buffers

```bash
# Baseline
pgbench -c 32 -j 8 -T 180 pgbench_test | tee before.txt

# After ALTER SYSTEM SET shared_buffers = '8GB'; restart
pgbench -c 32 -j 8 -T 180 pgbench_test | tee after.txt
```

### PG 18 AIO comparison

```ini
# Test 1
io_method = none
# Test 2
io_method = worker
```

Run identical pgbench after cold restart; compare TPS and `pg_stat_io`.

### Connection pool comparison

```bash
# Direct to PostgreSQL
pgbench -h pg-primary -c 100 -j 8 -T 120 pgbench_test

# Through PgBouncer (transaction mode)
pgbench -h pgbouncer -p 6432 -c 500 -j 8 -T 120 --protocol=extended pgbench_test
```

---

## HA Failover Test Pattern

```bash
# Terminal 1 — continuous load
pgbench -h haproxy-vip -p 5000 -c 20 -j 4 -T 600 -P 5 pgbench_test

# Terminal 2 — trigger failover (Patroni example)
patronictl switchover --master pg-node1 --candidate pg-node2
```

Watch for latency spikes and connection errors during promotion.

---

## Interpreting Results

| Metric | Good sign | Investigate if |
|--------|-----------|----------------|
| **tps** | Stable across run | Drops after warmup (checkpoint, autovacuum) |
| **latency average** | Low vs SLA | Spikes at `-P` intervals |
| **initial connection time** | < 50 ms | High with SSL or many `-c` |
| **failed transactions** | 0 | Any failures — check logs |

Cross-check with:

```sql
SELECT query, calls, mean_exec_time, stddev_exec_time
FROM pg_stat_statements
WHERE query LIKE '%pgbench%'
ORDER BY mean_exec_time DESC;
```

(requires `shared_preload_libraries = 'pg_stat_statements'`)

---

## Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `ERROR: relation "pgbench_accounts" does not exist` | Not initialized | `pgbench -i` |
| TPS flatlines low | Disk-bound cold cache | Warm run; check `pg_stat_io` |
| `too many clients` | `-c` > `max_connections` | Lower clients or raise limit / use PgBouncer |
| Different results each run | Autovacuum, checkpoint | `-n` flag; longer `-T`; disable autovacuum on test DB only |
| SSL overhead | `-h` with `sslmode=require` | Expected; compare with/without for planning |

---

## Cleanup

```bash
dropdb pgbench_test
# Or keep for regression suite
```

---

## Related

- [In-Memory Features & Integration](in-memory-features-integration.md)
- [Tuning Parameters](tuning-parameters.md)
- [Query Optimization](query-optimization.md)
- [pg_stat_statements](../07-monitoring/pg-stat-statements.md)
- [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md)
