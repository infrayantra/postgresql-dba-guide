# Extensions

PostgreSQL extensions add functionality via `CREATE EXTENSION`.

## Deep-Dive Guides

| Extension / Topic | Guide |
|-------------------|-------|
| **pgvector** | [pgvector.md](pgvector.md) — embeddings, HNSW/IVFFlat indexes |
| **pgAudit** | [pgaudit.md](pgaudit.md) — compliance audit logging |
| **pg_cron / pgAgent** | [pg-cron-agent.md](pg-cron-agent.md) — scheduled SQL jobs |
| **Build your own** | [creating-extensions.md](creating-extensions.md) — SQL & C extensions |

---

## Popular Extensions

| Extension | Purpose | Needs shared_preload |
|-----------|---------|---------------------|
| pg_stat_statements | Query performance stats | **Yes** |
| pgvector | Vector / AI similarity search | No |
| pgcrypto | Crypto functions | No |
| pg_trgm | Trigram fuzzy search | No |
| postgis | Geospatial | No |
| citext | Case-insensitive text | No |
| uuid-ossp | UUID generation | No |
| pg_partman | Partition management | No |
| pg_repack | Online bloat removal | No |
| pgaudit | Audit logging | **Yes** |
| pg_cron | In-database job scheduler | **Yes** |
| auto_explain | Log slow plan details | **Yes** |
| pglogical | Logical replication (3rd party) | **Yes** |
| timescaledb | Time-series hypertables | **Yes** |

---

## Install & Enable

```bash
# Package (RHEL / PG 18)
sudo dnf install -y postgresql18-contrib postgresql18-pg-stat-statements pgvector_18 pgaudit18_18 pg_cron_18

# SQL
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION pgaudit;
CREATE EXTENSION pg_cron;
```

---

## Check Available & Installed

```sql
SELECT * FROM pg_available_extensions ORDER BY name;
SELECT extname, extversion FROM pg_extension;
ALTER EXTENSION postgis UPDATE TO '3.4.0';
```

---

## shared_preload_libraries

Required for libraries loading at postmaster start:

```ini
shared_preload_libraries = 'pg_stat_statements,pgaudit,pg_cron,auto_explain'
cron.database_name = 'postgres'
```

**Restart required.** Then `CREATE EXTENSION` in each database.

---

## pg_trgm Example

```sql
CREATE EXTENSION pg_trgm;
CREATE INDEX idx_names_trgm ON users USING gin (name gin_trgm_ops);
SELECT * FROM users WHERE name % 'john';
```

---

## PostGIS

```sql
CREATE EXTENSION postgis;
CREATE TABLE places (
  id serial PRIMARY KEY,
  name text,
  geom geometry(Point, 4326)
);
CREATE INDEX idx_places_geom ON places USING gist (geom);
```

---

## Extension in Template

```sql
CREATE EXTENSION pg_stat_statements;
\c template1
CREATE EXTENSION pg_stat_statements;
```

---

## Upgrade Extensions After PG Upgrade

```sql
ALTER EXTENSION pg_stat_statements UPDATE;
ALTER EXTENSION vector UPDATE;
ALTER EXTENSION pgaudit UPDATE;
```

---

## Related

- [pgvector](pgvector.md)
- [pgAudit](pgaudit.md)
- [pg_cron & pgAgent](pg-cron-agent.md)
- [Creating Custom Extensions](creating-extensions.md)
- [pg_stat_statements](../07-monitoring/pg-stat-statements.md)
- [Partitioning](partitioning.md)
- [Auditing](../08-security/auditing.md)
