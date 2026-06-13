# Data Directory (PGDATA) — Setup & Relocation

The **data directory** (`$PGDATA`) holds all cluster files: databases, WAL, config, and logs (if relative path). **PostgreSQL 18** default paths:

| Platform | Default PGDATA |
|----------|----------------|
| RHEL PGDG | `/var/lib/pgsql/18/data` |
| Debian/Ubuntu | `/var/lib/postgresql/18/main` |
| Docker official | `/var/lib/postgresql/data` |

> See also: [postgresql.conf](postgresql-conf.md) · [Cluster Management](../03-administration/cluster-management.md)

---

## Inspect Current Paths

```sql
SHOW data_directory;
SHOW config_file;
SHOW hba_file;
SHOW ident_file;
```

```bash
sudo -u postgres /usr/pgsql-18/bin/postgres -C data_directory -D /var/lib/pgsql/18/data
sudo -u postgres /usr/pgsql-18/bin/postgres -C config_file -D /var/lib/pgsql/18/data

# systemd (RHEL)
systemctl cat postgresql-18 | grep -E 'PGDATA|Environment'
```

```bash
# Debian
pg_lsclusters
# Ver Cluster Port Status Owner Data directory
# 18  main    5432 online postgres /var/lib/postgresql/18/main
```

---

## Set Data Directory at initdb (New Cluster)

```bash
# RHEL — custom path
sudo mkdir -p /data/pgdata/18
sudo chown postgres:postgres /data/pgdata/18
sudo chmod 700 /data/pgdata/18

sudo -u postgres /usr/pgsql-18/bin/initdb \
  -D /data/pgdata/18 \
  -E UTF8 \
  --locale=en_US.UTF-8 \
  --data-checksums

# Point service at new path (RHEL)
# Edit /usr/lib/systemd/system/postgresql-18.service or drop-in:
# Environment=PGDATA=/data/pgdata/18
sudo systemctl daemon-reload
sudo systemctl enable --now postgresql-18
```

```bash
# Debian — create cluster on custom path
sudo pg_createcluster 18 custom --port=5433 -- --data-checksums
# Or after manual initdb, register with pg_ctlcluster
```

---

## Change Data Directory (Move Existing Cluster)

**Requires downtime.** Use `rsync` for large datasets.

### Step 1 — Stop PostgreSQL

```bash
sudo systemctl stop postgresql-18
# Verify stopped
sudo -u postgres /usr/pgsql-18/bin/pg_ctl -D /var/lib/pgsql/18/data status
```

### Step 2 — Copy data to new location

```bash
sudo mkdir -p /data/pgdata/18
sudo chown postgres:postgres /data/pgdata/18

# Method A: rsync (recommended — preserves permissions)
sudo rsync -av --delete /var/lib/pgsql/18/data/ /data/pgdata/18/

# Method B: cp -a
sudo cp -a /var/lib/pgsql/18/data/. /data/pgdata/18/
sudo chown -R postgres:postgres /data/pgdata/18
sudo chmod 700 /data/pgdata/18
```

### Step 3 — Update service / environment

**RHEL systemd drop-in:**

```bash
sudo mkdir -p /etc/systemd/system/postgresql-18.service.d
sudo tee /etc/systemd/system/postgresql-18.service.d/pgdata.conf <<'EOF'
[Service]
Environment=PGDATA=/data/pgdata/18
EOF
sudo systemctl daemon-reload
```

**Debian:**

```bash
# Update cluster config
sudo pg_ctlcluster 18 main stop
# Edit /etc/postgresql/18/main/postgresql.conf if needed
# Move via pg_renamecluster or update postgresql.conf data_directory (see below)
```

### Step 4 — Optional: set in postgresql.conf

Normally PGDATA is determined by `-D` at startup. You can also set:

```ini
# postgresql.conf (must match actual location)
data_directory = '/data/pgdata/18'
```

Requires **restart**; path must match where postmaster is started.

### Step 5 — Tablespaces

If tablespaces exist, **symlinks or paths must remain valid**:

```sql
SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;
```

Move tablespace directories separately and update symlinks, or use `ALTER TABLE ... SET TABLESPACE` before migration.

### Step 6 — Start and verify

```bash
sudo systemctl start postgresql-18
sudo -u postgres psql -c "SHOW data_directory;"
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
```

### Step 7 — Remove old directory (after validation)

```bash
# Only after confirming cluster healthy for 24–48h
sudo mv /var/lib/pgsql/18/data /var/lib/pgsql/18/data.old
# rm -rf after backup verified
```

---

## Move PGDATA to Separate Disk (Common Production Pattern)

```
/data/pgdata/18/     ← PGDATA (fast SSD)
/data/pgarchive/     ← WAL archive (see backup-archive.md)
/data/pgbackup/      ← base backups
/data/pglog/         ← logs (see log-directory.md)
```

Benefits: isolate I/O, size disks independently, easier DR copy.

---

## Patroni / HA Note

Patroni stores `data_dir` in DCS config — do **not** move PGDATA manually on Patroni nodes without updating:

```yaml
# patroni.yml
postgresql:
  data_dir: /data/pgdata/18
```

Coordinate with `patronictl edit-config` and rolling restarts.

---

## Docker / Kubernetes

```yaml
# docker-compose
volumes:
  - /host/data/pgdata:/var/lib/postgresql/data
environment:
  PGDATA: /var/lib/postgresql/data/pgdata  # optional subdir
```

CNPG / Zalando: PVC mounts replace manual PGDATA moves.

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `FATAL: data directory has wrong ownership` | Not postgres:postgres or not 700 | `chown` / `chmod 700` |
| `FATAL: lock file postmaster.pid already exists` | Stale pid or running instance | Stop other instance; remove pid only if sure stopped |
| `could not open file ... No such file` | Incomplete rsync | Re-sync; check tablespace paths |
| Service starts wrong path | Old PGDATA in systemd | Fix drop-in; `daemon-reload` |

---

## Related

- [Backup & Archive Directories](backup-archive-directories.md)
- [Log Directory](log-directory.md)
- [Tablespaces](../03-administration/tablespaces.md)
- [pg_basebackup](../04-backup-recovery/pg-basebackup.md)
