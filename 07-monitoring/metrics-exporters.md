# Prometheus / Grafana Exporters

## postgres_exporter (Most Common)

```bash
# Download from prometheuscommunity/postgres_exporter
export DATA_SOURCE_NAME="postgresql://monitor:pass@localhost:5432/postgres?sslmode=disable"
./postgres_exporter --web.listen-address=:9187
```

### Recommended Custom Queries

Place in `queries.yaml`:

```yaml
pg_replication:
  query: |
    SELECT client_addr, state,
           pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
    FROM pg_stat_replication
  metrics:
    - client_addr: { usage: LABEL }
      state: { usage: LABEL }
      replay_lag_bytes: { usage: GAUGE }

pg_stat_user_tables:
  query: |
    SELECT schemaname, relname, n_live_tup, n_dead_tup, seq_scan, idx_scan
    FROM pg_stat_user_tables
  metrics:
    - schemaname: { usage: LABEL }
      relname: { usage: LABEL }
      n_live_tup: { usage: GAUGE }
      n_dead_tup: { usage: GAUGE }
      seq_scan: { usage: COUNTER }
      idx_scan: { usage: COUNTER }
```

### Monitor User

```sql
CREATE USER monitor PASSWORD '...';
GRANT pg_monitor TO monitor;
-- PG 10+: pg_monitor role includes most stats access
```

## Key Metrics to Dashboard

| Metric | Source | Alert threshold |
|--------|--------|-----------------|
| Replication lag (bytes/time) | pg_stat_replication | > 100MB or > 30s |
| Connections | pg_stat_activity count | > 80% max_connections |
| Cache hit ratio | pg_stat_database | < 95% |
| Dead tuples | pg_stat_user_tables | rising unchecked |
| Long running queries | pg_stat_activity | > statement_timeout |
| Disk usage | node_exporter + du | > 85% |
| XID age | pg_database | > 500M |
| Archive failures | pg_stat_archiver | failed_count > 0 |
| Lock waits | pg_locks | blocked > 60s |

## Grafana Dashboards

Import community dashboards:
- **Dashboard ID 9628** — PostgreSQL Database
- **Dashboard ID 12485** — PostgreSQL Exporter Quickstart

Use `generate_deeplink` when sharing with team (if Grafana MCP available).

## pgwatch2

Alternative all-in-one monitoring (InfluxDB/Prometheus + Grafana):

```bash
docker compose up pgwatch2
```

Auto-discovers metrics, preset dashboards.

## pganalyze

SaaS — query performance, EXPLAIN plans, index recommendations. Agent on DB host.

## Cloud Native

| Platform | Monitoring |
|----------|------------|
| AWS RDS/Aurora | CloudWatch, Performance Insights |
| GCP Cloud SQL | Cloud Monitoring, Query Insights |
| Azure Flexible | Azure Monitor, Query Store |
| Crunchy Bridge | Built-in Grafana |

## Alertmanager Example

```yaml
- alert: PostgresReplicationLag
  expr: pg_replication_replay_lag_bytes > 1e8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "PG replication lag > 100MB"
```

## Related

- [Knowledge Base Index](../INDEX.md)
- [DBA Health Checks](dba-health-checks.md)
- [System Catalogs](system-catalogs.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
- [pg_stat_statements](pg-stat-statements.md)
