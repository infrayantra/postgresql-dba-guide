# Cluster & Instance Management

## Service Control

```bash
# systemd (RHEL/Debian package installs)
sudo systemctl start postgresql-18
sudo systemctl stop postgresql-18
sudo systemctl restart postgresql-18
sudo systemctl reload postgresql-18   # SIGHUP — reload config

# pg_ctl (direct)
pg_ctl -D $PGDATA start
pg_ctl -D $PGDATA stop -m fast       # default; aborts active transactions
pg_ctl -D $PGDATA stop -m immediate  # crash-like; use only in emergency
pg_ctl -D $PGDATA stop -m smart      # wait for all clients to disconnect
pg_ctl -D $PGDATA reload
pg_ctl -D $PGDATA promote            # standby → primary
pg_ctl -D $PGDATA status
```

### Shutdown Modes

| Mode | Behavior |
|------|----------|
| smart | Wait for sessions to end |
| fast | Rollback active tx, disconnect clients |
| immediate | Abort; recovery on next start |

## Cluster Status

```sql
SELECT pg_is_in_recovery();           -- false = primary
SELECT pg_last_wal_receive_lsn(),     -- standby only
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();

SHOW server_version;
SHOW server_version_num;
SELECT current_setting('cluster_name');
```

```bash
# Is postmaster running?
pg_ctl -D $PGDATA status
cat $PGDATA/postmaster.pid
```

## Register Cluster (Debian/Ubuntu pg_createcluster)

```bash
pg_createcluster 18 main --port=5432
pg_ctlcluster 18 main start
pg_lsclusters
```

## Tablespaces

```sql
CREATE TABLESPACE faststorage LOCATION '/mnt/nvme/pgdata';
CREATE TABLE metrics (id int, val numeric) TABLESPACE faststorage;

-- Move existing table
ALTER TABLE big_table SET TABLESPACE faststorage;

SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;
```

Requirements: directory owned by `postgres`, empty, not inside `$PGDATA`.

## Database Maintenance Operations

```sql
-- Size overview
SELECT datname, pg_size_pretty(pg_database_size(datname))
FROM pg_database ORDER BY pg_database_size(datname) DESC;

-- Connection count per DB
SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;

-- Terminate idle sessions
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND state_change < now() - interval '1 hour'
  AND usename = 'app_user';

-- Cancel long query (graceful)
SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE pid = 12345;

-- Prevent new connections (maintenance window)
ALTER DATABASE app_db CONNECTION LIMIT 0;
UPDATE pg_database SET datallowconn = false WHERE datname = 'app_db';
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'app_db';
```

## Object Size Queries

```sql
-- Top tables
SELECT relname AS table,
       pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;

-- Index sizes
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC LIMIT 20;
```

## Scheduled Maintenance Window Script

```bash
#!/bin/bash
# maintenance.sh
set -e
DB=app_db

psql -d $DB -c "CHECKPOINT;"
psql -d $DB -c "VACUUM (VERBOSE, ANALYZE);"
psql -d $DB -c "REINDEX DATABASE CONCURRENTLY $DB;"  # PG 12+ — use per-index in prod
```

## Multi-Instance on One Host

Run separate clusters on different ports:

```bash
/usr/pgsql-18/bin/initdb -D /pgdata/18/app1 -U postgres
echo "port = 5433" >> /pgdata/18/app1/postgresql.conf
pg_ctl -D /pgdata/18/app1 start
```

Use `PGPORT` or `-p` to connect.

## Related

- [Production Cluster Layout](../03-administration/production-cluster-layout.md)
- [Users & Roles](user-roles.md)
- [Upgrades](../09-maintenance/upgrades.md)
- [Failover](../05-replication-ha/failover.md)
