# Major Version Upgrade Guide

Complete reference for upgrading PostgreSQL from an **older major version** to a **newer major version** (e.g. PG 14 → 18). Minor upgrades (18.0 → 18.2) are covered at the end.

> **Rule:** You cannot `yum update` across major versions. Major upgrades require **pg_upgrade**, **logical dump/restore**, or **logical replication**.

---

## Upgrade Methods at a Glance

| Method | Downtime | Speed (large DB) | Cross many versions | Rollback | Best for |
|--------|----------|------------------|---------------------|----------|----------|
| **pg_upgrade** | Minutes–hours | Fast | One jump at a time* | Hard with `--link` | TB-scale, same host |
| **pg_dump / pg_restore** | Hours–days | Slow | Any (dump from old, restore to new) | Easy (keep old cluster) | < 500 GB, schema changes |
| **pg_dumpall** | Hours–days | Slow | Full cluster migration | Easy | Small multi-DB clusters |
| **Logical replication** | Seconds–minutes cutover | Medium setup | Publisher ≥ PG 10 | Keep publisher | Near-zero downtime |
| **Cloud wizard / DMS** | Varies | Varies | Provider-dependent | Snapshots | RDS, Cloud SQL, Azure |

*pg_upgrade supports **one major version jump** per run (14→15, 15→16). For 14→18, either chain upgrades or use dump/replication.

---

## Which Method Should You Use?

```
START: Current version? Target version? Downtime budget?
│
├─ Same major, newer minor (18.0 → 18.2)
│   └─► Package update + restart (see Minor Upgrades below)
│
├─ One major jump (17 → 18), TB database, hours downtime OK
│   └─► pg_upgrade (--check first)
│
├─ Multiple major jumps (13 → 18)
│   ├─ Chain: 13→14→15→16→17→18 via pg_upgrade (painful)
│   ├─ Better: pg_dump from 13, restore to 18
│   └─ Best (large + low downtime): logical replication 13→18 if supported
│
├─ Need schema cleanup during migration
│   └─► pg_dump / pg_restore
│
├─ Near-zero downtime, large database
│   └─► Logical replication cutover
│
└─ Managed cloud (RDS / Cloud SQL / Azure)
    └─► Provider major version upgrade OR DMS migration
```

### Size & Downtime Guidelines

| Database size | Acceptable downtime | Recommended |
|---------------|---------------------|---------------|
| < 50 GB | 1–4 hours | pg_dump or pg_upgrade |
| 50 GB – 1 TB | 2–8 hours | pg_upgrade |
| 1 TB – 10 TB | pg_upgrade with `--link` or logical replication |
| > 10 TB | Minutes cutover | Logical replication + brief lock |
| Any (cloud) | Provider SLA | RDS modify / DMS / read replica promote |

---

## Pre-Upgrade Checklist (All Methods)

Run on the **source (old) cluster** before any migration.

### 1. Document Current State

```sql
SELECT version();
SHOW data_directory;
SHOW data_checksums;
SHOW server_encoding;
SHOW lc_collate;
SHOW lc_ctype;

SELECT name, setting FROM pg_settings
WHERE source != 'default'
ORDER BY name;
```

```bash
# Save config files
cp $PGDATA/postgresql.conf /backup/pre-upgrade/
cp $PGDATA/pg_hba.conf /backup/pre-upgrade/
```

### 2. Health Checks

```sql
-- Extensions (must exist on target version)
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- Invalid indexes/constraints
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
SELECT conrelid::regclass, conname FROM pg_constraint WHERE NOT convalidated;

-- Prepared transactions (block pg_upgrade)
SELECT * FROM pg_prepared_xacts;

-- Replication slots (note for cutover)
SELECT slot_name, slot_type, active FROM pg_replication_slots;

-- Large objects, orphan issues — pg_upgrade --check will report

-- Role/password hash types (migrate MD5 before PG 18)
SELECT rolname,
       CASE WHEN rolpassword LIKE 'SCRAM-SHA-256%' THEN 'scram'
            WHEN rolpassword LIKE 'md5%' THEN 'md5'
            ELSE 'other' END AS hash_type
FROM pg_authid WHERE rolcanlogin;
```

### 3. Full Backup (Mandatory)

```bash
# Physical — for rollback
pg_basebackup -h localhost -U replicator -D /backup/pre-upgrade-base -Fp -Xs -P

# Logical — always have this regardless of method
pg_dumpall -h localhost -U postgres -f /backup/pre-upgrade-$(date +%F).sql
pg_dump -Fc -h localhost -U postgres -d app_db -f /backup/app_db-$(date +%F).dump
```

### 4. Test in Staging

1. Clone production (backup restore or replica)
2. Run full upgrade procedure on staging
3. Run application regression tests
4. Compare query plans (`EXPLAIN`) for top 20 queries from `pg_stat_statements`
5. Measure downtime window

### 5. Extension Compatibility

Check each extension's release notes for target PG version. Common blockers:

| Extension | Notes |
|-----------|-------|
| postgis | Must install matching version on new PG before pg_upgrade |
| pg_stat_statements | Reinstall in shared_preload_libraries on new cluster |
| timescaledb | Strict version matrix — check docs |
| oracle_fdw, mysql_fdw | Rebuild for new PG major |
| pg_cron | Version-specific packages |

---

## Method 1: pg_upgrade (Step-by-Step)

Upgrades data files in place to new major version format. **One major version per run.**

### Requirements

- Old and new binaries installed (e.g. `/usr/pgsql-17/bin` and `/usr/pgsql-18/bin`)
- Same locale/encoding on new initdb
- **Matching `data_checksums`** — PG 18 defaults ON; old cluster without checksums needs `--no-data-checksums` on new initdb
- No prepared transactions
- Compatible extensions installed for **new** version

### RHEL / Rocky / Alma Example: PG 17 → 18

```bash
# ── 1. Install new version (keep old running until cutover) ──
sudo dnf install -y postgresql18-server postgresql18-contrib

# ── 2. Stop old cluster ──
sudo systemctl stop postgresql-17

# ── 3. Initialize NEW cluster ──
# Check old checksum setting first:
sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D /var/lib/pgsql/17/data status 2>/dev/null || true
OLD_CHECKSUMS=$(sudo -u postgres psql -tAc "SHOW data_checksums" 2>/dev/null || echo "off")

if [ "$OLD_CHECKSUMS" = "on" ]; then
  sudo -u postgres /usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data \
    --encoding=UTF8 --locale=en_US.UTF-8
else
  # PG 18 defaults checksums ON — must disable to match old cluster
  sudo -u postgres /usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data \
    --encoding=UTF8 --locale=en_US.UTF-8 --no-data-checksums
fi

# ── 4. Install extensions in NEW cluster (before pg_upgrade) ──
sudo systemctl start postgresql-18
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
sudo systemctl stop postgresql-18

# ── 5. Dry run ──
cd /var/lib/pgsql
sudo -u postgres /usr/pgsql-18/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-17/bin \
  --new-bindir=/usr/pgsql-18/bin \
  --old-datadir=/var/lib/pgsql/17/data \
  --new-datadir=/var/lib/pgsql/18/data \
  --check

# Review output — fix ALL errors before proceeding

# ── 6. Production run ──
# Option A: COPY mode (safer rollback — needs 2x disk temporarily)
sudo -u postgres /usr/pgsql-18/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-17/bin \
  --new-bindir=/usr/pgsql-18/bin \
  --old-datadir=/var/lib/pgsql/17/data \
  --new-datadir=/var/lib/pgsql/18/data \
  --verbose

# Option B: LINK mode (fast, minimal disk — hard rollback)
# SNAPSHOT FILESYSTEM FIRST
sudo -u postgres /usr/pgsql-18/bin/pg_upgrade \
  ... --link

# Option C: SWAP mode (PG 18+) — exchanges directories
# Read PG 18 release notes; understand implications
sudo -u postgres /usr/pgsql-18/bin/pg_upgrade \
  ... --swap
```

### Debian / Ubuntu Example: PG 17 → 18

```bash
sudo apt install -y postgresql-18 postgresql-client-18

sudo systemctl stop postgresql@17-main

sudo pg_createcluster 18 main --port=5433   # temp port during upgrade

cd /tmp
sudo -u postgres pg_upgrade \
  --old-bindir=/usr/lib/postgresql/17/bin \
  --new-bindir=/usr/lib/postgresql/18/bin \
  --old-datadir=/var/lib/postgresql/17/main \
  --new-datadir=/var/lib/postgresql/18/main \
  --old-options '-c config_file=/etc/postgresql/17/main/postgresql.conf' \
  --new-options '-c config_file=/etc/postgresql/18/main/postgresql.conf' \
  --check

sudo -u postgres pg_upgrade ...   # without --check

sudo pg_dropcluster 17 main
sudo pg_ctlcluster 18 main restart
```

### Post pg_upgrade Scripts

```bash
cd /var/lib/pgsql   # directory where pg_upgrade was run

# Regenerate optimizer stats (PG 18 preserves stats — still run to validate)
./analyze_new_cluster.sh

# Optional: delete old cluster after validation period (days/weeks)
# ./delete_old_cluster.sh
```

### Start New Cluster & Verify

```bash
sudo systemctl enable --now postgresql-18

sudo -u postgres psql <<'SQL'
SELECT version();
SHOW data_checksums;
SELECT count(*) FROM pg_database;
SELECT extname, extversion FROM pg_extension;
SQL
```

### pg_upgrade Mode Comparison

| Mode | Disk space | Speed | Rollback |
|------|------------|-------|----------|
| Default (copy) | ~2× database size | Moderate | Old datadir intact |
| `--link` | Minimal extra | Fast | Requires snapshot; old files are hard links |
| `--swap` (PG 18+) | Minimal | Fast | Read docs carefully |

---

## Method 2: pg_dump / pg_restore (Logical)

Works for **any version gap** (e.g. PG 12 → 18). Slower but safest and allows schema changes.

### Full Cluster (roles + globals + all DBs)

```bash
# On OLD server
pg_dumpall -h old-host -U postgres -f cluster_$(date +%F).sql

# On NEW server (PG 18 installed, empty cluster)
psql -U postgres -f cluster_$(date +%F).sql
```

### Single Database (Recommended — parallel)

```bash
# Export from OLD
pg_dump -h old-host -U postgres -Fd -j 4 -f app_db_dump app_db

# Import to NEW
pg_restore -h new-host -U postgres -d app_db -j 4 --no-owner --role=app_user app_db_dump

# Or create DB first
createdb -h new-host -U postgres -O app_user app_db
pg_restore -h new-host -U postgres -d app_db -j 4 app_db_dump
```

### Schema Only + Data Separate (large DBs)

```bash
pg_dump -s -Fc -f schema.dump app_db          # DDL first
pg_restore -d app_db schema.dump

pg_dump -a -Fc -f data.dump app_db            # data only
pg_restore -d app_db --disable-triggers data.dump
```

### What pg_dump Does NOT Include

- `postgres` database local customizations (usually fine)
- Tablespace location mappings (recreate manually)
- Replication slots, subscriptions (recreate on new cluster)
- Some extension objects — verify after restore

### Post-Restore on New Version

```sql
ANALYZE;
ALTER EXTENSION postgis UPDATE;
ALTER EXTENSION pg_stat_statements UPDATE;

-- Resequence if needed
SELECT setval(pg_get_serial_sequence('orders','id'),
              (SELECT max(id) FROM orders));
```

---

## Method 3: Logical Replication (Minimal Downtime)

Best for **large databases** where dump/restore takes too long and pg_upgrade downtime is unacceptable.

### Supported Version Pairs

Logical replication requires **PG 10+** on publisher. Cross-major works (e.g. PG 14 publisher → PG 18 subscriber).

### Setup: PG 17 Publisher → PG 18 Subscriber

**On OLD (publisher):**

```sql
ALTER SYSTEM SET wal_level = logical;
SELECT pg_reload_conf();   -- or restart if needed

CREATE ROLE repl_user REPLICATION LOGIN PASSWORD 'secure_pass';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO repl_user;

CREATE PUBLICATION upgrade_pub FOR ALL TABLES IN SCHEMA public;
-- or specific tables: FOR TABLE orders, customers, ...
```

```
# pg_hba.conf on publisher
hostssl app_db repl_user 10.0.2.0/24 scram-sha-256
```

**On NEW (subscriber — PG 18):**

```sql
-- Create matching schema/table structure first (pg_dump -s) OR let copy_data create tables

CREATE SUBSCRIPTION upgrade_sub
  CONNECTION 'host=old-primary port=5432 dbname=app_db user=repl_user password=... sslmode=require'
  PUBLICATION upgrade_pub
  WITH (copy_data = true, create_slot = true, slot_name = upgrade_slot);
```

**Monitor sync:**

```sql
-- Publisher
SELECT slot_name, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots WHERE slot_name = 'upgrade_slot';

-- Subscriber
SELECT subname, received_lsn, latest_end_lsn,
       now() - last_msg_receipt_time AS apply_lag
FROM pg_stat_subscription;
```

### Cutover (Minutes of Downtime)

```bash
# 1. Stop application writes to OLD primary
# 2. Wait for lag = 0
# 3. Verify row counts match
# 4. Drop subscription (or disable)
# 5. Point application to NEW PG 18 cluster
# 6. Run ANALYZE, verify sequences, recreate jobs/slots
```

```sql
-- On subscriber after cutover
ALTER SUBSCRIPTION upgrade_sub DISABLE;
DROP SUBSCRIPTION upgrade_sub;   -- drops slot on publisher if owned by subscription

-- Sequences are NOT replicated — sync manually
SELECT setval('orders_id_seq', (SELECT max(id) FROM orders));
```

### Limitations

- Sequences not replicated — sync at cutover
- Large objects — use `--large-objects` in pg_dump or replicate separately
- DDL during migration — must apply to both sides or refresh subscription
- Truncate on publisher can cause resync issues

---

## Multi-Hop Upgrades (Old → Latest)

When source is **several majors behind** (e.g. PG 12 → 18):

### Option A: Chain pg_upgrade (Same Server)

```bash
# 12 → 13 → 14 → 15 → 16 → 17 → 18
# Each hop: install new major, initdb, pg_upgrade, validate, repeat
# Time-consuming but no full dump of multi-TB data each hop
```

### Option B: Direct Logical (Recommended for PG 12–14 sources)

```bash
pg_dump -Fd -j 8 -h pg12-host -f dump_dir app_db
pg_restore -j 8 -h pg18-host -d app_db dump_dir
```

### Option C: Logical Replication (PG 10+ sources)

Single hop to PG 18 subscriber regardless of intermediate versions.

### End-of-Life Urgency

| Version | EOL | Action |
|---------|-----|--------|
| PG 12 | Nov 2024 | Upgrade immediately |
| PG 13 | Nov 2025 | Upgrade to 16+ or 18 |
| PG 14 | Nov 2026 | Plan upgrade to 17/18 |

---

## Version-Specific Breaking Changes (When Upgrading Through)

Review release notes for **every major** you cross. Critical items:

### Crossing PG 15

```sql
-- PUBLIC schema: apps may lose CREATE privilege
GRANT CREATE ON SCHEMA public TO app_user;   -- if needed (security review first)

-- COPY FROM program restricted
GRANT pg_read_server_files TO etl_user;      -- if using COPY FROM file
```

### Crossing PG 16

- Reconfigure logical decoding on standbys if used
- Update monitoring for `pg_stat_all_tables` column changes

### Crossing PG 17

- Review vacuum memory behavior changes
- Test JSON_TABLE if used

### Crossing PG 18

```sql
-- Checksums: new initdb defaults ON
SHOW data_checksums;

-- MD5 → SCRAM migration
ALTER ROLE each_login_user PASSWORD 'same_or_new_password';

-- Reindex FTS/pg_trgm if using ICU collation provider
-- REINDEX INDEX CONCURRENTLY idx_fts;

-- VACUUM behavior: processes partition children by default
-- Use VACUUM ONLY parent_table for old behavior
```

---

## Post-Upgrade Tasks (All Methods)

```sql
-- 1. Update extensions
ALTER EXTENSION postgis UPDATE;
ALTER EXTENSION pg_stat_statements UPDATE;

-- 2. Refresh statistics
ANALYZE;
-- PG < 18 upgrades: essential. PG 18 pg_upgrade: verify but often already good

-- 3. Reindex if pg_upgrade warned
REINDEX DATABASE CONCURRENTLY app_db;   -- or targeted indexes

-- 4. Verify constraints
SELECT conrelid::regclass, conname FROM pg_constraint WHERE NOT convalidated;

-- 5. Update configs
-- Merge old postgresql.conf settings into new version's config
-- New GUCs may have different defaults — diff the files

-- 6. Vacuum freeze
VACUUM (VERBOSE, ANALYZE);

-- 7. Application smoke tests
-- Connection pools, prepared statements, ORM migrations

-- 8. Monitoring baselines
SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

### Config Migration

```bash
# Compare old vs new default settings
/usr/pgsql-18/bin/postgres -C shared_buffers -D /var/lib/pgsql/18/data

# Settings removed or renamed — check release notes
diff /backup/pre-upgrade/postgresql.conf /var/lib/pgsql/18/data/postgresql.conf
```

---

## Rollback Procedures

| Method | How to rollback |
|--------|-----------------|
| pg_dump restore | Keep old cluster running; repoint apps to old host |
| pg_upgrade (copy) | Stop PG 18, start PG 17 with old datadir untouched |
| pg_upgrade (`--link`) | Restore from filesystem snapshot taken before upgrade |
| Logical replication | Keep publisher running; repoint apps back to publisher |
| Cloud upgrade | Restore from snapshot / PITR to pre-upgrade time |

**Never run `delete_old_cluster.sh` until production validated for days/weeks.**

---

## Cloud / DBaaS Major Version Upgrades

### AWS RDS

```bash
# Check available targets
aws rds describe-db-engine-versions --engine postgres \
  --query 'DBEngineVersions[?contains(EngineVersion, `18`)].EngineVersion'

# In-place major upgrade (downtime during modify)
aws rds modify-db-instance \
  --db-instance-identifier myapp-prod \
  --engine-version 18.1 \
  --allow-major-version-upgrade \
  --apply-immediately

# Or: create PG 18 instance, DMS replicate, cutover
```

**RDS notes:**
- Pre-upgrade snapshot automatic
- Parameter group must match new major (`postgres18` family)
- `rds_superuser` role — test extension compatibility
- Read replicas upgraded after primary or recreated

### Google Cloud SQL

```bash
gcloud sql instances patch INSTANCE_NAME \
  --database-version=POSTGRES_18
```

Use Database Migration Service for complex cutovers.

### Azure Flexible Server

```bash
az postgres flexible-server update \
  --resource-group rg-prod \
  --name myapp-prod \
  --version 18
```

### Docker / Kubernetes

- **Docker:** new container with `postgres:18`, restore dump or replicate
- **CNPG:** update `spec.imageName`, follow operator upgrade docs; often logical replication or dump for major jumps

---

## Minor Version Upgrades (Same Major)

**No data migration needed.** Replace binaries and restart.

```bash
# RHEL
sudo dnf update postgresql18-server
sudo systemctl restart postgresql-18

# Debian/Ubuntu
sudo apt update && sudo apt upgrade postgresql-18
sudo pg_ctlcluster 18 main restart

# Docker
docker pull postgres:18.2-bookworm
# Recreate container with same volume — minor bump is safe

SELECT version();   -- confirm 18.x
```

---

## Upgrade Runbook Template

Copy for each production upgrade:

```
Project:        PG ___ → PG ___
Method:         pg_upgrade | pg_dump | logical replication | cloud
Date/Window:    ___________
Owner:          ___________

Pre-checks:     [ ] Backup verified  [ ] Staging passed  [ ] Extensions OK
                [ ] App team notified  [ ] Rollback documented

Execution:      [ ] Stop apps  [ ] Run upgrade  [ ] Post-upgrade SQL
                [ ] Smoke tests  [ ] Enable apps

Validation:     [ ] Row counts  [ ] pg_stat_statements baseline
                [ ] Replication (if any)  [ ] Backups on new version

Sign-off:       DBA ______ App ______ Date ______
Old cluster decommission date: ______
```

---

## Related

- [Minor & Major Upgrades Overview](upgrades.md)
- [Version History](../01-getting-started/version-history.md)
- [PostgreSQL 18 Reference](../01-getting-started/postgresql-18.md)
- [Logical Replication](../05-replication-ha/logical-replication.md)
- [Logical Backup](../04-backup-recovery/logical-backup.md)
- [PITR](../04-backup-recovery/point-in-time-recovery.md)
