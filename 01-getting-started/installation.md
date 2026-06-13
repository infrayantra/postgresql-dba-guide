# Installation & Initialization — Overview

PostgreSQL can run on bare-metal Linux, containers, Kubernetes, and managed cloud (DBaaS). This page is the **decision hub**; each platform has a dedicated deep-dive guide.

**After install:** configure production paths, backup, and monitoring → [Production Cluster Layout](../03-administration/production-cluster-layout.md).

**Download URLs:** [Official Download Links](official-download-links.md) · **Full index:** [INDEX.md](../INDEX.md)

---

## Choose Your Platform

| Platform | Guide | Best for |
|----------|-------|----------|
| **Linux servers** (RHEL, Debian, Ubuntu, SUSE, Amazon Linux) | [Linux Deep Install](install-linux.md) | Production self-managed, full control |
| **Windows** (dev / learning) | [Windows Install](install-windows.md) | EDB installer + pgAdmin; use Linux for prod |
| **Docker / Compose** | [Docker Install](install-docker.md) | Dev, CI, single-node prod with ops maturity |
| **Kubernetes** | [Kubernetes Install](install-kubernetes.md) | Cloud-native HA (CNPG, Zalando, Helm) |
| **Managed / DBaaS** (RDS, Aurora, Cloud SQL, Azure, Neon) | [DBaaS Install](install-dbaas.md) | Production without running PG yourself |
| **macOS** | [Official Downloads](official-download-links.md) (Postgres.app / Homebrew) | Local development |

---

## Quick Decision Tree

```
Need PostgreSQL?
│
├─ Production, minimal ops overhead?
│   └─► DBaaS (RDS / Cloud SQL / Azure Flexible) → install-dbaas.md
│
├─ Already on Kubernetes?
│   └─► CloudNativePG or Zalando operator → install-kubernetes.md
│
├─ Container workflow, single host?
│   └─► Docker Compose with volumes + secrets → install-docker.md
│
└─ VMs / bare metal / full DBA control?
    └─► PGDG packages on Linux → install-linux.md
```

---

## Universal First Steps (All Self-Managed)

Regardless of platform, production clusters should have:

1. **`data_checksums` enabled at initdb** — **on by default in PG 18**; use `--no-data-checksums` only for legacy pg_upgrade
2. **SCRAM-SHA-256** password authentication for remote connections
3. **`pg_hba.conf`** least-privilege rules (no `0.0.0.0/0 trust`)
4. **Dedicated data volume** (not OS disk) on fast storage (NVMe/SSD)
5. **Backup configured before go-live** — logical or physical + WAL
6. **`pg_stat_statements`** for query observability

```sql
-- Verify after any install path
SELECT version();
SHOW data_directory;
SHOW data_checksums;
SHOW ssl;
```

---

## Package Source: Always Prefer PGDG (Linux)

OS-bundled PostgreSQL (RHEL AppStream, Ubuntu default) lags behind and blocks multiple major versions. Use [PostgreSQL Global Development Group (PGDG)](https://www.postgresql.org/download/) packages:

- **RHEL-family:** `pgdg-redhat-repo` RPM + `dnf module disable postgresql`
- **Debian/Ubuntu:** `apt.postgresql.org` APT repo

Full commands: [install-linux.md](install-linux.md)

---

## Initialize a New Cluster (Self-Managed)

```bash
# Generic initdb — paths vary by distro
sudo -u postgres initdb -D /path/to/PGDATA \
  --encoding=UTF8 \
  --locale=en_US.UTF-8 \
  --auth-local=peer \
  --auth-host=scram-sha-256
# PG 18+: checksums ON by default — add --no-data-checksums only if required
```

| Option | Purpose |
|--------|---------|
| `--data-checksums` | Detect silent page corruption (PG 18 default ON) |
| `--no-data-checksums` | Disable checksums (PG 18+; legacy pg_upgrade only) |
| `--wal-segsize=64` | 64 MB WAL segments (heavy write workloads) |
| `--locale=C` | Sort performance (K8s/CNPG default) vs locale-aware sorting |

### Bootstrap SQL

```sql
ALTER USER postgres PASSWORD 'strong_password_here';

CREATE ROLE app_user LOGIN PASSWORD 'app_pass';
CREATE DATABASE app_db OWNER app_user ENCODING 'UTF8';
REVOKE CONNECT ON DATABASE app_db FROM PUBLIC;
GRANT CONNECT ON DATABASE app_db TO app_user;
```

---

## Platform-Specific Paths

| Platform | `$PGDATA` typical | Config location | Service |
|----------|-------------------|-----------------|---------|
| RHEL PGDG | `/var/lib/pgsql/18/data` | `$PGDATA/` | `postgresql-18` |
| Debian/Ubuntu | `/var/lib/postgresql/18/main` | `/etc/postgresql/18/main/` | `postgresql@18-main` |
| Docker | `/var/lib/postgresql/data` | `$PGDATA/` or mount | container |
| CNPG (K8s) | pod volume | Operator CRD `spec.postgresql.parameters` | Pod |

---

## Docker Quick Reference

```yaml
# Minimal — see install-docker.md for production compose
services:
  postgres:
    image: postgres:18-bookworm
    environment:
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
    volumes:
      - pgdata:/var/lib/postgresql/data
    shm_size: 256mb
```

---

## Kubernetes Quick Reference

```bash
# CloudNativePG — see install-kubernetes.md
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
kubectl apply -f cnpg-cluster.yaml
kubectl -n database get clusters
```

---

## DBaaS Quick Reference

```bash
# AWS RDS example — see install-dbaas.md for full options
aws rds create-db-instance \
  --engine postgres --engine-version 18.1 \
  --db-instance-class db.r6g.large \
  --multi-az --storage-encrypted \
  --backup-retention-period 14
```

---

## Directory Layout After initdb

```
$PGDATA/
├── postgresql.conf
├── pg_hba.conf
├── pg_ident.conf
├── PG_VERSION
├── base/           # database files
├── global/         # cluster catalog
├── pg_wal/         # WAL segments
├── pg_stat/
├── pg_logical/     # replication slots
└── postmaster.pid  # present when running
```

---

## Verify Installation

```bash
# Service (Linux)
systemctl status postgresql-18    # RHEL
pg_lsclusters                     # Debian/Ubuntu

# Connectivity
pg_isready -h localhost -p 5432
ss -tlnp | grep 5432
```

```sql
SELECT version();
SHOW config_file;
SHOW hba_file;
SHOW data_checksums;
```

---

## Production Checklist (Day 0)

- [ ] Platform guide followed ([Linux](install-linux.md) / [Docker](install-docker.md) / [K8s](install-kubernetes.md) / [DBaaS](install-dbaas.md))
- [ ] `data_checksums = on`
- [ ] Strong passwords; SCRAM-SHA-256
- [ ] Network restricted (private subnet / no public IP)
- [ ] TLS enabled for remote connections
- [ ] Backup + tested restore procedure documented
- [ ] Monitoring (pg_stat_statements, cloud insights, or Prometheus)
- [ ] `$PGDATA`, port, version documented in runbook

---

## Deep-Dive Guides

| Guide | Contents |
|-------|----------|
| [postgresql-18.md](postgresql-18.md) | PG 18 features: AIO, skip scan, uuidv7(), OAuth, checksum defaults, upgrade notes |
| [install-linux.md](install-linux.md) | RHEL/Rocky/Alma, Debian/Ubuntu, Amazon Linux, SUSE, Alpine, source compile, SELinux, dedicated disks, OS tuning |
| [install-docker.md](install-docker.md) | Official image, entrypoint, Compose prod, secrets, replication, custom images, pitfalls |
| [install-kubernetes.md](install-kubernetes.md) | CloudNativePG, Zalando, Bitnami Helm, StatefulSet, storage, pooler, upgrades |
| [install-dbaas.md](install-dbaas.md) | RDS, Aurora, Cloud SQL, Azure Flexible, Neon, Supabase, migration, cost |

---

## Related

- [Architecture & Internals](architecture.md)
- [Version History & Upgrades](version-history.md)
- [Major Version Upgrade Guide](../09-maintenance/major-version-upgrade.md)
- [postgresql.conf](../02-configuration/postgresql-conf.md)
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
