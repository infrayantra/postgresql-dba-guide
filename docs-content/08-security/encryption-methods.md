# PostgreSQL Encryption Methods — Complete Reference

All encryption options for **PostgreSQL 18** — what each method protects, how it works, and when to use it.

| Deep-dive guides | |
|------------------|--|
| TLS setup (certs, mTLS, HA) | [ssl-tls-implementation.md](ssl-tls-implementation.md) |
| Data at rest (LUKS, TDE, backups) | [tde-implementation.md](tde-implementation.md) |

---

## Two Fundamental Layers

```
                    ┌─────────────────────────────────────┐
  IN TRANSIT        │  TLS / SSL (network wire)           │  ← Method 1–4
                    └─────────────────────────────────────┘
                              │
                         PostgreSQL
                              │
                    ┌─────────────────────────────────────┐
  AT REST           │  Volume / TDE / column / backup     │  ← Method 5–12
                    └─────────────────────────────────────┘
```

| Layer | Threat model | Without encryption |
|-------|--------------|-------------------|
| **In transit** | Sniffing network, MITM | Passwords + query data visible |
| **At rest** | Stolen disk, backup leak, snapshot theft | Full database readable |

**Production baseline:** TLS in transit **+** volume encryption at rest **+** encrypted backups.

---

## Method Comparison (All Options)

| # | Method | Layer | Built into PG 18? | Transparent? | Typical use |
|---|--------|-------|-------------------|--------------|-------------|
| 1 | **TLS (server cert)** | Transit | Yes | Yes (client config) | All remote connections |
| 2 | **mTLS (client cert)** | Transit + auth | Yes | Partial | Zero-trust, no passwords |
| 3 | **TLS at proxy** (HAProxy/PgBouncer) | Transit | Via proxy | Yes | Centralized cert management |
| 4 | **Cloud managed TLS** (RDS, etc.) | Transit | Provider | Yes | Managed PostgreSQL |
| 5 | **LUKS / dm-crypt** | At rest | OS-level | Yes | Self-hosted `$PGDATA` |
| 6 | **Cloud volume encryption** (EBS, Azure, GCP) | At rest | Cloud | Yes | VM / managed DB storage |
| 7 | **pgBackRest backup cipher** | At rest (backup) | Extension/tool | Configured | Off-site backup protection |
| 8 | **S3 / object storage SSE-KMS** | At rest (archive) | S3/GCS | Yes | WAL archive, backup objects |
| 9 | **pgcrypto (column)** | At rest (column) | Extension | No | PII columns, tokens |
| 10 | **Application AES** | At rest (column) | App code | No | Highest sensitivity fields |
| 11 | **Percona pg_tde** | At rest (tablespace) | Extension (Percona) | Yes | True DB-level TDE |
| 12 | **Password hash (SCRAM)** | Auth storage | Yes | Yes | Not wire encryption — hashes only |

> **SCRAM-SHA-256** encrypts/hashes stored passwords — it is **not** a substitute for TLS on the network.

---

## Category 1 — Encryption In Transit

### Method 1: TLS with Server Certificate (Standard)

**What it does:** Encrypts all traffic between client and PostgreSQL using TLS 1.2/1.3.

**Protects:** Query results, passwords (with SCRAM), replication stream on the wire.

```ini
# postgresql.conf
ssl = on
ssl_cert_file = '/etc/postgresql/ssl/server/server.crt'
ssl_key_file = '/etc/postgresql/ssl/server/server.key'
ssl_ca_file = '/etc/postgresql/ssl/ca/ca.crt'
ssl_min_protocol_version = 'TLSv1.2'
```

```
# pg_hba.conf
hostnossl all all 0.0.0.0/0 reject
hostssl  all all 10.0.2.0/24 scram-sha-256
```

```bash
psql "host=db.example.com sslmode=verify-full sslrootcert=ca.crt dbname=app user=app"
```

| sslmode | Use |
|---------|-----|
| `require` | Encrypted, no cert verify (dev/internal) |
| `verify-ca` | Encrypted + trust CA |
| `verify-full` | **Production** — encrypted + CA + hostname match |

→ [ssl-tls-implementation.md](ssl-tls-implementation.md)

---

### Method 2: Mutual TLS (mTLS)

**What it does:** Server validates **client certificate** in addition to (or instead of) password.

**Protects:** Stolen passwords useless without client cert; strong identity.

```
# pg_hba.conf
hostssl all app_user 10.0.2.0/24 cert clientcert=verify-full
```

```bash
psql "sslmode=verify-full sslrootcert=ca.crt sslcert=client.crt sslkey=client.key ..."
```

**When to use:** Service-to-service, zero-trust networks, compliance requiring dual-factor at transport layer.

---

### Method 3: TLS Termination at Proxy

**What it does:** Client connects with TLS to HAProxy/PgBouncer; proxy may use plain or TLS to PostgreSQL backend.

```
App ──TLS──► HAProxy :5432 ──► PostgreSQL :5432
```

**When to use:** Single cert management point; many app clients; internal VPC trusted between proxy and DB.

**Risk:** Plain text between proxy and DB if not also TLS — acceptable only in private network.

---

### Method 4: Cloud Provider TLS

**What it does:** Amazon RDS, Cloud SQL, Azure issue/manage server certificates.

```bash
# RDS — download global CA bundle
psql "host=xxx.rds.amazonaws.com sslmode=verify-full sslrootcert=global-bundle.pem ..."
```

```ini
# RDS parameter
rds.force_ssl = 1
```

**When to use:** All managed PostgreSQL — enable `storage encrypted` + `rds.force_ssl` at creation.

---

### Replication & TLS

Streaming replication supports TLS via `hostssl` in pg_hba and `sslmode` in `primary_conninfo`:

```ini
primary_conninfo = 'host=10.0.1.11 port=5432 user=replicator sslmode=verify-full sslrootcert=/etc/postgresql/ssl/ca/ca.crt'
```

Patroni HA: configure on all nodes — see [ssl-tls-implementation.md](ssl-tls-implementation.md).

---

## Category 2 — Encryption At Rest

### Method 5: LUKS Volume Encryption (Linux)

**What it does:** Encrypts entire block device; PostgreSQL sees normal filesystem.

**Algorithm:** AES-XTS (LUKS2 default, typically 512-bit key).

```bash
cryptsetup luksFormat /dev/nvme1n1
cryptsetup luksOpen /dev/nvme1n1 pgdata_crypt
mkfs.xfs /dev/mapper/pgdata_crypt
mount /dev/mapper/pgdata_crypt /data
# initdb -D /data/pgdata
```

| Pros | Cons |
|------|------|
| Transparent to PostgreSQL | Key unlock at boot (DR planning) |
| Protects WAL + data + indexes | Per-node keys on HA cluster |
| Industry standard | CPU overhead minimal on modern HW |

→ [tde-implementation.md](tde-implementation.md)

---

### Method 6: Cloud Volume / Managed Storage Encryption

**What it does:** Hypervisor/storage layer encryption (AES-256).

| Platform | Feature | Key management |
|----------|---------|----------------|
| AWS EBS / RDS | `--encrypted`, `--kms-key-id` | AWS KMS |
| GCP Cloud SQL | CMEK | Cloud KMS |
| Azure Flexible | Infrastructure encryption | Azure Key Vault |

**When to use:** Default for all cloud deployments — enable at **resource creation** (RDS cannot add encryption later without snapshot migration).

---

### Method 7: pgBackRest Backup Encryption

**What it does:** Encrypts backup files in repository (AES-256-CBC).

```ini
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<passphrase-from-vault>
```

**Protects:** Stolen backup files on S3/NFS — independent of `$PGDATA` volume encryption.

**When to use:** Always, for off-site backups.

---

### Method 8: WAL Archive / Object Storage Encryption

**What it does:** SSE-S3, SSE-KMS, or SSE-C on archived WAL and backup objects.

```bash
archive_command = 'aws s3 cp %p s3://pg-wal/%f --sse aws:kms --sse-kms-key-id alias/pg-wal'
```

**When to use:** Any WAL shipping to S3/GCS/Azure Blob.

---

### Method 9: pgcrypto Column Encryption

**What it does:** Encrypt specific column values in SQL/application.

```sql
CREATE EXTENSION pgcrypto;

INSERT INTO users (ssn_enc)
VALUES (pgp_sym_encrypt('123-45-6789', vault_key));

SELECT pgp_sym_decrypt(ssn_enc, vault_key) FROM users;
```

| Function | Algorithm | Use |
|----------|-----------|-----|
| `pgp_sym_encrypt` | AES (OpenPGP) | Symmetric — single key |
| `pgp_pub_encrypt` | OpenPGP public key | Asymmetric |
| `digest()` | SHA-256, etc. | Hashing (not encryption) |
| `crypt()` | bcrypt | Password hashing |

**When to use:** Specific PII columns; defense in depth beyond disk encryption.

**Limitation:** Cannot index encrypted values (unless deterministic encryption with tradeoffs).

---

### Method 10: Application-Level Encryption

**What it does:** App encrypts before INSERT; DB stores `bytea` ciphertext.

```python
# App uses AES-256-GCM + AWS KMS data key
ciphertext = encrypt(plaintext, kms_data_key)
# INSERT into db as bytea
```

**When to use:** PAN, SSN, health records; keys never touch PostgreSQL config.

---

### Method 11: Percona pg_tde (Extension)

**What it does:** Transparent encryption of tablespace data files; keys from Vault/KMS.

```sql
CREATE EXTENSION pg_tde;
CREATE TABLESPACE enc_ts LOCATION '/data/enc' WITH (encryption = true);
CREATE TABLE secrets (...) TABLESPACE enc_ts;
```

**When to use:** Need Oracle/SQL Server-style TDE on PostgreSQL; Percona stack approved.

**Not available** in community PostgreSQL from postgresql.org.

---

### Method 12: SCRAM Password Storage (Auth — Not Wire Encryption)

**What it does:** Stores password verifier as SCRAM-SHA-256 hash — not reversible.

```sql
SHOW password_encryption;  -- scram-sha-256 (PG 18 default)
ALTER ROLE app_user PASSWORD 'secret';
```

**Must pair with TLS** — SCRAM protects stored hashes; TLS protects credentials on the wire.

---

## Decision Matrix — Which Methods Do I Need?

| Scenario | Recommended methods |
|----------|---------------------|
| **Standard production (self-hosted)** | 1 (TLS verify-full) + 5 (LUKS) + 7 (pgBackRest) + 12 (SCRAM) |
| **AWS RDS production** | 4 (force SSL) + 6 (RDS encrypted) + 8 (S3 SSE-KMS backups) |
| **Patroni HA 3-node** | 1 + 5 on each node + TLS replication + 7 |
| **PCI / HIPAA** | 1 + 2 (mTLS optional) + 6 + 7 + 9 or 10 for PAN/PHI + pgAudit |
| **Dev / lab** | 1 (self-signed TLS) or VPN-only + SCRAM |
| **Multi-tenant SaaS** | 1 + 6 + 9/10 for tenant secrets + RLS |

---

## Encryption Algorithms Reference

| Context | Algorithm | Key size |
|---------|-----------|----------|
| TLS 1.3 | AES-256-GCM, ChaCha20-Poly1305 | 256-bit |
| TLS 1.2 (recommended ciphers) | ECDHE + AES-GCM | 256-bit |
| LUKS2 | aes-xts-plain64 | 512-bit (256-bit effective) |
| pgBackRest | AES-256-CBC | 256-bit |
| AWS EBS/RDS | AES-256 | 256-bit (KMS-managed) |
| SCRAM-SHA-256 | PBKDF2 + SHA-256 | — |
| pgcrypto (symmetric) | AES (OpenPGP) | 128–256 bit |
| pg_tde (Percona) | AES | KMS-dependent |

**Avoid:** TLS 1.0/1.1, MD5 auth, DES, RC4, `sslmode=disable` in production.

---

## What Is NOT Encrypted (Know the Gaps)

| Item | Encrypted by TLS? | Encrypted by LUKS? | Notes |
|------|-------------------|--------------------|-------|
| Query text in logs | No | N/A | Redact logs; restrict log access |
| `pg_dump` plain output | No | N/A | Use `-Fc` + encrypt dump file |
| Memory (shared_buffers) | No | No | OS swap encryption optional |
| Replication if plain TCP | No | N/A | Use `hostssl` + sslmode |
| pg_stat_activity.query | No | N/A | Visible to admins |
| Crash dumps / core files | No | Partial | Disable core dumps on DB servers |

---

## Quick Setup — Minimum Production

### Step 1: TLS (5 minutes after certs exist)

```ini
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_min_protocol_version = 'TLSv1.2'
```

```
hostnossl all all 0.0.0.0/0 reject
hostssl all all 10.0.0.0/8 scram-sha-256
```

### Step 2: Encrypted volume

```bash
# Cloud: enable encryption at volume/DB creation
# Linux: LUKS on /data before initdb
```

### Step 3: Encrypted backups

```ini
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=<vault>
```

### Step 4: Verify

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
SHOW data_checksums;
```

```bash
lsblk  # LUKS mapper active
pgbackrest info
```

---

## Monitoring Encryption Health

```sql
-- Non-SSL remote sessions (should be zero)
SELECT pid, usename, client_addr
FROM pg_stat_activity a
LEFT JOIN pg_stat_ssl s USING (pid)
WHERE client_addr IS NOT NULL
  AND (s.ssl IS NULL OR s.ssl = false);

-- All SSL connections
SELECT version, cipher, count(*)
FROM pg_stat_ssl
WHERE ssl = true
GROUP BY version, cipher;
```

**Alerts:**
- Any remote connection without SSL
- Certificate expiry < 30 days
- Backup repo without cipher enabled
- Unencrypted EBS/RDS instance detected (config audit)

---

## Compliance Quick Map

| Standard | Required methods |
|----------|------------------|
| **PCI-DSS 4.0** | TLS 1.2+, encrypted storage, encrypted backups, key management |
| **HIPAA** | TLS + at-rest encryption + access audit (pgAudit) |
| **SOC 2** | Encryption + rotation policy + monitoring |
| **GDPR** | At-rest + transit for personal data; column encryption for special categories |
| **ISO 27001** | Documented key lifecycle; LUKS/KMS; TLS |

---

## Related

- [SSL/TLS Implementation](ssl-tls-implementation.md)
- [TDE Implementation](tde-implementation.md)
- [Encryption Overview](encryption.md)
- [Authentication](authentication.md)
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
- [pgAudit](pgaudit.md)
- [pgBackRest](../04-backup-recovery/pg-backrest.md)
