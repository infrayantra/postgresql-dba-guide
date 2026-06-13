# TDE & Data-at-Rest Encryption Implementation

Guide to protecting PostgreSQL **18** data at rest — filesystem encryption, cloud TDE, backup encryption, column-level options, and Percona **pg_tde**.

> **Important:** Community PostgreSQL 18 does **not** include native transparent database-level TDE (unlike Oracle TDE or SQL Server). "TDE" for PostgreSQL means **encrypting storage layers** or using **third-party extensions**.

---

## Encryption Layers

```
┌─────────────────────────────────────────────────────────┐
│  Application encryption (pgcrypto, app-level AES)       │  ← column/value
├─────────────────────────────────────────────────────────┤
│  PostgreSQL data files ($PGDATA)                        │
├─────────────────────────────────────────────────────────┤
│  Filesystem / volume encryption (LUKS, EBS, dm-crypt)   │  ← "TDE" in practice
├─────────────────────────────────────────────────────────┤
│  Physical disk / SAN encryption                          │
└─────────────────────────────────────────────────────────┘

         TLS encrypts data IN TRANSIT only → see ssl-tls-implementation.md
```

| Method | Transparent to PG? | Protects $PGDATA | Protects backups |
|--------|-------------------|------------------|------------------|
| LUKS / cloud volume | Yes | Yes | Only if backup on encrypted vol |
| pgBackRest cipher | No (configured) | N/A | Yes |
| pgcrypto columns | No | Partial (those columns) | Encrypted columns in dump |
| Percona pg_tde | Yes (extension) | Yes (tablespaces) | Extension-specific |
| RDS / Cloud SQL TDE | Yes (managed) | Yes | Provider-managed |

---

## Option 1 — LUKS Full-Disk / Volume Encryption (Self-Managed)

Best for bare-metal and VM PostgreSQL on Linux when you control the OS.

### Dedicated volume for $PGDATA

```bash
# Identify disk (example: /dev/nvme1n1)
lsblk

# Format with LUKS2
sudo cryptsetup luksFormat /dev/nvme1n1
sudo cryptsetup luksOpen /dev/nvme1n1 pgdata_crypt

# Create filesystem
sudo mkfs.xfs /dev/mapper/pgdata_crypt

# Mount
sudo mkdir -p /data
sudo mount /dev/mapper/pgdata_crypt /data

# Persist in /etc/crypttab + /etc/fstab
echo "pgdata_crypt UUID=$(blkid -s UUID -o value /dev/nvme1n1) none luks" | sudo tee -a /etc/crypttab

echo '/dev/mapper/pgdata_crypt /data xfs defaults 0 0' | sudo tee -a /etc/fstab
```

### PostgreSQL layout on encrypted volume

```bash
sudo mkdir -p /data/pgdata /data/pglog /data/pgarchive
sudo chown postgres:postgres /data/pgdata /data/pglog /data/pgarchive
sudo chmod 700 /data/pgdata

# Patroni data_dir or initdb
sudo -u postgres /usr/pgsql-18/bin/initdb -D /data/pgdata
```

### Key management

| Approach | Notes |
|----------|-------|
| Passphrase at boot | Manual unlock after reboot — document break-glass |
| Clevis + Tang (Network Bound Encryption) | Auto-unlock in trusted network |
| TPM 2.0 binding | Unlock tied to hardware |
| Cloud KMS (AWS KMS, Azure Key Vault) | For VMs with KMS integration |

**Clevis/Tang example (RHEL):**

```bash
sudo dnf install clevis clevis-luks clevis-dracut
sudo clevis luks bind -d /dev/nvme1n1 tang '{"url":"http://tang.example.com"}'
```

### HA cluster note

All 3 Patroni nodes need **independent encrypted volumes** or shared encrypted storage (rare for PG). Each node unlocks its own LUKS volume at boot before starting Patroni.

---

## Option 2 — Cloud Volume Encryption

### AWS EBS

```bash
# Enable encryption on new volume (default in many accounts)
aws ec2 create-volume --size 500 --volume-type gp3 \
  --availability-zone us-east-1a \
  --encrypted \
  --kms-key-id alias/aws/ebs

# Attach to EC2; mount as /data
```

- Uses AES-256; keys in AWS KMS
- Snapshots encrypted with same key
- **RDS:** storage encryption enabled at instance creation (cannot enable later without snapshot restore)

```bash
aws rds create-db-instance \
  --storage-encrypted \
  --kms-key-id arn:aws:kms:... \
  ...
```

### Google Cloud SQL

```bash
gcloud sql instances create mydb \
  --disk-encryption-key=projects/PROJECT/locations/REGION/keyRings/RING/cryptoKeys/KEY
```

### Azure Flexible Server

```bash
az postgres flexible-server create \
  --geo-redundant-backup Enabled \
  ...
# Infrastructure encryption + customer-managed keys via Azure Key Vault
```

---

## Option 3 — pgBackRest Backup Encryption

Encrypts backup repository — protects off-site copies even if `$PGDATA` volume is encrypted separately.

```ini
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<strong-passphrase-in-vault>

# PG 18+: or use repo cipher from env
# repo1-cipher-pass=<env:PG_BACKREST_CIPHER_PASS>
```

Store passphrase in HashiCorp Vault, AWS Secrets Manager — not in git.

```bash
# Encrypted backup still restorable with passphrase
pgbackrest --stanza=main info
pgbackrest --stanza=main --delta restore
```

---

## Option 4 — Percona pg_tde (Extension)

Commercial/open-source path to **true PostgreSQL TDE** — encrypts data files at the tablespace level using external key management.

> Not part of community PostgreSQL 18 from postgresql.org. Requires Percona Distribution for PostgreSQL or Percona build.

### Concept

```
Master key (Vault/KMS)
    └── Tablespace encryption key (TEK)
            └── Data files encrypted on disk
```

### High-level setup

1. Install Percona PG 18 with pg_tde
2. Configure key provider (file, Vault, KMIP)
3. Enable extension and encrypted tablespace

```sql
CREATE EXTENSION pg_tde;

-- Create encrypted tablespace
CREATE TABLESPACE encrypted_ts LOCATION '/data/encrypted'
  WITH (encryption = true);

CREATE TABLE sensitive_data (
  id int PRIMARY KEY,
  ssn text
) TABLESPACE encrypted_ts;
```

Consult [Percona pg_tde documentation](https://docs.percona.com/postgresql/) for key rotation and HA implications.

---

## Option 5 — Column-Level Encryption (pgcrypto)

Not TDE — but protects specific columns when full-disk encryption is insufficient.

```sql
CREATE EXTENSION pgcrypto;

CREATE TABLE users (
  id bigint PRIMARY KEY,
  email text NOT NULL,
  ssn_enc bytea NOT NULL
);

-- Encrypt on insert (passphrase from app or vault — NOT hardcoded in prod)
INSERT INTO users (id, email, ssn_enc)
VALUES (1, 'user@example.com', pgp_sym_encrypt('123-45-6789', current_setting('app.enc_key')));

-- Decrypt (requires key in session)
SET app.enc_key = 'vault-retrieved-key';
SELECT email, pgp_sym_decrypt(ssn_enc, current_setting('app.enc_key')) AS ssn
FROM users WHERE id = 1;
```

| Pros | Cons |
|------|------|
| Granular | No index on encrypted values (unless deterministic) |
| Works on any PG | Key management burden |
| Portable dumps | Performance overhead |

---

## Option 6 — Application-Level Encryption

Encrypt before INSERT in application; store ciphertext in `bytea` or `text`.

- Use AES-256-GCM with keys from AWS KMS / Vault
- PostgreSQL never sees plaintext
- Best for highly sensitive fields (PII, PAN)

---

## WAL & Archive Encryption

PostgreSQL does **not** encrypt WAL separately from data files. WAL inherits filesystem encryption:

| WAL location | Encryption |
|--------------|------------|
| `$PGDATA/pg_wal/` | Same LUKS/EBS as $PGDATA |
| Archive (`/data/pgarchive/`) | Encrypt archive directory volume |
| S3 archive | SSE-S3 or SSE-KMS |

```bash
# S3 archive_command with SSE-KMS (via aws cli)
archive_command = 'aws s3 cp %p s3://pg-wal-archive/%f --sse aws:kms --sse-kms-key-id alias/pg-wal'
```

---

## HA / Patroni Considerations

| Topic | Guidance |
|-------|----------|
| All nodes | Encrypt each node's `$PGDATA` volume consistently |
| pg_basebackup | Encrypted source → encrypted target; keys must be available on replica |
| Failover | Standby promotes on encrypted volume — auto-unlock must work on DR site |
| Shared storage | Rare; if used, encryption at SAN/NFS layer |
| Replication wire | Use **TLS** for in-transit — separate from TDE |

---

## Compliance Mapping

| Requirement | Implementation |
|-------------|----------------|
| PCI-DSS encryption at rest | LUKS/EBS + TLS in transit + pgAudit |
| HIPAA | Volume encryption + access controls + audit logs |
| SOC2 | KMS-managed keys + rotation policy + backup encryption |
| GDPR | TDE + column encryption for special category data |

Document in security policy:
- Key custodian
- Rotation schedule (annual cert/key rotation)
- Break-glass recovery procedure

---

## Key Rotation

### LUKS key rotation

```bash
sudo cryptsetup luksAddKey /dev/nvme1n1
sudo cryptsetup luksRemoveKey /dev/nvme1n1 --key-slot 0   # after verifying new slot
```

### AWS KMS key rotation

Enable automatic annual rotation on KMS CMK; EBS volumes use current key material.

### pgBackRest

Change `repo1-cipher-pass`; re-encrypt repo or maintain old passphrase for historical backups.

### pg_tde

Follow Percona key rotation procedure — re-wrap TEKs with new master key.

---

## Verification

```bash
# LUKS active?
lsblk -f
sudo dmsetup ls --tree

# AWS EBS encrypted?
aws ec2 describe-volumes --volume-ids vol-xxx --query 'Volumes[0].Encrypted'

# PostgreSQL on correct mount?
df -h /data/pgdata
mount | grep /data
```

```sql
-- pgcrypto test
SELECT pgp_sym_encrypt('test', 'key') IS NOT NULL;

-- Checksum enabled (corruption detection — complements encryption)
SHOW data_checksums;
```

---

## Implementation Checklist

### Minimum production baseline

- [ ] `$PGDATA` on encrypted volume (LUKS / EBS / Azure SSE)
- [ ] WAL and archive on encrypted storage
- [ ] Backups encrypted (pgBackRest cipher or encrypted bucket)
- [ ] TLS for all client connections
- [ ] Keys in KMS/Vault — not in repos or config files
- [ ] Boot-time unlock documented (DR site included)
- [ ] Quarterly restore test from encrypted backup

### Enhanced (regulated data)

- [ ] Column or app-level encryption for PII/PAN
- [ ] Customer-managed KMS keys (CMK)
- [ ] pgAudit + log shipping to immutable storage
- [ ] mTLS for application connections
- [ ] Evaluate pg_tde if Percona stack approved

---

## Related

- [SSL/TLS Implementation](ssl-tls-implementation.md)
- [Encryption Overview](encryption.md)
- [pgBackRest](../04-backup-recovery/pg-backrest.md)
- [Auditing](auditing.md)
- [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md)
