# Knowledge Base Index

Master map of the **PostgreSQL DBA Knowledge Base** — **81 documents**, target **PostgreSQL 18**.

→ Start: [README.md](README.md) · [VERSION.md](VERSION.md)

---

## By DBA Lifecycle

```
Install → Configure → Operate → Monitor → Secure → Backup/DR → HA → Tune → Troubleshoot
   │         │          │         │        │         │        │      │         │
   §1        §2         §3        §7       §8        §4       §5     §6        §11
```

| Phase | Primary docs |
|-------|----------------|
| **1. Install** | [Downloads](01-getting-started/official-download-links.md) · [Installation](01-getting-started/installation.md) · [Linux](01-getting-started/install-linux.md) · [Windows](01-getting-started/install-windows.md) · [Docker](01-getting-started/install-docker.md) · [K8s](01-getting-started/install-kubernetes.md) · [DBaaS](01-getting-started/install-dbaas.md) |
| **2. Configure** | [Production Layout](03-administration/production-cluster-layout.md) · [postgresql.conf](02-configuration/postgresql-conf.md) · [pg_hba.conf](02-configuration/pg-hba-conf.md) · [Paths](02-configuration/data-directory.md) |
| **3. Operate** | [Cluster Management](03-administration/cluster-management.md) · [Users/Roles](03-administration/user-roles.md) · [DBA Checklists](09-maintenance/dba-runbook-checklists.md) |
| **4. Monitor** | [Health Checks](07-monitoring/dba-health-checks.md) · [pg_stat_statements](07-monitoring/pg-stat-statements.md) · [Logging](07-monitoring/logging.md) · [Metrics](07-monitoring/metrics-exporters.md) |
| **5. Secure** | [Encryption Methods](08-security/encryption-methods.md) · [TLS](08-security/ssl-tls-implementation.md) · [Authentication](08-security/authentication.md) · [RLS](08-security/row-level-security.md) |
| **6. Backup/DR** | [Logical vs Physical](01-getting-started/logical-vs-physical.md) · [pgBackRest](04-backup-recovery/pg-backrest.md) · [PITR](04-backup-recovery/point-in-time-recovery.md) · [DC/DR Drill](04-backup-recovery/dc-dr-drill.md) |
| **7. HA** | [PG 18 HA Runbook](05-replication-ha/postgresql-18-ha-setup-runbook.md) · [Streaming Rep](05-replication-ha/streaming-replication.md) · [Failover](05-replication-ha/failover.md) · [Replication Slots](05-replication-ha/replication-slots.md) |
| **8. Tune** | [In-Memory](06-performance/in-memory-features-integration.md) · [Tuning](06-performance/tuning-parameters.md) · [Indexing](06-performance/indexing.md) · [EXPLAIN](06-performance/query-optimization.md) |
| **9. Troubleshoot** | [Investigation Runbook](11-troubleshooting/investigation-runbook.md) · [Common Errors](11-troubleshooting/common-errors.md) · [Slow Queries](11-troubleshooting/slow-queries.md) |

---

## Learning Paths

### Path A — New DBA (2–4 weeks)

1. [History & releases](01-getting-started/postgresql-history-and-releases.md)
2. [Architecture](01-getting-started/architecture.md)
3. [Install locally](01-getting-started/official-download-links.md) + [psql reference](cheat-sheets/psql-reference.md)
4. [postgresql.conf](02-configuration/postgresql-conf.md) + [pg_hba.conf](02-configuration/pg-hba-conf.md)
5. [Admin SQL](cheat-sheets/admin-sql.md)
6. [Backup basics](01-getting-started/logical-vs-physical.md)
7. [VACUUM](09-maintenance/vacuum-analyze.md)

### Path B — Production on-call

1. [DBA Checklists](09-maintenance/dba-runbook-checklists.md)
2. [Health Checks](07-monitoring/dba-health-checks.md)
3. [Investigation Runbook](11-troubleshooting/investigation-runbook.md)
4. [Replication Slots](05-replication-ha/replication-slots.md)
5. [PITR](04-backup-recovery/point-in-time-recovery.md)
6. [Session timeouts](06-performance/session-timeouts.md)

### Path C — HA & DR lead

1. [Production Layout](03-administration/production-cluster-layout.md)
2. [PG 18 HA Runbook](05-replication-ha/postgresql-18-ha-setup-runbook.md)
3. [pgBackRest](04-backup-recovery/pg-backrest.md)
4. [DC/DR Drill](04-backup-recovery/dc-dr-drill.md)
5. [Failover](05-replication-ha/failover.md)
6. [TLS for HA](08-security/ssl-tls-implementation.md)

### Path D — Performance specialist

1. [In-Memory Features](06-performance/in-memory-features-integration.md)
2. [Tuning Parameters](06-performance/tuning-parameters.md)
3. [pgbench](06-performance/pgbench.md)
4. [Indexing](06-performance/indexing.md)
5. [Query Optimization](06-performance/query-optimization.md)
6. [pg_stat_statements](07-monitoring/pg-stat-statements.md)

### Path E — Security & compliance

1. [Encryption Methods](08-security/encryption-methods.md)
2. [TLS Implementation](08-security/ssl-tls-implementation.md)
3. [TDE](08-security/tde-implementation.md)
4. [pgAudit](10-advanced/pgaudit.md)
5. [Row-Level Security](08-security/row-level-security.md)

---

## Complete Document List (81)

### 01-getting-started (14)
`official-download-links` · `installation` · `install-linux` · `install-windows` · `install-docker` · `install-kubernetes` · `install-dbaas` · `postgresql-18` · `architecture` · `postgresql-history-and-releases` · `logical-vs-physical` · `version-history`

### Root & navigation (3)
`README` · `VERSION` · `INDEX`

### cheat-sheets (5)
`README (cheat-sheets/)` · `psql-reference` · `psql-commands` · `admin-sql` · `parameters-quick-ref`

### 02-configuration (6)
`postgresql-conf` · `data-directory` · `backup-archive-directories` · `log-directory` · `pg-hba-conf` · `pg-ident-conf`

### 03-administration (6)
`production-cluster-layout` · `capacity-planning` · `cluster-management` · `user-roles` · `databases-schemas` · `tablespaces`

### 04-backup-recovery (7)
`logical-backup` · `physical-backup` · `pg-basebackup` · `pg-backrest` · `point-in-time-recovery` · `dc-dr-drill`

### 05-replication-ha (7)
`postgresql-18-ha-setup-runbook` · `replication-slots` · `streaming-replication` · `logical-replication` · `failover` · `patroni-pgpool`

### 06-performance (8)
`in-memory-features-integration` · `tuning-parameters` · `pgbench` · `session-timeouts` · `vacuum-bloat` · `indexing` · `query-optimization`

### 07-monitoring (5)
`dba-health-checks` · `system-catalogs` · `pg-stat-statements` · `logging` · `metrics-exporters`

### 08-security (7)
`authentication` · `encryption-methods` · `encryption` · `ssl-tls-implementation` · `tde-implementation` · `row-level-security` · `auditing`

### 09-maintenance (5)
`dba-runbook-checklists` · `vacuum-analyze` · `autovacuum` · `major-version-upgrade` · `upgrades`

### 10-advanced (9)
`partitioning` · `extensions` · `pgvector` · `pgaudit` · `pg-cron-agent` · `creating-extensions` · `locking-concurrency` · `wal-internals` · `connection-pooling`

### 11-troubleshooting (4)
`investigation-runbook` · `common-errors` · `slow-queries` · `corruption-recovery`

---

## External Official References

| Resource | URL |
|----------|-----|
| PostgreSQL downloads | https://www.postgresql.org/download/ |
| PG 18 documentation | https://www.postgresql.org/docs/18/ |
| Release notes | https://www.postgresql.org/docs/release/ |
| pgAdmin | https://www.pgadmin.org/download/ |
| PGDG Linux repos | https://www.postgresql.org/download/linux/ |
| Security patches | https://www.postgresql.org/support/security/ |

---

## Conventions (maintainers)

- Default version: **PostgreSQL 18**
- RHEL paths: `/usr/pgsql-18/bin`, `$PGDATA=/var/lib/pgsql/18/data`
- Auth: **SCRAM-SHA-256** (not MD5)
- Production backup: **pgBackRest** + archive; logical dump for portability
- HA reference: **Patroni + etcd + HAProxy**

See [VERSION.md](VERSION.md) for full policy.

---

*Index last updated: June 2026*
