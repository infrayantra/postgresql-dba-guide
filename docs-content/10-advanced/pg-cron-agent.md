# pg_cron & pgAgent — Job Scheduling

PostgreSQL does not include a built-in job scheduler. Use **pg_cron** (recommended, in-cluster) or **pgAgent** (legacy GUI-driven) to run SQL on a schedule.

---

## Comparison

| Feature | pg_cron | pgAgent |
|---------|---------|---------|
| Maintainer | Citus / Microsoft | pgAdmin project |
| Install | Extension in PostgreSQL | Separate daemon |
| Schedule | Cron syntax in SQL | GUI / SQL in `pgagent` DB |
| Runs as | Background worker in postmaster | External agent process |
| PG 18 | Supported via PGDG package | Check compatibility |
| Best for | Vacuum, partition maintenance, reports | Legacy environments |

**Recommendation:** Use **pg_cron** for new deployments on **PostgreSQL 18**.

---

## pg_cron

Runs jobs inside PostgreSQL using cron expressions (`minute hour dom month dow`).

### Install (RHEL / PGDG)

```bash
sudo dnf install -y pg_cron_18    # package name may vary: pg_cron_18 or postgresql18-pg-cron
```

### Configure postgresql.conf

```ini
shared_preload_libraries = 'pg_cron,pg_stat_statements'
cron.database_name = 'postgres'    # database where cron schema lives
cron.timezone = 'UTC'
cron.log_run = on
cron.log_statement = on
cron.max_running_jobs = 8
```

**Restart required** after changing `shared_preload_libraries`.

### Enable extension

```sql
CREATE EXTENSION pg_cron;
\c postgres
SELECT cron.schedule_in_database('test-job', '* * * * *', 'SELECT 1', 'postgres');
```

### Schedule examples

```sql
-- Nightly VACUUM on hot table (02:00 UTC daily)
SELECT cron.schedule(
  'vacuum-orders',
  '0 2 * * *',
  $$VACUUM (VERBOSE, ANALYZE) public.orders$$
);

-- Every 5 minutes — refresh materialized view
SELECT cron.schedule(
  'refresh-daily-sales',
  '*/5 * * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY reporting.daily_sales$$
);

-- Weekly partition maintenance (Sunday 03:00)
SELECT cron.schedule(
  'partman-maint',
  '0 3 * * 0',
  $$SELECT partman.run_maintenance('public.events')$$
);

-- Monthly report — first day of month
SELECT cron.schedule(
  'monthly-report',
  '0 6 1 * *',
  $$CALL reporting.generate_monthly_summary()$$
);
```

### Manage jobs

```sql
-- List jobs
SELECT jobid, schedule, command, nodename, active FROM cron.job ORDER BY jobid;

-- Job run history
SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 20;

-- Unschedule
SELECT cron.unschedule('vacuum-orders');
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobid = 5;

-- Disable without dropping
UPDATE cron.job SET active = false WHERE jobid = 5;
```

### Security

- Jobs run as the **user who scheduled them** (or superuser)
- Restrict who can call `cron.schedule`:

```sql
REVOKE ALL ON SCHEMA cron FROM PUBLIC;
GRANT USAGE ON SCHEMA cron TO dba_role;
```

- Do not store secrets in job SQL — use `SET app.settings` or vault-backed functions

### HA / Patroni note

pg_cron runs on the **primary only** (background workers on leader). After failover, jobs continue on the new primary — no duplicate runs on replicas.

Verify after failover:

```sql
SELECT * FROM cron.job WHERE active;
```

### Docker / Kubernetes

Add to `postgresql.conf` command args or ConfigMap; include `pg_cron` in image (PGDG package or custom Dockerfile).

---

## pgAgent

External job scheduler historically bundled with pgAdmin.

### Install (RHEL)

```bash
sudo dnf install -y pgagent_18
sudo systemctl enable --now pgagent-18
```

### Setup

1. Create `pgagent` extension database (often `postgres` or dedicated DB)
2. Connect with pgAdmin → **Management → pgAgent**
3. Create schedules, steps, and job classes

### SQL alternative

```sql
CREATE EXTENSION pgagent;
-- Jobs stored in pgagent.pga_job, pga_schedule, pga_jobstep tables
```

### When to use pgAgent

- Existing pgAdmin-centric ops team
- Complex multi-step jobs with branching
- Windows-heavy environments

For greenfield Linux/PG 18 clusters, prefer pg_cron.

---

## External Schedulers (Alternative)

| Tool | Pattern |
|------|---------|
| **cron + psql** | `0 2 * * * psql -c "VACUUM ANALYZE;"` |
| **systemd timers** | Unit files calling psql |
| **Kubernetes CronJob** | `psql` in container against service |
| **Airflow / Prefect** | ETL orchestration |
| **Patroni pause** | Avoid failover during long maintenance jobs |

```bash
# /etc/cron.d/pg-maintenance
0 2 * * * postgres psql -h 127.0.0.1 -p 5432 -d app_db -c "VACUUM (ANALYZE) public.orders;"
```

---

## Monitoring pg_cron

```sql
-- Failed jobs in last 24h
SELECT jobid, command, return_message, start_time
FROM cron.job_run_details
WHERE status = 'failed'
  AND start_time > now() - interval '24 hours';

-- Alert query for postgres_exporter custom check
SELECT count(*) AS failed_cron_jobs
FROM cron.job_run_details
WHERE status = 'failed' AND start_time > now() - interval '1 hour';
```

---

## Related

- [Extensions Overview](extensions.md)
- [VACUUM & ANALYZE](../09-maintenance/vacuum-analyze.md)
- [Partitioning](partitioning.md)
- [Patroni HA](../05-replication-ha/postgresql-18-ha-setup-runbook.md)
