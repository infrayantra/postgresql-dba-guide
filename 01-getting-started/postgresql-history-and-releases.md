# PostgreSQL History, Release Cycle & Enterprise vs Open Source

How PostgreSQL began, how versions are released and supported, and how **vendor/enterprise offerings** relate to **community PostgreSQL** (the open-source project).

> **Upgrade paths:** [Version History & Upgrade Paths](version-history.md) · [VERSION.md](../VERSION.md) · [DBaaS comparison](install-dbaas.md)

---

## Origins — From POSTGRES to PostgreSQL

### Berkeley and the Ingres lineage

PostgreSQL traces back to **INGRES**, a relational database started at **UC Berkeley** in the early 1970s under **Michael Stonebraker**. Ingres pioneered concepts that shaped modern RDBMS design.

In **1986**, Stonebraker led **POSTGRES** (Post-Ingres) at Berkeley — a research project that extended the relational model with:

- Complex types (arrays, user-defined types)
- Rules / query rewrite (precursor to triggers and views)
- Less rigid enforcement of pure relational theory

POSTGRES shipped as open source to universities and researchers. It was **not** a commercial product; it was a research platform that proved ideas later adopted industry-wide.

### Postgres95 and the SQL rename

By the mid-1990s, the codebase added a **SQL query language** (replacing the earlier PostQUEL language). In **1995**, **Postgres95** was released with a more accessible SQL interface.

In **1996**, the name became **PostgreSQL** to reflect SQL support while keeping the POSTGRES heritage. The project moved beyond Berkeley into a **worldwide open-source community**.

### Community governance today

PostgreSQL is developed by the **PostgreSQL Global Development Group (PGDG)** — not a single company. It is a **community open-source project** under the **PostgreSQL License** (a permissive BSD-style license similar to MIT/BSD).

- Source: [https://github.com/postgres/postgres](https://github.com/postgres/postgres)
- Docs: [https://www.postgresql.org/docs/](https://www.postgresql.org/docs/)
- No single vendor owns the core database

---

## Historical Timeline (Selected Milestones)

| Year | Event |
|------|-------|
| 1970s | Ingres at UC Berkeley |
| 1986 | POSTGRES research project begins |
| 1995 | Postgres95 — SQL interface |
| 1996 | Renamed PostgreSQL; community development |
| 1998 | **Version 6.3** — first version some production sites used seriously |
| 2000 | **7.0** — foreign keys, improved subqueries |
| 2005 | **8.0** — Windows port; savepoints; tablespaces |
| 2005 | **8.1** — two-phase commit; improved MVCC |
| 2008 | **8.3** — HOT updates, ENUM, XML |
| 2010 | **9.0** — **streaming replication**, hot standby |
| 2012 | **9.2** — index-only scans, JSON support |
| 2014 | **9.4** — JSONB, logical decoding foundation |
| 2016 | **9.6** — parallel query, **pg_stat_statements** in contrib |
| 2017 | **10** — **logical replication**, declarative partitioning, version numbering change (10 not 10.0 as major only) |
| 2018 | **11** — partitioning improvements, JIT (experimental) |
| 2019 | **12** — SQL/JSON path, REINDEX CONCURRENTLY |
| 2020 | **13** — deduplication, B-tree improvements |
| 2021 | **14** — multirange, stored procedures enhancements |
| 2022 | **15** — MERGE, public schema permission change |
| 2023 | **16** — logical replication from standby, `pg_stat_io` |
| 2024 | **17** — improved vacuum memory, JSON_TABLE |
| 2025 | **18** — async I/O, skip scan, uuidv7(), OAuth, checksums default ON |

PostgreSQL’s story is one of **steady, conservative evolution** — strong backward compatibility, MVCC from early days, and features proven in research before production hardening.

---

## Architecture Legacy (Why It Matters)

Ideas from POSTGRES still visible today:

| Concept | Modern PostgreSQL |
|---------|-------------------|
| MVCC | Core concurrency model — readers don't block writers |
| Extensibility | Extensions, custom types, operators, index methods |
| WAL | Durability and replication foundation |
| Cost-based optimizer | Inherited and continuously improved |
| Rules / triggers | Evolved into triggers, rules, generated columns |

Understanding this explains why PostgreSQL favors **extensibility and standards** over monolithic single-vendor features.

---

## Release Cycle

PostgreSQL uses **semantic versioning at the major level only** — majors are integer: 16, 17, 18 (not 18.0 as the product name; minors are 18.1, 18.2).

### Major releases

| Aspect | Policy |
|--------|--------|
| **Frequency** | Roughly **once per year** (September–October typical) |
| **Content** | New features, optimizer changes, possible incompatibilities (documented) |
| **Support duration** | **5 years** from major release date |
| **Upgrade** | Requires dump/restore, pg_upgrade, or logical replication |

Example (PG 18):

- Released: **September 2025**
- End of life: **~November 2030**

### Minor releases

| Aspect | Policy |
|--------|--------|
| **Frequency** | About **every 3 months** (quarterly) |
| **Content** | **Bug and security fixes only** — no new features |
| **Upgrade** | Replace binaries; restart cluster; **no dump/restore** |
| **Branch** | All supported majors get minor releases |

```bash
# Minor upgrade example (18.0 → 18.2)
sudo dnf update postgresql18-server
sudo systemctl restart postgresql-18
SELECT version();
```

### Release support matrix (2026)

| Major | Status | EOL |
|-------|--------|-----|
| **18** | Current | ~Nov 2030 |
| 17 | Supported | Nov 2029 |
| 16 | Supported | Nov 2028 |
| 15 | Supported | Nov 2027 |
| 14 | Supported | Nov 2026 |
| 13 | **EOL** | Nov 2025 |

See [VERSION.md](../VERSION.md) for package names and KB policy.

### Pre-release branches

- **Alpha / beta / RC** — for testing before GA
- Production should run **GA minor releases**, not git main

---

## How Development Works

```
Contributors worldwide
        │
        ▼
  Commitfest (patches reviewed on pgsql-hackers mailing list)
        │
        ▼
  Core team + committers merge to master
        │
        ▼
  Beta → RC → GA major (yearly)
        │
        ▼
  Stable branch — quarterly minor releases (security + bugs)
```

- **No CLA** required for most contributions
- **Feature freeze** before each major release
- **Release notes** document breaking changes — read before every major upgrade
- Extensions in `contrib/` ship with core; third-party extensions separate

---

## Open Source PostgreSQL vs Enterprise Offerings

**Important distinction:** There is only **one core PostgreSQL engine** in the community project. “Enterprise PostgreSQL” usually means **a vendor wraps, supports, or extends** that engine — or a **managed cloud service** runs it for you.

### Community / open source PostgreSQL

| What you get | Details |
|--------------|---------|
| **Core database** | Full-featured RDBMS — same engine vendors build on |
| **License** | PostgreSQL License — free commercial use, no royalties |
| **Support** | Community mailing lists, IRC, Stack Overflow, no SLA |
| **Packaging** | PGDG (yum/apt), source compile, Docker `postgres:18` |
| **Extensions** | contrib + open ecosystem (PostGIS, pgvector, Citus, etc.) |
| **You operate** | Install, patch, backup, HA, tuning — your responsibility |

This knowledge base targets **community PostgreSQL 18** unless noted (Patroni, pgBackRest, etc.).

### What “enterprise” vendors typically add

Vendors do **not** fork PostgreSQL into a different database silently — they **distribute PostgreSQL** plus extras:

| Category | Examples | Typical value |
|----------|----------|---------------|
| **Commercial support** | EDB, Percona, Crunchy Data (support arms) | 24×7 SLA, named engineers, CVE guidance |
| **Management tools** | EDB PEM, pgMonitor, custom dashboards | GUI, fleet management |
| **Proprietary extensions** | EDB Oracle compatibility, Percona pg_tde | Oracle PL/SQL subset, TDE, audit extras |
| **Curated distributions** | EDB Advanced Server*, Percona Distribution | Patched builds, bundled tools, installers |
| **Managed cloud (DBaaS)** | RDS, Aurora, Cloud SQL, Azure Flexible, Neon | Ops abstracted; vendor runs PG for you |
| **Kubernetes operators** | CNPG, Zalando, Crunchy PGO | HA automation on K8s |

\* **EDB Postgres Advanced Server (EPAS)** is EDB’s product line with **compatibility features** on top of PostgreSQL — still PostgreSQL-derived but with optional Oracle-mode syntax and proprietary add-ons. **EDB Postgres Extended** / distribution tracks community PG more closely.

### Comparison table

| Dimension | Community OSS | Enterprise / vendor | Managed cloud (DBaaS) |
|-----------|---------------|---------------------|------------------------|
| **Core engine** | PGDG/community build | Same major version + patches | Same major (often delayed days–weeks) |
| **License cost** | Free | Subscription / support contract | Usage-based ($/hour, storage) |
| **Support SLA** | None | Yes (tiered) | Yes (platform SLA) |
| **Who patches** | You | You or vendor delivers packages | Provider |
| **HA / failover** | You (Patroni, etc.) | Vendor tools or guidance | Often built-in |
| **Backups / PITR** | You (pgBackRest) | Often integrated | Built-in (verify retention) |
| **Extra features** | Extensions only | Proprietary modules possible | Provider extensions (e.g. Aurora storage) |
| **Vendor lock-in** | Low | Low–medium (support/tools) | Medium (APIs, features) |
| **Upgrade timing** | You choose | Vendor certifies versions | Provider schedule |

### Engine compatibility

For **pure community PostgreSQL**:

- SQL, wire protocol, and on-disk format are **standard PostgreSQL**
- Applications using standard SQL/drivers (JDBC, psycopg, pgx) work the same

For **EDB Advanced Server (Oracle compatibility mode)**:

- Additional syntax and Oracle-like packages
- Migration from Oracle easier; **not 100% identical** to community PG
- Check compatibility mode when moving between EDB and community

For **cloud variants**:

- **Amazon RDS PostgreSQL** — community PG + AWS ops; some parameter limits
- **Aurora PostgreSQL** — PostgreSQL-compatible **storage/compute layer** (not byte-identical to self-hosted PG)
- **Google Cloud SQL / Azure Flexible** — community PG engine, managed wrapper
- **Neon / Supabase** — PostgreSQL-compatible with serverless/storage separation

See [DBaaS Install Guide](install-dbaas.md).

### Security and compliance

| Feature | Community | Enterprise add-ons |
|---------|-----------|-------------------|
| SSL/TLS | Built-in | Same + vendor hardening guides |
| SCRAM auth | Built-in (PG 18 deprecates MD5) | Same |
| Row-level security | Built-in | Same |
| Audit (pgaudit) | Extension (open source) | Often bundled/supported by vendor |
| TDE (transparent data encryption) | Not in core | Percona pg_tde, EDB options, cloud volume encryption |
| FIPS / Common Criteria | DIY | Vendor certifications on their distribution |

See [Encryption Methods](../08-security/encryption-methods.md).

### Which should you choose?

| Situation | Recommendation |
|-----------|----------------|
| Strong in-house DBA/SRE team | **Community PG** + Patroni + pgBackRest |
| Need 24×7 SLA, limited PG staff | **Vendor support** on community PG or managed service |
| Oracle migration with PL/SQL | Evaluate **EDB Advanced Server** or rewrite + community PG |
| Fastest time to prod, no ops team | **Managed DBaaS** |
| Kubernetes-native HA | **CNPG / Zalando** on community PG images |
| Maximum control, no license cost | **Community PG** (this KB’s default) |

**Many large companies run community PostgreSQL in production** without a commercial database license — they pay for people, hardware, and optionally support contracts.

---

## Version Numbering Cheat Sheet

```
PostgreSQL 18.2
           │  │
           │  └── minor (quarterly bug/security fix)
           └───── major (yearly features; 5-year support)
```

- Before PG 10: versions were 9.6, 9.5, etc.
- From PG 10 onward: **10, 11, 12, … 18** (major only in marketing)
- `SELECT version();` shows full string including minor

---

## Staying Current

1. Subscribe to **pgsql-announce** for security releases
2. Apply **minor upgrades** within weeks of release
3. Plan **major upgrades** before EOL (see [major-version-upgrade](../09-maintenance/major-version-upgrade.md))
4. Read **release notes** for breaking changes
5. Distinguish **community docs** from vendor docs when using EDB/cloud

---

## Related

- [Knowledge Base Index](../INDEX.md)
- [Version History & Upgrade Paths](version-history.md)
- [VERSION.md](../VERSION.md)
- [PostgreSQL 18 Features](postgresql-18.md)
- [Architecture & Internals](architecture.md)
- [Installation Overview](installation.md)
- [DBaaS / Managed PostgreSQL](install-dbaas.md)
- [Major Version Upgrade](../09-maintenance/major-version-upgrade.md)
