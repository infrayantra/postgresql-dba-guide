# Knowledge Base Version Policy

| Item | Value |
|------|-------|
| **Knowledge base version** | 1.0 |
| **Current PostgreSQL** | **18.x** (released 2025-09-25) |
| **Knowledge base updated** | June 2026 |
| **Document count** | 81 markdown files |
| **Master index** | [INDEX.md](INDEX.md) |
| **Official PG docs** | https://www.postgresql.org/docs/18/ |

---

## Convention

All examples in this knowledge base **default to PostgreSQL 18** unless a section explicitly discusses upgrading *from* an older major.

| Context | Use |
|---------|-----|
| New installs | PG **18** packages, paths, Docker tags |
| Upgrade guides | Source version → **18** |
| Version-specific features | Tag minimum version (e.g. "since PG 16") |
| EOL versions | Documented for migration planning only |

---

## Package & Path Reference (PG 18)

| Platform | Packages | Binaries | Service |
|----------|----------|----------|---------|
| RHEL / Rocky / Alma | `postgresql18-server`, `postgresql18-contrib` | `/usr/pgsql-18/bin` | `postgresql-18` |
| Debian / Ubuntu | `postgresql-18`, `postgresql-contrib-18` | `/usr/lib/postgresql/18/bin` | `postgresql@18-main` |
| Windows (EDB) | Installer from postgresql.org/download/windows | `C:\Program Files\PostgreSQL\18\bin` | `postgresql-x64-18` |
| Docker | `postgres:18`, `postgres:18-bookworm` | in container | — |
| CNPG | `ghcr.io/cloudnative-pg/postgresql:18.x` | in pod | — |

| Path | Value |
|------|-------|
| RHEL `$PGDATA` | `/var/lib/pgsql/18/data` |
| Debian `$PGDATA` | `/var/lib/postgresql/18/main` |
| Production layout | `/data/pgdata/18`, `/data/pgarchive`, `/data/pglog` |

See [Production Cluster Layout](03-administration/production-cluster-layout.md).

---

## Supported PostgreSQL Versions

| Major | Status | EOL | Notes |
|-------|--------|-----|-------|
| **18** | **Current — use for new work** | ~Nov 2030 | AIO, uuidv7(), OAuth, checksums default ON |
| 17 | Supported | Nov 2029 | pg_upgrade to 18 |
| 16 | Supported | Nov 2028 | |
| 15 | Supported | Nov 2027 | |
| 14 | Supported | Nov 2026 | Plan upgrade |
| 13 | **EOL** | Nov 2025 | Upgrade immediately |
| 12 and older | **EOL** | — | Not supported |

History & release cycle: [postgresql-history-and-releases.md](01-getting-started/postgresql-history-and-releases.md)

---

## PG 18 Production Checklist (DBA)

- [ ] `data_checksums` ON at initdb (PG 18 default)
- [ ] SCRAM-SHA-256 passwords (migrate off MD5)
- [ ] `archive_mode = on` + pgBackRest or equivalent
- [ ] PITR drill completed
- [ ] `shared_preload_libraries` includes `pg_stat_statements`
- [ ] Dedicated log directory (`/data/pglog`)
- [ ] PgBouncer for app connections if > 100 clients
- [ ] `io_method = worker` for I/O-bound workloads (benchmark first)
- [ ] Replication slots monitored
- [ ] Patroni REST: `/primary` not `/master`

---

## Knowledge Base Structure

| Folder | Topics |
|--------|--------|
| `01-getting-started/` | Install, history, architecture, downloads |
| `02-configuration/` | postgresql.conf, paths, pg_hba |
| `03-administration/` | Production layout, capacity, roles |
| `04-backup-recovery/` | pgBackRest, PITR, pg_basebackup |
| `05-replication-ha/` | Patroni runbook, slots, failover |
| `06-performance/` | Tuning, pgbench, indexing, EXPLAIN |
| `07-monitoring/` | Health checks, logging, metrics |
| `08-security/` | TLS, TDE, encryption, audit |
| `09-maintenance/` | DBA checklists, vacuum, upgrades |
| `10-advanced/` | Extensions, pooling, WAL internals |
| `11-troubleshooting/` | Investigation, errors, corruption |
| `cheat-sheets/` | psql, admin SQL, parameters |

Full index: [INDEX.md](INDEX.md)

---

## When Updating This Knowledge Base

1. Pin examples to latest stable **minor** when citing version (e.g. `18.4`).
2. Search for stale patterns: `postgresql-16`, `pgsql/17`, `postgres:16`, MD5 auth.
3. Update `README.md`, `INDEX.md`, and this file dates.
4. Add new pages to README TOC and INDEX document list.
5. Add release-note callouts for PG 19+ when released.

---

## Official References

| Resource | URL |
|----------|-----|
| Downloads | https://www.postgresql.org/download/ |
| PG 18 docs | https://www.postgresql.org/docs/18/ |
| Release notes | https://www.postgresql.org/docs/release/ |
| Security patches | https://www.postgresql.org/support/security/ |

KB download page: [official-download-links.md](01-getting-started/official-download-links.md)

**Website:** [WEBSITE.md](WEBSITE.md) — MkDocs Material static site (`.\scripts\serve-docs.ps1`).

---

*PostgreSQL is community open-source (PostgreSQL License). Enterprise/vendor differences: [History & Enterprise vs OSS](01-getting-started/postgresql-history-and-releases.md).*
