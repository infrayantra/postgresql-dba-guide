# PostgreSQL 18 — DBA Reference

PostgreSQL **18** was released **2025-09-25**. This page covers what DBAs need for installation, tuning, upgrades, and day-to-day operations on PG 18.

> **Version policy:** Examples default to **PG 18** (current). See [VERSION.md](../VERSION.md).

---

## Version at a Glance

| Item | Value |
|------|-------|
| Release date | 2025-09-25 |
| End of life | ~November 2030 (5-year support) |
| Docs | https://www.postgresql.org/docs/18/ |
| Docker tag | `postgres:18`, `postgres:18-bookworm` |
| PGDG packages | `postgresql18-server`, `postgresql-18` |

---

## Headline Features for DBAs

### 1. Asynchronous I/O (AIO)

New I/O subsystem — backends queue multiple read requests instead of sequential waits. Benefits **sequential scans**, **bitmap heap scans**, and **VACUUM**. Benchmarks show up to ~3× improvement on I/O-bound workloads.

```ini
# postgresql.conf (PG 18+)
io_method = worker               # none | worker | io_uring (Linux)
io_combine_limit = 128kB         # combine adjacent requests
io_max_combine_limit = 1MB       # cap per combine batch
```

```sql
-- Monitor AIO activity
SELECT * FROM pg_aios;

-- effective_io_concurrency now useful on systems without fadvise()
SHOW effective_io_concurrency;
SHOW maintenance_io_concurrency;
```

**Tuning tip:** After upgrade, revisit `effective_io_concurrency` and `maintenance_io_concurrency` — PG 18 enables meaningful values on more platforms.

### 2. pg_upgrade Improvements

- **Retains optimizer statistics** by default — faster time-to-steady-state after major upgrade
- **`--swap`** option — exchange data directories instead of copy/link (advanced; read release notes)
- Checksum mismatch handling: `--no-data-checksums` on initdb for legacy non-checksum clusters

```bash
/usr/pgsql-18/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-17/bin \
  --new-bindir=/usr/pgsql-18/bin \
  --old-datadir=/var/lib/pgsql/17/data \
  --new-datadir=/var/lib/pgsql/18/data \
  --check

# Statistics preserved — analyze_new_cluster.sh still recommended but less critical
./analyze_new_cluster.sh
```

### 3. B-tree Skip Scan

Multicolumn B-tree indexes usable when leading columns are missing from the predicate — planner can **skip** through index entries.

```sql
-- Index on (status, created_at)
CREATE INDEX ON orders (status, created_at);

-- PG 18 may use skip scan for:
SELECT * FROM orders WHERE created_at > '2025-01-01';
-- Previously often required Seq Scan or separate index
```

Verify with `EXPLAIN` — look for `Skip Scan` in plan.

### 4. initdb Defaults: Checksums ON

**PG 18 enables `data_checksums` by default** at initdb.

```bash
# Disable only when upgrading legacy cluster without checksums
initdb -D $PGDATA --no-data-checksums
```

pg_upgrade requires **matching checksum settings** between old and new clusters.

### 5. OAuth 2.0 Authentication

Native OAuth 2.0 support for SSO integration (enterprise / cloud identity).

```ini
# postgresql.conf
oauth_validator_libraries = 'oauth_validator'
```

Configure via `pg_hba.conf` OAuth method and validator library — see [Authentication](../08-security/authentication.md).

### 6. MD5 Deprecation

MD5 password auth **deprecated** in PG 18; removal planned in a future major release.

```sql
-- Warnings on CREATE/ALTER ROLE with MD5
SHOW password_encryption;  -- use scram-sha-256

-- Suppress warnings temporarily (not recommended long-term)
SET md5_password_warnings = off;
```

**Action:** Migrate all roles to SCRAM before PG 19+.

---

## Developer Features (DBA Should Know)

### uuidv7()

Time-ordered UUIDs — better B-tree locality than random UUIDv4.

```sql
SELECT uuidv7();
-- uuidv4() added as alias for gen_random_uuid()
CREATE TABLE events (
  id uuid PRIMARY KEY DEFAULT uuidv7(),
  payload jsonb
);
```

### Virtual Generated Columns (New Default)

Generated columns default to **VIRTUAL** (computed at read time) vs **STORED**.

```sql
CREATE TABLE products (
  price numeric,
  tax numeric,
  total numeric GENERATED ALWAYS AS (price + tax)  -- VIRTUAL by default in PG 18
);

-- Explicit storage mode still supported
ALTER TABLE products ADD COLUMN total_stored numeric
  GENERATED ALWAYS AS (price + tax) STORED;
```

**Ops note:** VIRTUAL columns don't consume disk; STORED columns can be logically replicated in PG 18.

### RETURNING OLD / NEW

```sql
UPDATE orders SET status = 'shipped'
WHERE id = 1
RETURNING old.status AS previous_status, new.status AS current_status;
```

### Temporal Constraints

Constraints over time ranges — `WITHOUT OVERLAPS` for PRIMARY KEY, UNIQUE, FOREIGN KEY on ranges.

```sql
CREATE TABLE bookings (
  room_id int,
  during tstzrange,
  EXCLUDE USING gist (room_id WITH =, during WITH &&)
);
-- See release notes for WITHOUT OVERLAPS syntax on constraints
```

---

## Behavior Changes & Incompatibilities

| Change | Impact | DBA action |
|--------|--------|------------|
| Checksums default ON | New clusters only | Use `--no-data-checksums` for pg_upgrade from old non-checksum |
| VACUUM/ANALYZE inheritance children | Partitions auto-processed | Use `VACUUM ONLY parent` for old behavior |
| MD5 deprecated | Auth warnings | Migrate to SCRAM |
| COPY CSV `\.` handling | Stricter EOF marker | Update ETL scripts; match psql client version |
| Unlogged partitioned tables disallowed | DDL error | Remove UNLOGGED from partitioned tables |
| AFTER trigger role timing | Security semantics | Review SECURITY DEFINER trigger chains |
| Timezone abbreviation order | Session TZ first | Test apps relying on `timezone_abbreviations` |
| Full-text / pg_trgm + ICU collation | Possible behavior shift | Reindex FTS and pg_trgm indexes after pg_upgrade |

---

## Install Quick Reference (PG 18)

### RHEL / Rocky / Alma

```bash
sudo dnf install -y postgresql18-server postgresql18-contrib
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb   # checksums on by default
sudo systemctl enable --now postgresql-18
```

### Debian / Ubuntu

```bash
sudo apt install -y postgresql-18 postgresql-contrib-18
pg_lsclusters   # verify 18/main online
```

### Docker

```yaml
image: postgres:18-bookworm
environment:
  POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"  # checksums on by default
```

### Kubernetes (CNPG)

```yaml
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.0
  bootstrap:
    initdb:
      dataChecksums: true   # default in PG 18 initdb anyway
```

### DBaaS

```bash
aws rds create-db-instance --engine postgres --engine-version 18.1 ...
gcloud sql instances create ... --database-version=POSTGRES_18
az postgres flexible-server create ... --version 18
```

---

## Upgrade Paths to PG 18

| From | Recommended method |
|------|-------------------|
| PG 17 | pg_upgrade (stats retained) |
| PG 16 | pg_upgrade chain OR logical replication OR pg_dump |
| PG 14–15 | pg_dump/restore OR logical replication |
| PG 12–13 | pg_dump/restore (EOL — upgrade urgently) |

**Full step-by-step guide:** [Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md)

```bash
# Pre-upgrade on source cluster
SELECT extname, extversion FROM pg_extension;
SELECT * FROM pg_prepared_xacts;
pg_upgrade --check ...
```

---

## New / Changed Monitoring (PG 18)

```sql
SELECT * FROM pg_aios;                    -- AIO file handles
-- pg_stat_statements changes — review release notes for column renames
SELECT * FROM pg_stat_io;                 -- PG 16+, still relevant
```

Enable AIO-aware workload testing after upgrade — compare `pg_stat_statements` totals and sequential scan times.

---

## Optimizer GUCs (PG 18)

```ini
enable_self_join_elimination = on
enable_distinct_reordering = on
```

Disable temporarily when investigating plan regressions after upgrade.

---

## Related

- [Version History & Upgrade Paths](version-history.md)
- [Linux Install](install-linux.md)
- [Docker Install](install-docker.md)
- [Kubernetes Install](install-kubernetes.md)
- [DBaaS Install](install-dbaas.md)
- [Authentication — OAuth](../08-security/authentication.md)
- [In-Memory Features & Integration](../06-performance/in-memory-features-integration.md)
- [Tuning Parameters](../06-performance/tuning-parameters.md)
