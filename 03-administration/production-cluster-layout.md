# Production Cluster Layout — Greenfield Setup

End-to-end checklist for standing up a **production PostgreSQL 18** cluster: paths, config, backup, replication, security, and monitoring. Use as a runbook for new on-prem or VM deployments.

> **HA stack:** [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md) · **Paths:** [Data Directory](../02-configuration/data-directory.md) · [Archive & Backup](../02-configuration/backup-archive-directories.md) · [Logs](../02-configuration/log-directory.md)

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Application tier                          │
│              ──► PgBouncer :6432 (transaction pool)              │
└───────────────────────────────┬─────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
  ┌───────────┐          ┌───────────┐          ┌───────────┐
  │ pg-node1  │  WAL     │ pg-node2  │          │ pg-node3  │
  │ PRIMARY   │────────►│ STANDBY   │          │ STANDBY   │
  └─────┬─────┘          └───────────┘          └───────────┘
        │
        ├── /data/pgdata/18/      PGDATA
        ├── /data/pgarchive/      WAL archive (PITR)
        ├── /data/pgbackup/       pg_basebackup / manual
        ├── /data/pglog/          PostgreSQL logs
        └── /var/lib/pgbackrest/  pgBackRest repo (or S3)
```

Single-node production (no HA) uses the same path layout; add streaming replica when RTO/RPO requires it.

---

## Phase 1 — OS & Storage

```bash
# Dedicated volumes (example)
/data/pgdata     # SSD/NVMe — PGDATA
/data/pgarchive  # SSD or fast HDD — WAL archive
/data/pglog      # any — logs
/data/pgbackup   # HDD or NFS — base backups

# Packages (RHEL PGDG)
sudo dnf install postgresql18-server postgresql18-contrib pgbackrest pgbouncer

# OS tuning
sudo tee /etc/sysctl.d/99-postgresql.conf <<'EOF'
vm.swappiness = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
sudo sysctl -p /etc/sysctl.d/99-postgresql.conf

# Disable THP (Linux)
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

---

## Phase 2 — initdb & Paths

```bash
sudo mkdir -p /data/pgdata/18 /data/pgarchive /data/pglog /data/pgbackup
sudo chown postgres:postgres /data/pgdata/18 /data/pgarchive /data/pglog /data/pgbackup
sudo chmod 700 /data/pgdata/18

sudo -u postgres /usr/pgsql-18/bin/initdb \
  -D /data/pgdata/18 \
  -E UTF8 --locale=en_US.UTF-8 --data-checksums

# systemd PGDATA (RHEL drop-in)
sudo mkdir -p /etc/systemd/system/postgresql-18.service.d
echo -e '[Service]\nEnvironment=PGDATA=/data/pgdata/18' | \
  sudo tee /etc/systemd/system/postgresql-18.service.d/pgdata.conf
sudo systemctl daemon-reload
```

---

## Phase 3 — postgresql.conf (Production Baseline)

Edit `/data/pgdata/18/postgresql.conf` or `conf.d/production.conf`:

```ini
# Identity
cluster_name = 'prod-main'
port = 5432
listen_addresses = '*'

# Memory (example: 64 GB RAM)
shared_buffers = 16GB
effective_cache_size = 48GB
work_mem = 64MB
maintenance_work_mem = 2GB
huge_pages = try

# Connections — app goes through PgBouncer
max_connections = 200
superuser_reserved_connections = 5

# WAL & durability
wal_level = replica              # use logical if logical replication needed
max_wal_size = 8GB
min_wal_size = 2GB
checkpoint_completion_target = 0.9
wal_compression = on

# Archive (PITR)
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_timeout = 300

# Replication
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 1GB
hot_standby = on

# PG 18 I/O
io_method = worker
effective_io_concurrency = 200
random_page_cost = 1.1

# Logging
logging_collector = on
log_directory = '/data/pglog'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_line_prefix = '%t [%p]: user=%u,db=%d,app=%a,client=%h '
log_timezone = 'UTC'
log_connections = on
log_disconnections = on
log_checkpoints = on
log_lock_waits = on
log_min_duration_statement = 1000
log_autovacuum_min_duration = 0

# Security
ssl = on
ssl_cert_file = '/etc/postgresql/ssl/server.crt'
ssl_key_file = '/etc/postgresql/ssl/server.key'
password_encryption = scram-sha-256

# Monitoring
shared_preload_libraries = 'pg_stat_statements,auto_explain'
track_io_timing = on
```

```sql
CREATE EXTENSION pg_stat_statements;
```

---

## Phase 4 — pg_hba.conf

```
# TYPE   DATABASE   USER        ADDRESS         METHOD
local    all        postgres                    peer
hostssl  all        all         10.0.0.0/8      scram-sha-256
hostssl  replication replicator 10.0.0.0/8      scram-sha-256
hostssl  all        all         127.0.0.1/32    scram-sha-256
```

See [pg_hba.conf](pg-hba-conf.md) and [TLS](../08-security/ssl-tls-implementation.md).

---

## Phase 5 — pgBackRest

```ini
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=14
repo1-retention-archive-type=time
repo1-retention-archive=30
process-max=4
compress-type=zst
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<from-vault>

[main]
pg1-path=/data/pgdata/18
pg1-port=5432
```

```bash
sudo systemctl restart postgresql-18
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main check
sudo -u postgres pgbackrest --stanza=main --type=full backup
```

---

## Phase 6 — Replication User & Standby (Optional)

```sql
CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD '...';
SELECT pg_create_physical_replication_slot('standby1');
```

On standby node:

```bash
sudo -u postgres pg_basebackup -h pg-node1 -U replicator \
  -D /data/pgdata/18 -Fp -Xs -P -R -S standby1
sudo systemctl start postgresql-18
```

---

## Phase 7 — PgBouncer

```ini
[databases]
app_db = host=127.0.0.1 port=5432 dbname=app_db

[pgbouncer]
listen_port = 6432
pool_mode = transaction
default_pool_size = 50
max_client_conn = 1000
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
```

Apps connect to `:6432`, not `:5432`.

---

## Phase 8 — Application Database & Roles

```sql
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_user LOGIN PASSWORD '...';
GRANT app_owner TO app_user;

CREATE DATABASE app_db OWNER app_owner ENCODING 'UTF8';
\c app_db
CREATE SCHEMA app AUTHORIZATION app_owner;
ALTER ROLE app_user SET search_path TO app, public;
ALTER ROLE app_user SET statement_timeout = '30s';
ALTER ROLE app_user SET idle_in_transaction_session_timeout = '60s';
```

See [Users & Roles](../03-administration/user-roles.md).

---

## Phase 9 — Verify & Sign-Off Checklist

### Cluster health

- [ ] `pg_isready` returns accepting connections
- [ ] `SHOW data_directory` = `/data/pgdata/18`
- [ ] `SHOW archive_mode` = `on`
- [ ] `pg_stat_archiver.failed_count` = 0
- [ ] `pgbackrest --stanza=main check` OK
- [ ] SSL enforced in `pg_hba.conf`
- [ ] SCRAM passwords (no MD5)

### Backup & DR

- [ ] Full pgBackRest backup completed
- [ ] PITR drill to isolated host (see [PITR](../04-backup-recovery/point-in-time-recovery.md))
- [ ] Archive retention ≥ RPO policy
- [ ] Runbook documented in [DC/DR Drill](../04-backup-recovery/dc-dr-drill.md)

### HA (if applicable)

- [ ] Standby `pg_is_in_recovery()` = true
- [ ] Replication lag < SLA
- [ ] Failover tested (Patroni switchover or manual)
- [ ] Replication slots monitored

### Monitoring

- [ ] `pg_stat_statements` enabled
- [ ] Logs in `/data/pglog`
- [ ] Alerts: disk, connections, archive failures, replication lag
- [ ] [DBA health checks](../07-monitoring/dba-health-checks.md) scheduled

### Security

- [ ] Least-privilege roles
- [ ] No superuser for apps
- [ ] Firewall: 5432 internal only; 6432 for apps
- [ ] [Encryption](../08-security/encryption-methods.md) reviewed

---

## Sizing Quick Reference

| RAM | shared_buffers | effective_cache_size | max_connections (direct) |
|-----|----------------|----------------------|--------------------------|
| 8 GB | 2 GB | 6 GB | 50–100 |
| 32 GB | 8 GB | 24 GB | 100–200 |
| 64 GB | 16 GB | 48 GB | 200 + PgBouncer |
| 128 GB | 32 GB | 96 GB | 200 + PgBouncer |

See [Capacity Planning](capacity-planning.md) and [Tuning](../06-performance/tuning-parameters.md).

---

## Related

- [Capacity Planning](capacity-planning.md)
- [DBA Runbook Checklists](../09-maintenance/dba-runbook-checklists.md)
- [Logical vs Physical](../01-getting-started/logical-vs-physical.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
