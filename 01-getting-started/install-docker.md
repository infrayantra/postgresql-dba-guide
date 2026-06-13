# PostgreSQL on Docker

Deep guide for running PostgreSQL in containers — development through production-grade Docker Compose and image customization.

---

## Official Image Overview

**Image:** [`postgres`](https://hub.docker.com/_/postgres) on Docker Hub (Docker Official Image).

| Tag pattern | Example | Notes |
|-------------|---------|-------|
| `{major}` | `postgres:18` | Latest minor of major |
| `{major}.{minor}` | `postgres:18.3` | Pin minor for reproducibility |
| `{major}-{variant}` | `postgres:18-bookworm` | Debian base |
| `{major}-alpine` | `postgres:18-alpine` | Smaller; musl — test extensions |

**Production:** pin digest or exact minor tag — `postgres:18.0-bookworm@sha256:...`.

> **PG 18 note:** Official image initdb enables **data checksums by default**. Use `POSTGRES_INITDB_ARGS: "--no-data-checksums"` only for legacy migration scenarios.

---

## How the Entrypoint Works

On **first start** with empty data volume:

1. Runs `initdb` if `$PGDATA` is empty
2. Sets password from `POSTGRES_PASSWORD` (required unless `POSTGRES_HOST_AUTH_METHOD=trust`)
3. Creates user/db from `POSTGRES_USER`, `POSTGRES_DB`
4. Runs scripts in `/docker-entrypoint-initdb.d/` (`.sql`, `.sql.gz`, `.sh`)

On **subsequent starts:** skips init — data persists in volume.

```bash
# Init scripts run ONLY once — changing script after init has no effect
# To re-init: docker volume rm pgdata (destroys data!)
```

---

## Development — Docker Run

```bash
docker run -d \
  --name pg-dev \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=devpass \
  -e POSTGRES_DB=myapp \
  -p 5432:5432 \
  -v pg_dev_data:/var/lib/postgresql/data \
  postgres:18-bookworm
```

Connect:

```bash
docker exec -it pg-dev psql -U admin -d myapp
# or from host:
psql "postgresql://admin:devpass@localhost:5432/myapp"
```

---

## Production-Oriented Docker Compose

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:18.3-bookworm
    container_name: postgres-primary
    restart: unless-stopped
    shm_size: 256mb                    # important for shared_buffers + parallel workers
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
      POSTGRES_DB: app_db
      PGDATA: /var/lib/postgresql/data/pgdata   # subdir avoids volume mount root issues
    secrets:
      - pg_password
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./conf/postgresql.conf:/etc/postgresql/postgresql.conf:ro
      - ./init:/docker-entrypoint-initdb.d:ro
    ports:
      - "127.0.0.1:5432:5432"          # bind localhost only if on same host
    command:
      - "postgres"
      - "-c"
      - "config_file=/etc/postgresql/postgresql.conf"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d app_db"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 2G

secrets:
  pg_password:
    file: ./secrets/pg_password.txt

volumes:
  pgdata:
    driver: local
```

### Custom postgresql.conf Mount

```ini
# conf/postgresql.conf — minimal production overrides
listen_addresses = '*'
max_connections = 100
shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 32MB
maintenance_work_mem = 256MB
wal_level = replica
max_wal_size = 2GB
log_min_duration_statement = 500
shared_preload_libraries = 'pg_stat_statements'
```

### Init Script Example

```sql
-- init/01-extensions.sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- init/02-app-schema.sql
CREATE ROLE app_user LOGIN PASSWORD 'change_in_prod';
GRANT CONNECT ON DATABASE app_db TO app_user;
\c app_db
CREATE SCHEMA app AUTHORIZATION app_user;
```

---

## Environment Variables Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `POSTGRES_PASSWORD` | — | Superuser password (**required** unless trust) |
| `POSTGRES_PASSWORD_FILE` | — | Docker secret path (preferred) |
| `POSTGRES_USER` | `postgres` | Superuser name |
| `POSTGRES_DB` | same as user | Default database created |
| `POSTGRES_INITDB_ARGS` | — | Extra args: `--data-checksums` |
| `POSTGRES_HOST_AUTH_METHOD` | `scram-sha-256` | `trust`/`md5`/`scram-sha-256` |
| `PGDATA` | `/var/lib/postgresql/data` | Data directory inside container |

### Enable Checksums at Init

```yaml
environment:
  POSTGRES_INITDB_ARGS: "--data-checksums --auth-host=scram-sha-256"
```

---

## Networking Patterns

### Same Compose Stack (App + DB)

```yaml
services:
  app:
    image: myapp:latest
    environment:
      DATABASE_URL: postgresql://app_user:pass@postgres:5432/app_db
    depends_on:
      postgres:
        condition: service_healthy
  postgres:
    # ... no ports exposed to host — internal network only
```

### External Access via Reverse Proxy / TLS

Do not expose 5432 publicly without TLS + firewall. Options:
- WireGuard / VPN to Docker host
- HAProxy with TLS termination
- Cloud Load Balancer → container

---

## Backup in Docker

```bash
# Logical backup
docker exec postgres-primary pg_dump -U postgres -Fc app_db > backup.dump

# Restore
docker exec -i postgres-primary pg_restore -U postgres -d app_db --clean < backup.dump

# Volume snapshot (host-level)
docker run --rm -v pgdata:/data -v $(pwd):/backup alpine \
  tar czf /backup/pgdata-$(date +%F).tar.gz -C /data .
```

For production: sidecar or cron container with `pg_dump` / pgBackRest pushing to S3.

---

## Streaming Replication (Docker Compose)

```yaml
services:
  postgres-primary:
    image: postgres:18-bookworm
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/pg_password
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"
    volumes:
      - pg_primary:/var/lib/postgresql/data
      - ./primary/init-replication.sh:/docker-entrypoint-initdb.d/99-replication.sh
    command:
      - postgres
      - -c
      - wal_level=replica
      - -c
      - max_wal_senders=5
      - -c
      - max_replication_slots=5
      - -c
      - hot_standby=on
    secrets: [pg_password]

  postgres-replica:
    image: postgres:18-bookworm
    environment:
      PGUSER: replicator
      PGPASSWORD_FILE: /run/secrets/repl_password
    volumes:
      - pg_replica:/var/lib/postgresql/data
      - ./replica/entrypoint.sh:/entrypoint.sh
    entrypoint: ["/entrypoint.sh"]
    depends_on:
      - postgres-primary
    secrets: [pg_password, repl_password]

secrets:
  pg_password:
    file: ./secrets/pg_password.txt
  repl_password:
    file: ./secrets/repl_password.txt

volumes:
  pg_primary:
  pg_replica:
```

```bash
#!/bin/bash
# primary/init-replication.sh — runs on first primary init
psql -v ON_ERROR_STOP=1 -U postgres <<-EOSQL
  CREATE USER replicator REPLICATION LOGIN PASSWORD '${REPL_PASSWORD:-replpass}';
EOSQL
echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
```

Replica bootstrap typically uses `pg_basebackup` in entrypoint script against `postgres-primary:5432`.

---

## Custom Dockerfile (Extensions)

When you need PostGIS, pgvector, etc. baked in:

```dockerfile
FROM postgres:18-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-18-postgis-3 \
    postgresql-18-pgvector \
    && rm -rf /var/lib/apt/lists/*

COPY init-extensions.sql /docker-entrypoint-initdb.d/
```

```sql
-- init-extensions.sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS vector;
```

Build:

```bash
docker build -t mypostgis:18 .
```

**Alternative:** use community images — `postgis/postgis:18-3.5`, `pgvector/pgvector:pg18`.

---

## Docker Production Checklist

- [ ] Pin image version or digest
- [ ] `POSTGRES_INITDB_ARGS=--data-checksums`
- [ ] Secrets via files, not env in plain compose committed to git
- [ ] Named volume or bind mount on fast disk (not container layer)
- [ ] `shm_size` ≥ 256MB (or 25% of shared_buffers)
- [ ] `healthcheck` + app `depends_on: condition: service_healthy`
- [ ] Resource limits (`deploy.resources` or `--memory`)
- [ ] No public port 5432 unless TLS + IP allowlist
- [ ] Automated backup to external storage
- [ ] Monitor with postgres_exporter sidecar

---

## Common Pitfalls

| Issue | Cause | Fix |
|-------|-------|-----|
| Init scripts didn't run | Volume not empty | `docker volume rm` or new volume |
| Slow performance | Default `shm_size` 64MB | Set `shm_size: 256mb`+ |
| Permission errors on bind mount | UID mismatch (postgres=999) | `chown 999:999` host dir or named volume |
| Data lost on recreate | No volume | Always mount `/var/lib/postgresql/data` |
| Can't enable checksums later | initdb-time only | Re-init with fresh volume |

---

## Rootless Docker / Podman

```bash
podman run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=pass \
  -v pgdata:/var/lib/postgresql/data:Z \
  -p 5432:5432 \
  docker.io/library/postgres:18
```

SELinux `:Z` flag on volumes (Fedora/RHEL).

---

## Related

- [Kubernetes Install](install-kubernetes.md)
- [Linux Install](install-linux.md)
- [Physical Backup](../04-backup-recovery/physical-backup.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
