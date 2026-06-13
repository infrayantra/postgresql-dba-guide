# PostgreSQL as a Service (DBaaS / Managed)

Guide to provisioning and operating PostgreSQL on managed cloud platforms and modern serverless providers — what the DBA still owns vs. what the provider handles.

---

## Managed vs. Self-Managed

| Responsibility | Self-managed (Linux/K8s) | DBaaS |
|----------------|--------------------------|-------|
| OS patching | You | Provider |
| PG minor upgrades | You (or auto) | Provider |
| PG major upgrades | You plan | Provider tools / assisted |
| HA / failover | You (Patroni, etc.) | Built-in |
| Backups / PITR | You configure | Built-in (verify retention!) |
| `postgresql.conf` tuning | Full control | Parameter groups (subset) |
| Extensions | Any | Allow-list |
| SSH / file system | Yes | No |
| Cost model | Infra + labor | $/hour + storage + IOPS |

**DBA role on DBaaS:** schema design, query tuning, security (IAM, network), backup verification, major upgrade planning, replication to analytics, compliance.

> **PostgreSQL 18 on DBaaS (2026):** AWS RDS, Aurora, Google Cloud SQL, and Azure Flexible Server support PG 18 — verify exact minor in your region via CLI/console before provisioning. Examples below use `--engine-version 18.x` / `POSTGRES_18`.

---

## AWS RDS for PostgreSQL

### Create via Console / CLI

```bash
aws rds create-db-instance \
  --db-instance-identifier myapp-prod \
  --db-instance-class db.r6g.xlarge \
  --engine postgres \
  --engine-version 18.1 \
  --master-username postgres \
  --master-user-password 'CHANGE_ME' \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --multi-az \
  --backup-retention-period 14 \
  --preferred-backup-window "03:00-04:00" \
  --vpc-security-group-ids sg-xxxxxxxx \
  --db-subnet-group-name private-db-subnets \
  --no-publicly-accessible \
  --deletion-protection \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --database-insights-mode advanced \
  --tags Key=Environment,Value=production
```

### Key RDS Concepts

| Feature | Notes |
|---------|-------|
| **Parameter groups** | Custom `postgresql.conf` settings — apply and reboot |
| **Option groups** | Extensions (pg_cron, postgis) — engine version specific |
| **Multi-AZ** | Sync standby in another AZ — automatic failover ~60–120s |
| **Read replicas** | Async, cross-region supported |
| **Storage autoscaling** | gp3/io1/io2 — monitor IOPS credits |
| **Performance Insights** | Wait event analysis — free tier 7 days retention |

### Parameter Group Example

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name pg18-oltp \
  --db-parameter-group-family postgres18 \
  --description "OLTP tuning"

aws rds modify-db-parameter-group \
  --db-parameter-group-name pg18-oltp \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
    "ParameterName=pg_stat_statements.track,ParameterValue=all,ApplyMethod=immediate" \
    "ParameterName=log_min_duration_statement,ParameterValue=500,ApplyMethod=immediate" \
    "ParameterName=random_page_cost,ParameterValue=1.1,ApplyMethod=immediate"
```

Then attach to instance and reboot if needed.

### IAM Database Authentication

```bash
# Enable on instance
aws rds modify-db-instance --db-instance-identifier myapp-prod \
  --enable-iam-database-authentication

# Generate auth token (15 min validity)
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname myapp-prod.xxxxx.us-east-1.rds.amazonaws.com \
  --port 5432 --username iam_db_user --region us-east-1)

psql "host=myapp-prod.xxxxx.us-east-1.rds.amazonaws.com port=5432 dbname=postgres \
  user=iam_db_user sslmode=require"
```

```sql
CREATE USER iam_db_user;
GRANT rds_iam TO iam_db_user;
```

### RDS Limitations (DBA Must Know)

- No superuser — use `rds_superuser` role (some restrictions)
- No file system / `COPY FROM` program — use `aws_s3` extension or `\copy`
- Cannot load arbitrary shared libraries
- `replication` slot management — logical replication supported (PG 10+)
- Extensions: check [AWS RDS extension list](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)

---

## AWS Aurora PostgreSQL

Aurora-compatible PostgreSQL wire protocol — storage layer is distributed, not local disk.

```bash
aws rds create-db-cluster \
  --db-cluster-identifier myapp-aurora \
  --engine aurora-postgresql \
  --engine-version 18.1 \
  --master-username postgres \
  --master-user-password 'CHANGE_ME' \
  --db-subnet-group-name private-db-subnets \
  --vpc-security-group-ids sg-xxxxxxxx \
  --storage-encrypted \
  --backup-retention-period 14

aws rds create-db-instance \
  --db-instance-identifier myapp-aurora-instance-1 \
  --db-cluster-identifier myapp-aurora \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql
```

| Aurora feature | Benefit |
|----------------|---------|
| Storage auto-scales to 128 TB | No provisioned storage sizing |
| Up to 15 read replicas | Low lag reader endpoints |
| Fast failover | ~30s typically |
| Backtrack (MySQL only) | N/A for PG |
| Global Database | Cross-region DR |
| Serverless v2 | Auto-scaling ACU |

**Endpoint types:** cluster (writer), reader (load-balanced replicas), custom endpoints.

---

## Google Cloud SQL for PostgreSQL

```bash
gcloud sql instances create myapp-prod \
  --database-version=POSTGRES_18 \
  --tier=db-custom-4-16384 \
  --region=us-central1 \
  --storage-type=SSD \
  --storage-size=100GB \
  --storage-auto-increase \
  --backup-start-time=03:00 \
  --enable-point-in-time-recovery \
  --availability-type=REGIONAL \
  --network=projects/PROJECT/global/networks/vpc-prod \
  --no-assign-ip \
  --database-flags=shared_preload_libraries=pg_stat_statements,log_min_duration_statement=500
```

### Cloud SQL Features

| Feature | Notes |
|---------|-------|
| **High availability (regional)** | Standby in another zone |
| **Read replicas** | Up to 10 |
| **Private IP** | VPC peering — preferred |
| **Cloud SQL Auth Proxy** | IAM + encrypted tunnel |
| **Query Insights** | Slow query analysis |
| **Maintenance window** | Auto minor version bumps |

### Connect via Auth Proxy

```bash
cloud-sql-proxy PROJECT:REGION:INSTANCE --port 5432

psql "host=127.0.0.1 port=5432 user=postgres dbname=app_db"
```

### IAM Authentication

```sql
CREATE USER "user@project.iam" WITH LOGIN;
GRANT cloudsqlsuperuser TO "user@project.iam";
```

---

## Azure Database for PostgreSQL

Two products — know which you use:

| Product | Status | Notes |
|---------|--------|-------|
| **Flexible Server** | Current — use this | Full VM-like control, zone redundant HA |
| Single Server | Retired / deprecated | Migrate to Flexible |

```bash
az postgres flexible-server create \
  --resource-group rg-prod \
  --name myapp-prod \
  --location eastus \
  --admin-user pgadmin \
  --admin-password 'CHANGE_ME' \
  --sku-name Standard_D4s_v3 \
  --tier GeneralPurpose \
  --storage-size 128 \
  --version 18 \
  --high-availability ZoneRedundant \
  --backup-retention 14 \
  --geo-redundant-backup Disabled \
  --public-access Disabled \
  --vnet myVnet \
  --subnet db-subnet
```

### Azure-Specific

- **Server parameters** = postgresql.conf equivalents
- **Azure AD authentication** for PostgreSQL
- **Private Link** for network isolation
- **Read replicas** in same or different regions
- **pgvector, PostGIS** available as extensions on Flexible Server

```bash
az postgres flexible-server parameter set \
  --resource-group rg-prod \
  --server-name myapp-prod \
  --name shared_preload_libraries \
  --value pg_stat_statements
```

---

## Comparison Matrix (Major Clouds)

| Capability | RDS PG | Aurora PG | Cloud SQL | Azure Flexible |
|------------|--------|-----------|-----------|----------------|
| **PG 18** | Yes (2026) | Yes | Yes | Yes |
| Multi-AZ / HA | Multi-AZ | Cluster storage | Regional | Zone redundant |
| Read scaling | Replicas | Many replicas | Replicas | Replicas |
| PITR | Yes | Yes | Yes | Yes |
| Custom extensions | Limited | Limited | Limited | Limited |
| Superuser | rds_superuser | rds_superuser | cloudsqlsuperuser | Partial |
| IAM auth | Yes | Yes | Auth Proxy | Azure AD |
| Logical replication | Yes | Yes | Yes | Yes |

---

## Serverless & Edge PostgreSQL

### Neon (Serverless Postgres)

- Storage/compute separation — scale to zero
- Branching (copy-on-write) for dev/preview environments
- Connection pooling built-in (PgBouncer)

```bash
# Connection string from Neon console
psql "postgresql://user:pass@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require"
```

**DBA notes:** cold start latency after idle; good for dev/staging and variable workloads.

### Supabase

- Managed Postgres + Auth + Storage + Realtime
- Based on PG — extensions: pgvector, postgis, pg_cron
- Connection pooler (Supavisor) on port 6543

```
# Direct connection (migrations, admin)
postgresql://postgres:pass@db.xxx.supabase.co:5432/postgres

# Pooled (application)
postgresql://postgres:pass@db.xxx.supabase.co:6543/postgres
```

### Crunchy Bridge / Aiven / Timescale Cloud

Fully managed with varying focus (HA, compliance, time-series). Pattern similar — connection string + parameter UI + backup SLAs.

---

## DBaaS Provisioning Checklist

### Network

- [ ] Private subnet only — no public IP in production
- [ ] Security group / firewall — app tier CIDR only on 5432
- [ ] TLS required (`sslmode=verify-full` with provider CA)

### Security

- [ ] Strong master password in secrets manager
- [ ] IAM / Azure AD / Cloud SQL Auth where available
- [ ] Separate app user (not master) with least privilege
- [ ] Enable encryption at rest (default on major clouds)
- [ ] Audit logging if compliance requires (pgaudit via extension where supported)

### Reliability

- [ ] Multi-AZ / regional HA enabled
- [ ] Backup retention ≥ business RPO (7–35 days typical)
- [ ] Test restore quarterly
- [ ] Deletion protection enabled

### Performance

- [ ] Right-size instance (CPU/RAM) — start with monitoring
- [ ] gp3/io2/SSD with provisioned IOPS if needed
- [ ] Parameter group tuned (shared_buffers, work_mem, pg_stat_statements)
- [ ] Connection pooling at app or PgBouncer layer

### Observability

- [ ] Enable Performance Insights / Query Insights
- [ ] CloudWatch / Cloud Monitoring / Azure Monitor alerts
- [ ] Disk space, CPU, connections, replication lag

---

## Migrating to / from DBaaS

### Into DBaaS (from self-managed)

```bash
# Logical — most portable
pg_dump -Fc -h old-host -U postgres app_db | \
  pg_restore -h rds-endpoint -U postgres -d app_db

# AWS DMS — minimal downtime
# GCP Database Migration Service
# Azure Database Migration Service
```

### Out of DBaaS (vendor exit)

```bash
pg_dump -Fc -h rds-endpoint -U postgres app_db -f export.dump
pg_restore -h self-hosted -U postgres -d app_db export.dump
```

Logical replication for near-zero downtime cutover (same pattern as major version upgrade).

---

## Cost Optimization Tips

| Tip | Savings |
|-----|---------|
| Reserved instances / committed use | 30–60% |
| Right-size after 2 weeks of metrics | Avoid over-provisioning |
| gp3 vs io1 | Often sufficient for OLTP |
| Read replicas only when read-bound | Replica cost |
| Serverless (Neon) for intermittent dev | Dev/staging |
| Archive old data to S3 (pg_dump / ETL) | Storage growth |

---

## When DBaaS Is the Wrong Choice

- Need obscure C extensions or custom PostgreSQL patches
- Regulatory requirement for full OS access
- Extreme tuning of kernel/WAL at hardware level
- Very predictable massive scale where bare metal wins on $/TPS

---

## Related

- [Linux Install](install-linux.md)
- [Kubernetes Install](install-kubernetes.md)
- [Authentication](../08-security/authentication.md)
- [Logical Backup](../04-backup-recovery/logical-backup.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
