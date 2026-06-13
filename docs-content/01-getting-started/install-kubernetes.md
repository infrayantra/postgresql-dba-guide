# PostgreSQL on Kubernetes

Running PostgreSQL on Kubernetes requires understanding **stateful workloads**, **persistent storage**, and **operator-managed HA**. Do not treat PostgreSQL like a stateless Deployment.

---

## Architecture Decision

| Approach | When to use | HA | Complexity |
|----------|-------------|-----|------------|
| **CloudNativePG (CNPG)** | Production K8s native PG | Yes (automatic failover) | Medium |
| **Zalando Postgres Operator** | Patroni-based, Spilo images | Yes | Medium |
| **Crunchy PGO** | Enterprise features, pgBackRest | Yes | Medium–High |
| **Bitnami Helm (StatefulSet)** | Dev/test, simple single instance | Manual | Low |
| **Self-managed StatefulSet** | Learning only — not prod | Manual | High |
| **External DBaaS** | Production without running PG in K8s | Provider-managed | Low |

**Production recommendation:** CNPG or Zalando operator — not raw StatefulSet alone.

---

## Prerequisites (All Options)

```bash
# Cluster with default StorageClass (SSD-backed)
kubectl get storageclass

# Install CNPG operator (example)
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml

kubectl get pods -n cnpg-system
```

Requirements:
- **Fast persistent volumes** (gp3, Premium SSD, local NVMe)
- **Adequate CPU/RAM** — PostgreSQL is memory-hungry
- **Backup target** (S3, GCS, Azure Blob)
- **Monitoring** (Prometheus Operator, Grafana)

---

## CloudNativePG (CNPG) — Recommended

Modern Kubernetes-native operator. Handles failover, backups, connection pooling integration, rolling upgrades.

### 1. Create Namespace & Secrets

```bash
kubectl create namespace database

kubectl -n database create secret generic postgres-superuser \
  --from-literal=username=postgres \
  --from-literal=password='STRONG_PASSWORD_HERE'
```

### 2. Cluster Manifest

```yaml
# cnpg-cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-prod
  namespace: database
spec:
  instances: 3                    # 1 primary + 2 replicas
  imageName: ghcr.io/cloudnative-pg/postgresql:18.0

  bootstrap:
    initdb:
      database: app_db
      owner: app_user
      secret:
        name: app-user-credentials
      dataChecksums: true
      encoding: UTF8
      localeCType: C
      localeCollate: C
      postInitSQL:
        - CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

  postgresql:
    parameters:
      max_connections: "200"
      shared_buffers: "1GB"
      effective_cache_size: "3GB"
      work_mem: "32MB"
      wal_level: "replica"
      max_wal_senders: "10"
      max_replication_slots: "10"
      log_min_duration_statement: "500"
      shared_preload_libraries: "pg_stat_statements"

  storage:
    size: 100Gi
    storageClass: gp3             # adjust for your cloud

  resources:
    requests:
      memory: "2Gi"
      cpu: "1"
    limits:
      memory: "4Gi"
      cpu: "2"

  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/pg-backups/
      s3Credentials:
        accessKeyId:
          name: s3-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: s3-creds
          key: SECRET_ACCESS_KEY
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: "30d"

  monitoring:
    enablePodMonitor: true
---
apiVersion: v1
kind: Secret
metadata:
  name: app-user-credentials
  namespace: database
type: kubernetes.io/basic-auth
stringData:
  username: app_user
  password: APP_USER_PASSWORD
```

```bash
kubectl apply -f cnpg-cluster.yaml
kubectl -n database get clusters
kubectl -n database get pods -l cnpg.io/cluster=postgres-prod
```

### 3. Connect to Primary

CNPG creates services: `-rw` (primary), `-ro` (replicas), `-r` (any).

```bash
# Port-forward for local access
kubectl -n database port-forward svc/postgres-prod-rw 5432:5432

psql "postgresql://app_user:PASS@localhost:5432/app_db"
```

From inside cluster:

```
postgresql://app_user:PASS@postgres-prod-rw.database.svc:5432/app_db
```

### 4. Scheduled Backups

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: postgres-prod-backup
  namespace: database
spec:
  schedule: "0 2 * * *"
  backupOwnerReference: self
  cluster:
    name: postgres-prod
  method: barmanObjectStore
```

### 5. Failover

CNPG automatically promotes most advanced replica on primary failure.

```bash
kubectl -n database cnpg status postgres-prod
kubectl -n database get pods -w   # watch promotion
```

### 6. Pooler (PgBouncer built-in)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: postgres-prod-pooler
  namespace: database
spec:
  cluster:
    name: postgres-prod
  instances: 2
  type: rw
  pgbouncer:
    poolMode: transaction
    parameters:
      max_client_conn: "1000"
      default_pool_size: "50"
```

Apps connect to `postgres-prod-pooler-rw.database.svc:5432`.

---

## Zalando Postgres Operator

Uses **Spilo** image (Patroni + WAL-E/WAL-G).

```bash
# Clone operator
git clone https://github.com/zalando/postgres-operator.git
cd postgres-operator
kubectl apply -k manifests/

# Or Helm
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm install postgres-operator postgres-operator-charts/postgres-operator
```

```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: my-cluster
  namespace: database
spec:
  teamId: "myteam"
  volume:
    size: 100Gi
    storageClass: gp3
  numberOfInstances: 3
  users:
    app_user: []
  databases:
    app_db: app_user
  postgresql:
    version: "18"
  resources:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

Connection via `-repl` and master `-pooler` services created by operator.

---

## Bitnami Helm Chart (Dev / Single Instance)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install postgres bitnami/postgresql \
  --namespace database \
  --create-namespace \
  --set auth.postgresPassword=secretpass \
  --set auth.database=app_db \
  --set primary.persistence.size=50Gi \
  --set primary.persistence.storageClass=gp3 \
  --set primary.extendedConfiguration="max_connections = 200\nshared_buffers = 512MB\n"
```

Get password:

```bash
kubectl get secret postgres-postgresql -n database \
  -o jsonpath="{.data.postgres-password}" | base64 -d
```

**Limitations:** HA mode exists but operator-based solutions are stronger for production failover.

---

## Raw StatefulSet (Educational — Not Production)

Illustrates why operators exist — you must handle failover, backups, upgrades yourself.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:18.0-bookworm
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
            - name: POSTGRES_INITDB_ARGS
              value: "--data-checksums"
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "2Gi"
          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 5
            periodSeconds: 5
  volumeClaimTemplates:
    - metadata:
        name: pgdata
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 50Gi
```

---

## Storage Best Practices

| Rule | Reason |
|------|--------|
| Use SSD/NVMe StorageClass | Random I/O performance |
| `ReadWriteOnce` only | PostgreSQL single writer |
| Avoid NFS for primary | Latency + locking issues (exceptions with specialized setups) |
| Size PVC with headroom | Disk expansion depends on CSI driver |
| Separate WAL disk (advanced) | CNPG/PGO support tablespace or dedicated mounts |

```yaml
# Volume expansion (if StorageClass allowVolumeExpansion: true)
kubectl -n database patch pvc postgres-prod-1 \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
# Then CNPG/PG may need rolling restart or online resize support
```

---

## Secrets & Configuration

```bash
# Never commit passwords — use Sealed Secrets, External Secrets Operator, or Vault
kubectl create secret generic postgres-app \
  --from-literal=uri="postgresql://user:pass@postgres-prod-rw:5432/app_db"
```

Mount `postgresql.conf` overrides via ConfigMap + operator-specific merge mechanism (CNPG: `spec.postgresql.parameters`).

---

## Upgrades on Kubernetes

**CNPG:**

```yaml
# Change imageName to new minor/major — rolling update
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4
```

Major version: follow CNPG upgrade documentation (logical replication or pg_upgrade job).

**General rule:** test upgrade on clone cluster first.

---

## Monitoring in K8s

```yaml
# CNPG PodMonitor (Prometheus Operator)
spec:
  monitoring:
    enablePodMonitor: true
```

Key alerts:
- Replication lag > threshold
- PVC usage > 85%
- Pod restart loop
- Backup job failure

---

## Anti-Patterns

| Don't | Do instead |
|-------|------------|
| Deployment (not StatefulSet) for PG | StatefulSet or Operator |
| EmptyDir for production data | PersistentVolumeClaim |
| Single replica in prod | 3 instances + sync rep |
| Manual failover scripts | CNPG / Patroni operator |
| Storing backups on same PV | S3/GCS off-cluster |

---

## Related

- [Docker Install](install-docker.md)
- [DBaaS](install-dbaas.md)
- [Streaming Replication](../05-replication-ha/streaming-replication.md)
- [Patroni](../05-replication-ha/patroni-pgpool.md)
- [pgBackRest](../04-backup-recovery/pg-backrest.md)
