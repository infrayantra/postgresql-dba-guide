# PostgreSQL DBA Knowledge Base

A comprehensive reference for PostgreSQL database administrators — from installation through production operations, performance tuning, high availability, and troubleshooting.

**Target audience:** DBAs, SREs, and backend engineers operating PostgreSQL in production.

| | |
|---|---|
| **PostgreSQL version** | **[18.x](01-getting-started/postgresql-18.md)** (current) |
| **Documents** | **81** guides + cheat sheets |
| **Master index** | **[INDEX.md](INDEX.md)** — lifecycle map & learning paths |
| **Version policy** | **[VERSION.md](VERSION.md)** |
| **Downloads** | **[Official links](01-getting-started/official-download-links.md)** |
| **Website** | **[GitHub Pages deploy](GITHUB-PAGES.md)** · Local: `.\scripts\serve-docs.ps1` |

---

## How to Use This Knowledge Base

| Need | Start here |
|------|------------|
| **First time here** | [INDEX.md](INDEX.md) · [History & releases](01-getting-started/postgresql-history-and-releases.md) |
| New cluster setup | [Downloads](01-getting-started/official-download-links.md) · [Production Layout](03-administration/production-cluster-layout.md) · [Installation](01-getting-started/installation.md) |
| Windows dev install | [Install on Windows](01-getting-started/install-windows.md) |
| Daily operations | [DBA Checklists](09-maintenance/dba-runbook-checklists.md) · [Health Checks](07-monitoring/dba-health-checks.md) |
| Disaster recovery | [Logical vs Physical](01-getting-started/logical-vs-physical.md) · [pgBackRest](04-backup-recovery/pg-backrest.md) · [PITR](04-backup-recovery/point-in-time-recovery.md) |
| Upgrade PG version | [Major Version Upgrade](09-maintenance/major-version-upgrade.md) |
| Performance issue | [In-Memory & Tuning](06-performance/in-memory-features-integration.md) → [Query Optimization](06-performance/query-optimization.md) → [Slow Queries](11-troubleshooting/slow-queries.md) |
| HA / failover | [Streaming Replication](05-replication-ha/streaming-replication.md) → [PG 18 HA Runbook](05-replication-ha/postgresql-18-ha-setup-runbook.md) |
| SSL / TLS / TDE | [Encryption Methods](08-security/encryption-methods.md) · [TLS Setup](08-security/ssl-tls-implementation.md) · [TDE](08-security/tde-implementation.md) |
| Something broken | [Investigation Runbook](11-troubleshooting/investigation-runbook.md) → [Common Errors](11-troubleshooting/common-errors.md) |
| Quick commands | [Cheat Sheets](cheat-sheets/README.md) · [psql Reference](cheat-sheets/psql-reference.md) |
| Paths / PITR / logs | [Data Directory](02-configuration/data-directory.md) · [Archive Mode](02-configuration/backup-archive-directories.md) · [PITR](04-backup-recovery/point-in-time-recovery.md) · [Log Directory](02-configuration/log-directory.md) |

---

## Learning Paths (summary)

Full paths in **[INDEX.md](INDEX.md)**.

| Path | For | Start with |
|------|-----|------------|
| **A — New DBA** | Learning PostgreSQL | Architecture → Install → psql → config |
| **B — On-call** | Production support | DBA Checklists → Health Checks → Investigation Runbook |
| **C — HA/DR** | High availability | Production Layout → HA Runbook → pgBackRest → DC/DR Drill |
| **D — Performance** | Tuning & queries | In-Memory → Tuning → pgbench → EXPLAIN |
| **E — Security** | Compliance & encryption | Encryption Methods → TLS → pgAudit → RLS |

---

## Table of Contents

### 1. Getting Started
- [Official Download Links (Windows, Linux, pgAdmin, Docker)](01-getting-started/official-download-links.md)
- [Installation Overview](01-getting-started/installation.md)
- [Linux Install (RHEL, Debian, Ubuntu, SUSE, Amazon Linux)](01-getting-started/install-linux.md)
- [Windows Install (EDB + pgAdmin)](01-getting-started/install-windows.md)
- [Docker & Docker Compose](01-getting-started/install-docker.md)
- [Kubernetes (CNPG, Zalando, Helm)](01-getting-started/install-kubernetes.md)
- [DBaaS / Managed (RDS, Aurora, Cloud SQL, Azure, Neon)](01-getting-started/install-dbaas.md)
- [PostgreSQL 18 — Features & DBA Notes](01-getting-started/postgresql-18.md)
- [PostgreSQL History, Releases & Enterprise vs OSS](01-getting-started/postgresql-history-and-releases.md)
- [Architecture & Internals](01-getting-started/architecture.md)
- [Logical vs Physical — Replication & Backup](01-getting-started/logical-vs-physical.md)
- [Version History & Upgrade Paths](01-getting-started/version-history.md)
- [Version Policy & Package Names](VERSION.md)

### 2. Configuration
- [postgresql.conf](02-configuration/postgresql-conf.md)
- [Data Directory (PGDATA)](02-configuration/data-directory.md)
- [Backup Directory & Archive Mode](02-configuration/backup-archive-directories.md)
- [Log Directory](02-configuration/log-directory.md)
- [pg_hba.conf (Authentication Rules)](02-configuration/pg-hba-conf.md)
- [pg_ident.conf & Connection Settings](02-configuration/pg-ident-conf.md)

### 3. Administration
- [Production Cluster Layout (Greenfield)](03-administration/production-cluster-layout.md)
- [Capacity Planning](03-administration/capacity-planning.md)
- [Cluster & Instance Management](03-administration/cluster-management.md)
- [Users, Roles & Privileges](03-administration/user-roles.md)
- [Databases, Schemas & Objects](03-administration/databases-schemas.md)
- [Tablespaces](03-administration/tablespaces.md)

### 4. Backup & Recovery
- [Logical vs Physical — Replication & Backup](01-getting-started/logical-vs-physical.md)
- [Logical Backup (pg_dump / pg_restore)](04-backup-recovery/logical-backup.md)
- [Physical Backup Overview](04-backup-recovery/physical-backup.md)
- [pg_basebackup](04-backup-recovery/pg-basebackup.md)
- [pgBackRest](04-backup-recovery/pg-backrest.md)
- [Point-in-Time Recovery (PITR)](04-backup-recovery/point-in-time-recovery.md)
- [DC / DR Drill Runbook](04-backup-recovery/dc-dr-drill.md)

### 5. Replication & High Availability
- [PostgreSQL 18 HA Setup Runbook (Patroni + etcd + HAProxy)](05-replication-ha/postgresql-18-ha-setup-runbook.md)
- [Replication Slots](05-replication-ha/replication-slots.md)
- [Streaming (Physical) Replication](05-replication-ha/streaming-replication.md)
- [Logical Replication](05-replication-ha/logical-replication.md)
- [Failover & Switchover](05-replication-ha/failover.md)
- [Patroni, repmgr & pgpool-II](05-replication-ha/patroni-pgpool.md)

### 6. Performance
- [In-Memory Features & Integration](06-performance/in-memory-features-integration.md)
- [Memory & I/O Tuning Parameters](06-performance/tuning-parameters.md)
- [pgbench — Load Testing](06-performance/pgbench.md)
- [Session & Timeout Tuning](06-performance/session-timeouts.md)
- [VACUUM, Bloat & Storage](06-performance/vacuum-bloat.md)
- [Indexing Strategies](06-performance/indexing.md)
- [Query Optimization & EXPLAIN](06-performance/query-optimization.md)

### 7. Monitoring
- [DBA Health Checks & Alerts](07-monitoring/dba-health-checks.md)
- [System Catalogs & Views](07-monitoring/system-catalogs.md)
- [pg_stat_statements](07-monitoring/pg-stat-statements.md)
- [Logging Configuration](07-monitoring/logging.md)
- [Prometheus / Grafana Exporters](07-monitoring/metrics-exporters.md)

### 8. Security
- [Authentication Methods](08-security/authentication.md)
- [Encryption Methods — Complete Reference](08-security/encryption-methods.md)
- [Encryption Overview](08-security/encryption.md)
- [SSL / TLS Implementation](08-security/ssl-tls-implementation.md)
- [TDE & Data-at-Rest Encryption](08-security/tde-implementation.md)
- [Row-Level Security (RLS)](08-security/row-level-security.md)
- [Auditing & Compliance (pgAudit)](08-security/auditing.md)

### 9. Maintenance
- [DBA Runbook — Daily / Weekly / Monthly](09-maintenance/dba-runbook-checklists.md)
- [VACUUM & ANALYZE](09-maintenance/vacuum-analyze.md)
- [Autovacuum Tuning](09-maintenance/autovacuum.md)
- [Major Version Upgrade Guide](09-maintenance/major-version-upgrade.md)
- [Upgrades Overview](09-maintenance/upgrades.md)

### 10. Advanced Topics
- [Table Partitioning](10-advanced/partitioning.md)
- [Extensions Overview](10-advanced/extensions.md)
- [pgvector (Vector Search)](10-advanced/pgvector.md)
- [pgAudit (Audit Logging)](10-advanced/pgaudit.md)
- [pg_cron & pgAgent (Job Scheduling)](10-advanced/pg-cron-agent.md)
- [Creating Custom Extensions](10-advanced/creating-extensions.md)
- [Locking & Concurrency](10-advanced/locking-concurrency.md)
- [WAL & Checkpoint Internals](10-advanced/wal-internals.md)
- [Connection Pooling (PgBouncer, pgpool)](10-advanced/connection-pooling.md)

### 11. Troubleshooting
- [Investigation Runbook](11-troubleshooting/investigation-runbook.md)
- [Common Errors & Fixes](11-troubleshooting/common-errors.md)
- [Slow Query Investigation](11-troubleshooting/slow-queries.md)
- [Corruption Detection & Recovery](11-troubleshooting/corruption-recovery.md)

### Cheat Sheets
- [Cheat Sheets Index](cheat-sheets/README.md)
- [psql — Complete Reference (Basics & Advanced)](cheat-sheets/psql-reference.md)
- [psql & CLI Commands](cheat-sheets/psql-commands.md)
- [Essential Admin SQL](cheat-sheets/admin-sql.md)
- [Parameters Quick Reference](cheat-sheets/parameters-quick-ref.md)

---

## Production Stack Reference (PG 18)

Typical self-hosted production components documented in this KB:

```
Apps → PgBouncer → PostgreSQL 18 (primary)
                      ├── streaming standby(s)
                      ├── pgBackRest → local/S3 (PITR)
                      ├── archive_command → WAL archive
                      └── Patroni + etcd + HAProxy (optional HA)
```

Paths: `/data/pgdata/18` · `/data/pgarchive` · `/data/pglog` · `/var/lib/pgbackrest`

Details: [Production Cluster Layout](03-administration/production-cluster-layout.md)

---

## PostgreSQL Process Model

```
                    ┌─────────────────┐
                    │   postmaster    │
                    └────────┬────────┘
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
   background writer    autovacuum launcher    walwriter
         │                   │                   │
   checkpointer         autovacuum workers     archiver
                              │
                    backend processes (one per connection)
```

More: [Architecture & Internals](01-getting-started/architecture.md)

---

## Key Paths & Environment (PG 18)

| Platform | `$PGDATA` | Binaries |
|----------|-----------|----------|
| RHEL PGDG | `/var/lib/pgsql/18/data` | `/usr/pgsql-18/bin` |
| Debian/Ubuntu | `/var/lib/postgresql/18/main` | `/usr/lib/postgresql/18/bin` |
| Windows EDB | `C:\Program Files\PostgreSQL\18\data` | `...\18\bin` |
| Docker | `/var/lib/postgresql/data` | in container |

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=postgres
# Password: use ~/.pgpass (Linux) or %APPDATA%\postgresql\pgpass.conf (Windows)
```

---

## Official External Links

| Resource | URL |
|----------|-----|
| Downloads | https://www.postgresql.org/download/ |
| Documentation | https://www.postgresql.org/docs/18/ |
| Release notes | https://www.postgresql.org/docs/release/ |
| Security | https://www.postgresql.org/support/security/ |
| pgAdmin | https://www.pgadmin.org/download/ |

Full list: [Official Download Links](01-getting-started/official-download-links.md)

---

## Contributing & Maintenance

1. Place topics in the numbered folder matching the lifecycle stage (see [INDEX.md](INDEX.md)).
2. Default all examples to **PostgreSQL 18** ([VERSION.md](VERSION.md)).
3. Cross-link related pages; add to README TOC if new top-level doc.
4. Prefer official sources for download URLs.

---

*Knowledge base v1.0 — PostgreSQL **18** · **[InfraYantra Labs](https://infrayantra.com/)***

*Navigation: [INDEX.md](INDEX.md) · [Website](WEBSITE.md) · [GitHub Pages](GITHUB-PAGES.md) · [Cheat Sheets](cheat-sheets/README.md)*
