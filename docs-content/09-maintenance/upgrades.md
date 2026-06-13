# Major & Minor Upgrades — Overview

Quick index for PostgreSQL upgrades. For **full step-by-step procedures**, see **[Major Version Upgrade Guide](major-version-upgrade.md)**.

---

## Minor vs Major

| Type | Example | Method | Downtime |
|------|---------|--------|----------|
| **Minor** | 18.0 → 18.2 | `dnf/apt update` + restart | Seconds–minutes |
| **Major** | 14 → 18 | pg_upgrade, dump/restore, or logical replication | Minutes–hours |

You **cannot** use package manager alone to jump major versions.

---

## Choose Your Major Upgrade Method

| Scenario | Method |
|----------|--------|
| One major jump, large DB, hours downtime OK | **pg_upgrade** |
| Several majors behind (12 → 18) | **pg_dump/restore** or **logical replication** |
| Near-zero downtime, large DB | **Logical replication** cutover |
| Small DB or schema refactor | **pg_dump / pg_restore** |
| AWS RDS / Cloud SQL / Azure | **Provider upgrade** or **DMS** |

→ Full walkthroughs: **[major-version-upgrade.md](major-version-upgrade.md)**

---

## Minor Version Upgrade

```bash
sudo dnf update postgresql18-server
sudo systemctl restart postgresql-18

SELECT version();
```

No dump/restore. Review release notes for bug fixes.

---

## Major Version Upgrade (Quick: 17 → 18 via pg_upgrade)

```bash
sudo dnf install postgresql18-server
sudo systemctl stop postgresql-17

# Match checksums with old cluster (PG 18 defaults ON)
sudo -u postgres /usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data
# Or: --no-data-checksums if old cluster had none

sudo -u postgres /usr/pgsql-18/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-17/bin \
  --new-bindir=/usr/pgsql-18/bin \
  --old-datadir=/var/lib/pgsql/17/data \
  --new-datadir=/var/lib/pgsql/18/data \
  --check

sudo -u postgres /usr/pgsql-18/bin/pg_upgrade ...   # production run
./analyze_new_cluster.sh
sudo systemctl enable --now postgresql-18
```

**PG 18:** statistics retained by default; migrate MD5 passwords to SCRAM.

→ Details, Debian steps, logical replication, multi-hop, cloud: **[major-version-upgrade.md](major-version-upgrade.md)**

---

## Pre-Upgrade Essentials

```sql
SELECT extname, extversion FROM pg_extension;
SELECT * FROM pg_prepared_xacts;
SHOW data_checksums;
```

```bash
pg_dumpall -f /backup/pre-upgrade.sql
pg_upgrade --check ...
```

---

## Post-Upgrade Essentials

```sql
ANALYZE;
ALTER EXTENSION pg_stat_statements UPDATE;
SELECT version();
```

---

## Related

- **[Major Version Upgrade Guide](major-version-upgrade.md)** ← primary reference
- [Version History](../01-getting-started/version-history.md)
- [PostgreSQL 18 Reference](../01-getting-started/postgresql-18.md)
- [Logical Replication](../05-replication-ha/logical-replication.md)
- [Logical Backup](../04-backup-recovery/logical-backup.md)
