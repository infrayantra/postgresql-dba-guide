# Version History & Upgrade Paths

> **Origins & release policy:** [PostgreSQL History, Releases & Enterprise vs OSS](postgresql-history-and-releases.md)

## Current Supported Versions (2026)

| Version | Release | End of Life | Notable features |
|---------|---------|-------------|------------------|
| **18** | Sep 2025 | Nov 2030 | AIO subsystem, skip scan, uuidv7(), OAuth 2.0, checksums default ON, pg_upgrade keeps stats |
| **17** | Sep 2024 | Nov 2029 | Improved vacuum memory, JSON_TABLE, MERGE enhancements |
| **16** | Sep 2023 | Nov 2028 | Logical replication from standby, `pg_stat_io` |
| **15** | Oct 2022 | Nov 2027 | MERGE, public schema permissions change |
| **14** | Sep 2021 | Nov 2026 | Multirange types, connection slots improvements |
| **13** | Sep 2020 | **EOL Nov 2025** | — |
| **12** | Oct 2019 | **EOL Nov 2024** | — |

> **New deployments (2026):** use **PostgreSQL 18**. PGDG and cloud providers typically support N and N-1 major versions.

See [PostgreSQL 18 — DBA Reference](postgresql-18.md) and **[Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md)** for detailed migration procedures.

---

## Supported Upgrade Paths (Summary)

| From | To | Recommended method |
|------|-----|-------------------|
| 17 | 18 | pg_upgrade (stats retained on PG 18) |
| 16 | 18 | pg_upgrade chain (16→17→18) OR pg_dump OR logical replication |
| 14–15 | 18 | pg_dump/restore OR logical replication (PG 14+ publisher) |
| 12–13 | 18 | pg_dump/restore (EOL — upgrade urgently) |
| Any | 18 (cloud) | RDS modify / DMS / Cloud SQL patch |

Full procedures: **[Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md)**

---

## Major Version Upgrade Methods

### 1. pg_upgrade (Fast, In-Place Directory)

Best for large clusters where dump/restore is too slow. **PG 18 retains optimizer statistics** after upgrade.

```bash
# Stop old cluster
systemctl stop postgresql-17

# Initialize new cluster (PG 18: checksums ON by default)
/usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data
# If old cluster has NO checksums:
/usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data --no-data-checksums

# Run pg_upgrade
/usr/pgsql-18/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-17/bin \
  --new-bindir=/usr/pgsql-18/bin \
  --old-datadir=/var/lib/pgsql/17/data \
  --new-datadir=/var/lib/pgsql/18/data \
  --check    # dry run first

# Production run (copy mode — safer rollback)
/usr/pgsql-18/bin/pg_upgrade ... 

# Or --link for speed (snapshot filesystem first)
# PG 18+: --swap option — see release notes

# After upgrade
./analyze_new_cluster.sh   # still recommended; less critical on PG 18
./delete_old_cluster.sh    # only when confident
```

**Requirements:**
- Compatible extensions (check release notes)
- Same locale/encoding
- **Matching data checksum settings** between clusters
- Enough disk (or use `--link` / `--swap`)

### 2. Logical Migration (pg_dump / pg_dumpall)

Safest; allows schema changes during migration.

```bash
pg_dumpall -h old_host -U postgres > cluster_dump.sql
pg_dump -Fc -j 4 -d mydb -f mydb.dump

psql -h new_host -f cluster_dump.sql
pg_restore -j 4 -d mydb mydb.dump
```

### 3. Logical Replication Migration

Zero-downtime cutover for large databases.

1. Set up PG 18 as subscriber to PG 16/17 publisher
2. Initial sync + catch-up
3. Brief outage: stop writes, verify lag = 0, repoint apps

### 4. Blue/Green with Cloud Tools

- AWS DMS, Aurora read replica promote
- GCP Database Migration Service
- Azure Database Migration Service

---

## Minor Version Upgrades

Package manager replaces binaries; restart required. **No dump/restore needed.**

```bash
sudo dnf update postgresql18-server
sudo systemctl restart postgresql-18

SELECT version();  -- verify new minor (e.g. 18.0 → 18.2)
```

---

## Pre-Upgrade Checklist

```sql
SELECT extname, extversion FROM pg_extension;

SELECT conrelid::regclass, contype
FROM pg_constraint WHERE NOT convalidated;

SELECT * FROM pg_prepared_xacts;

SHOW data_checksums;  -- must match target cluster for pg_upgrade
```

```bash
pg_upgrade --check ...
# PG 18: reindex FTS/pg_trgm if using ICU/non-libc collation provider
```

---

## Breaking Changes to Watch

### PG 18
- **Checksums default ON** for new initdb — use `--no-data-checksums` when upgrading old clusters without checksums
- **MD5 auth deprecated** — migrate to SCRAM-SHA-256
- **VACUUM/ANALYZE** processes inheritance children by default — use `ONLY` for old behavior
- **COPY CSV** stricter `\.` handling
- **Unlogged partitioned tables** disallowed
- **AFTER trigger** execution role semantics changed
- **OAuth 2.0** available — review auth architecture

### PG 17
- Vacuum and WAL behavior changes — review release notes

### PG 16
- `pg_stat_all_tables` column changes
- Logical decoding on standby requires configuration

### PG 15
- `PUBLIC` schema: `CREATE` revoked from all users except owner
- `COPY FROM` restricted to superuser by default

---

## Extension Compatibility

```sql
ALTER EXTENSION postgis UPDATE;
ALTER EXTENSION pg_stat_statements UPDATE;
```

Check each extension for PG 18 support before major upgrade.

---

## Rollback Strategy

| Method | Rollback |
|--------|----------|
| pg_dump restore | Keep old cluster running until verified |
| pg_upgrade (copy mode) | Old datadir intact until `delete_old_cluster.sh` |
| pg_upgrade (`--link`) | **No easy rollback** — filesystem snapshot first |
| pg_upgrade (`--swap`) | Understand swap semantics before use |
| Logical replication | Keep publisher until cutover verified |

---

## Related

- [Knowledge Base Index](../INDEX.md)
- [PostgreSQL History, Releases & Enterprise vs OSS](postgresql-history-and-releases.md)
- [Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md)
- [PostgreSQL 18 Reference](postgresql-18.md)
- [Upgrades](upgrades.md)
- [Installation](installation.md)
