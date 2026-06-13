# pgBackRest — Backup & Recovery

**pgBackRest** is the standard production tool for PostgreSQL **full/incremental/differential backups**, **WAL archiving**, **PITR**, and **S3/Azure/GCS** repos. This guide targets **PostgreSQL 18** on RHEL/Debian with PGDG packages.

> See also: [pg_basebackup](pg-basebackup.md) · [PITR](point-in-time-recovery.md) · [TDE / Backup Encryption](../08-security/tde-implementation.md)

---

## Architecture

```
┌──────────────── PostgreSQL 18 (primary) ────────────────┐
│  archive_command → pgbackrest archive-push %p           │
│  backup from pg1-path=/var/lib/pgsql/18/data            │
└──────────────────────────┬──────────────────────────────┘
                           │
              ┌────────────▼────────────┐
              │  pgBackRest process     │
              │  (parallel, incremental)│
              └────────────┬────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
   repo1 (local)     repo2 (S3)        repo3 (Azure)
```

| Concept | Meaning |
|---------|---------|
| **Stanza** | Backup group tied to one PostgreSQL cluster (`[main]`) |
| **Repo** | Storage backend (`repo1`, `repo2`, …) |
| **Full / diff / incr** | Backup types (see below) |

---

## Install (PG 18)

```bash
# RHEL / Rocky / Alma
sudo dnf install pgbackrest

# Debian / Ubuntu (PGDG)
sudo apt install pgbackrest

pgbackrest version
```

Create OS user and directories:

```bash
sudo mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest
sudo chown postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest
sudo chmod 750 /etc/pgbackrest
```

---

## Configuration

### /etc/pgbackrest/pgbackrest.conf

```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
repo1-retention-diff=14
repo1-retention-archive=14
repo1-retention-archive-type=time

start-fast=y
process-max=4
compress-type=zst
compress-level=3

log-level-console=info
log-level-file=debug
log-path=/var/log/pgbackrest

# Encryption at rest (backup repo)
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<store-in-vault-not-plaintext>

[main]
pg1-path=/var/lib/pgsql/18/data
pg1-port=5432
pg1-user=postgres
pg1-socket-path=/var/run/postgresql
```

### PostgreSQL integration

```ini
# postgresql.conf
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
archive_timeout = 60

# Recommended with pgBackRest
max_wal_senders = 10
wal_level = replica
```

```bash
sudo systemctl reload postgresql-18
```

### Initialize stanza

```bash
sudo -u postgres pgbackrest --stanza=main stanza-create
sudo -u postgres pgbackrest --stanza=main check
sudo -u postgres pgbackrest --stanza=main info
```

`check` validates archive and backup connectivity — run after every config change.

---

## Backup Types

| Type | Contains | When to run |
|------|----------|-------------|
| **full** | Entire cluster | Weekly or monthly |
| **diff** | Changes since last **full** | Daily |
| **incr** | Changes since last **any** backup | Hourly |

```bash
# Full
sudo -u postgres pgbackrest --stanza=main --type=full backup

# Differential
sudo -u postgres pgbackrest --stanza=main --type=diff backup

# Incremental
sudo -u postgres pgbackrest --stanza=main --type=incr backup

# Status
sudo -u postgres pgbackrest --stanza=main info
```

Example `info` output:

```
stanza: main
    status: ok
    db (current)
        wal archive min/max (18): 000000010000000000000001/000000010000000000000045

        full backup: 20250607-020000F
            timestamp start/stop: 2025-06-07 02:00:00 / 2025-06-07 02:45:00
            database size: 120.5GB, backup size: 120.5GB

        incr backup: 20250614-080000F_20250614-120000I
            timestamp start/stop: 2025-06-14 12:00:00 / 2025-06-14 12:08:00
            database size: 125.1GB, backup size: 2.3GB
```

---

## Scheduling

### cron

```bash
# /etc/cron.d/pgbackrest
0 2 * * 0 postgres pgbackrest --stanza=main --type=full backup
0 2 * * 1-6 postgres pgbackrest --stanza=main --type=diff backup
0 * * * * postgres pgbackrest --stanza=main --type=incr backup
```

### systemd timer

```ini
# /etc/systemd/system/pgbackrest-incr.service
[Unit]
Description=pgBackRest incremental backup

[Service]
Type=oneshot
User=postgres
ExecStart=/usr/bin/pgbackrest --stanza=main --type=incr backup
```

---

## Restore

### Full restore (disaster recovery)

```bash
sudo systemctl stop postgresql-18

# Empty data directory
sudo -u postgres rm -rf /var/lib/pgsql/18/data/*
sudo -u postgres mkdir -p /var/lib/pgsql/18/data

# Delta restore — only changed files
sudo -u postgres pgbackrest --stanza=main --delta restore

sudo systemctl start postgresql-18
```

### PITR (point-in-time recovery)

```bash
sudo systemctl stop postgresql-18
sudo -u postgres rm -rf /var/lib/pgsql/18/data/*

sudo -u postgres pgbackrest --stanza=main --type=time \
  --target='2025-06-14 10:30:00+00' \
  --target-action=promote \
  --delta restore

sudo systemctl start postgresql-18
```

Other targets:

```bash
--target='2025-06-14 10:30:00+00'     # timestamp
--target='000000010000000000000045'   # XID (with --target-xid)
--target-name='before_migration'      # named restore point
```

Create restore point before risky DDL:

```sql
SELECT pg_create_restore_point('before_migration');
```

### Restore to alternate path (DR drill)

```bash
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/dr-test/data \
  --delta restore
```

See [DC/DR Drill](dc-dr-drill.md).

---

## S3 Repository

```ini
[global]
repo1-type=s3
repo1-s3-bucket=my-pg-backups
repo1-s3-region=us-east-1
repo1-s3-endpoint=s3.amazonaws.com
repo1-s3-key=<access-key>
repo1-s3-key-secret=<secret>
repo1-path=/pg/prod-main
repo1-retention-full=4
repo1-retention-archive-type=time
repo1-retention-archive=30
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<passphrase>
```

Use IAM roles on EC2 instead of static keys when possible (`repo1-s3-role`).

Dual repo (local + S3):

```ini
repo1-type=posix
repo1-path=/var/lib/pgbackrest

repo2-type=s3
repo2-s3-bucket=offsite-backups
repo2-path=/pg/main
```

Backup writes to both; restore can use `--repo=2`.

---

## Performance Tuning

```ini
[global]
process-max=8              # parallel processes (≤ CPU cores)
compress-type=zst          # zst | lz4 | gz | none
compress-level=3
buffer-size=16MB
start-fast=y               # force checkpoint at backup start
```

On PostgreSQL side during large backups:

```ini
max_wal_size = 8GB
checkpoint_timeout = 15min
```

Monitor backup progress:

```sql
SELECT * FROM pg_stat_progress_basebackup;
```

```bash
tail -f /var/log/pgbackrest/main-backup.log
```

---

## Patroni / HA Integration

Patroni manages `archive_command` and often stanza config via dynamic settings:

```yaml
# patroni.yml excerpt
postgresql:
  parameters:
    archive_mode: 'on'
    archive_command: 'pgbackrest --stanza=main archive-push %p'
  create_replica_methods:
    - pgbackrest
    - basebackup
  pgbackrest:
    command: '/usr/bin/pgbackrest'
    keep_data: true
    no_params: true
    options:
      - '--type=none'
```

After failover, **standby promotion does not reconfigure pgBackRest** — same stanza, same `pg1-path` on new primary. Update DNS/VIP; run `pgbackrest check`.

For replica rebuild via pgBackRest:

```bash
pgbackrest --stanza=main --type=none restore
# Then configure recovery / Patroni handles replication
```

See [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md).

---

## Encryption

| Layer | Config |
|-------|--------|
| Backup repo | `repo1-cipher-type=aes-256-cbc` + passphrase |
| S3 SSE | Bucket default encryption + pgBackRest cipher (defense in depth) |
| TLS | PostgreSQL `ssl=on` for archive connections |

Store passphrase in vault; reference via env in systemd:

```ini
Environment=PGBACKREST_REPO1_CIPHER_PASS_FILE=/etc/pgbackrest/cipher.pass
```

Details: [TDE Implementation](../08-security/tde-implementation.md) · [Encryption Methods](../08-security/encryption-methods.md)

---

## Monitoring & Alerts

```sql
-- Archive health on PostgreSQL
SELECT archived_count, failed_count,
       last_archived_wal, last_archived_time,
       last_failed_wal, last_failed_time
FROM pg_stat_archiver;
```

```bash
# Exit code 0 = OK; use in Nagios/Prometheus script
pgbackrest --stanza=main check
pgbackrest --stanza=main info --output=json
```

### Alert conditions

| Condition | Action |
|-----------|--------|
| `failed_count` increasing | Fix archive_command; check disk/S3 creds |
| No full backup within retention policy | Run manual full; fix cron |
| `pgbackrest check` fails | Run `info`; verify stanza paths |
| WAL archive min/max gap growing on standby | Check network; repo space |

---

## pgBackRest vs pg_basebackup vs Barman

| Feature | pgBackRest | pg_basebackup | Barman |
|---------|------------|---------------|--------|
| Built-in | No | Yes | No |
| Incremental | Yes | No | Limited |
| Parallel backup/restore | Yes | Tar only (`-j`) | Yes |
| Cloud native repo | S3, Azure, GCS | Manual | Hooks |
| PITR | Yes | With WAL archive | Yes |
| Fleet / multi-server | One stanza each | Per-script | Central server |
| Standby bootstrap | restore + config | Excellent (`-R`) | `barman recover` |

**Barman** (brief): central Python backup server pulling from many PostgreSQL instances via SSH/streaming — good for large fleets; see [Barman docs](https://www.pgbarman.org/) if evaluating.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `[028]: backup and archive info lists do not match` | Run `stanza-upgrade` after PG major upgrade |
| `archive-push timeout` | Increase `archive-timeout`; check S3 latency |
| `unable to find backup` | Wrong stanza name; check `info` |
| Restore missing WAL | Extend `repo-retention-archive`; verify archive before PITR target |
| Permission denied on repo | `chown postgres:postgres` on repo path |
| Duplicate stanza after clone | New stanza for cloned cluster; never share stanza between two live clusters |

Post major upgrade (PG 17 → 18):

```bash
sudo -u postgres pgbackrest --stanza=main stanza-upgrade
sudo -u postgres pgbackrest --stanza=main check
```

---

## Backup Monitoring Checklist

- [ ] `pgbackrest check` daily (automated)
- [ ] Full backup age within policy
- [ ] `pg_stat_archiver.failed_count` = 0
- [ ] Monthly restore test (full + PITR)
- [ ] Cipher passphrase in vault with rotation procedure
- [ ] S3 lifecycle / repo retention aligned with compliance
- [ ] Post-upgrade `stanza-upgrade` completed

---

## Related

- [pg_basebackup](pg-basebackup.md)
- [Physical Backup Overview](physical-backup.md)
- [Point-in-Time Recovery](point-in-time-recovery.md)
- [DC/DR Drill](dc-dr-drill.md)
- [Encryption Methods](../08-security/encryption-methods.md)
- [Kubernetes Install](../01-getting-started/install-kubernetes.md)
