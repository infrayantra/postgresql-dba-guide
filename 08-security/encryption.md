# Encryption — Overview

All encryption options for PostgreSQL **18** — start with the **[Encryption Methods](encryption-methods.md)** reference for comparison and decision matrix.

---

## Guides

| Topic | Document |
|-------|----------|
| **All methods compared** (transit + at rest) | [encryption-methods.md](encryption-methods.md) |
| **TLS / SSL implementation** | [ssl-tls-implementation.md](ssl-tls-implementation.md) |
| **TDE / data at rest** | [tde-implementation.md](tde-implementation.md) |

---

## At a Glance

| Layer | Methods |
|-------|---------|
| **In transit** | TLS server cert · mTLS · proxy TLS · cloud TLS |
| **At rest** | LUKS · EBS/Azure/GCP · pgBackRest · S3 SSE-KMS · pgcrypto · pg_tde |
| **Authentication** | SCRAM-SHA-256 (hash, not wire encryption — pair with TLS) |

**Production minimum:** TLS `verify-full` + encrypted volume + encrypted backups + SCRAM.

---

## Combined Production Stack

```
App ──TLS verify-full──► HAProxy/PG :5432
                              │
                         $PGDATA on LUKS/EBS encrypted volume
                              │
                         WAL archive → S3 SSE-KMS
                              │
                         pgBackRest → AES-256 encrypted repo
                              │
                         pgAudit → immutable log store
```

---

## Related

- [Encryption Methods — Complete Reference](encryption-methods.md)
- [SSL/TLS Implementation](ssl-tls-implementation.md)
- [TDE Implementation](tde-implementation.md)
- [Authentication](authentication.md)
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
