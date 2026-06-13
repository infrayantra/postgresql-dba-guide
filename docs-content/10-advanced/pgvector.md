# pgvector — Vector Search & AI Embeddings

**pgvector** adds the `vector` type and similarity search operators to PostgreSQL — store embeddings from OpenAI, Hugging Face, etc., and query with SQL.

---

## Use Cases

- Semantic search (RAG — retrieval augmented generation)
- Recommendation engines
- Image/audio embedding similarity
- Hybrid search: vector + full-text + filters

---

## Install

### RHEL / PGDG

```bash
sudo dnf install -y pgvector_18
# or: postgresql18-pgvector depending on repo naming
```

### Debian / Ubuntu

```bash
sudo apt install -y postgresql-18-pgvector
```

### Docker

```dockerfile
FROM postgres:18-bookworm
RUN apt-get update && apt-get install -y postgresql-18-pgvector
```

Or use `pgvector/pgvector:pg18` image.

### Source (if package unavailable)

```bash
git clone https://github.com/pgvector/pgvector.git
cd pgvector
make PG_CONFIG=/usr/pgsql-18/bin/pg_config
sudo make install
```

### Enable

```sql
CREATE EXTENSION vector;
SELECT extversion FROM pg_extension WHERE extname = 'vector';
```

---

## Basic Usage

### Create table with embeddings

```sql
CREATE TABLE documents (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL,
  body text,
  embedding vector(1536)    -- dimension must match your model (OpenAI ada-002 = 1536)
);

-- Sample insert (embedding from application)
INSERT INTO documents (title, body, embedding)
VALUES (
  'PostgreSQL HA',
  'Patroni etcd HAProxy setup...',
  '[0.1, 0.2, ...]'::vector   -- 1536 floats from your embedding API
);
```

### Distance operators

| Operator | Distance | Index type |
|----------|----------|------------|
| `<->` | L2 (Euclidean) | `vector_l2_ops` (default) |
| `<#>` | Inner product | `vector_ip_ops` |
| `<=>` | Cosine | `vector_cosine_ops` |

```sql
-- Nearest neighbors (cosine — common for normalized embeddings)
SELECT id, title, embedding <=> '[0.1, 0.2, ...]'::vector AS distance
FROM documents
ORDER BY embedding <=> '[0.1, 0.2, ...]'::vector
LIMIT 10;
```

---

## Indexing

Without an index, search is sequential — fine for < 100k rows.

### IVFFlat (approximate — faster build)

```sql
CREATE INDEX ON documents
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

-- lists ≈ sqrt(row_count) for starters; rebuild after bulk load
```

Tuning:

```sql
SET ivfflat.probes = 10;   -- higher = better recall, slower (session-level)
```

### HNSW (recommended on PG 18)

```sql
CREATE INDEX ON documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

SET hnsw.ef_search = 40;   -- search-time tuning
```

**Rule:** Build indexes **after** bulk loading data.

---

## Hybrid Search Example

```sql
CREATE INDEX ON documents USING gin (to_tsvector('english', body));

SELECT id, title,
       embedding <=> $1::vector AS vec_dist,
       ts_rank(to_tsvector('english', body), plainto_tsquery('english', $2)) AS text_rank
FROM documents
WHERE to_tsvector('english', body) @@ plainto_tsquery('english', $2)
   OR embedding <=> $1::vector < 0.5
ORDER BY (vec_dist * 0.7 + (1 - text_rank) * 0.3)
LIMIT 20;
```

---

## Application Integration

### Python (psycopg + OpenAI)

```python
import psycopg
from openai import OpenAI

client = OpenAI()
text = "How to set up PostgreSQL HA?"
emb = client.embeddings.create(model="text-embedding-3-small", input=text).data[0].embedding

with psycopg.connect("postgresql://user:pass@localhost/app") as conn:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, title FROM documents ORDER BY embedding <=> %s::vector LIMIT 5",
            (str(emb),)
        )
        print(cur.fetchall())
```

Register vector type with psycopg3: `from pgvector.psycopg import register_vector`.

---

## Maintenance

```sql
-- Table size
SELECT pg_size_pretty(pg_total_relation_size('documents'));

-- Reindex after many updates
REINDEX INDEX CONCURRENTLY documents_embedding_idx;

-- Vacuum
VACUUM (ANALYZE) documents;
```

---

## HA / Replication

- pgvector indexes replicate via physical streaming replication
- After failover, indexes valid on new primary — no special cutover
- Logical replication: include `vector` columns in publication

---

## Cloud Availability

| Platform | pgvector |
|----------|----------|
| RDS PostgreSQL | Yes (extension) |
| Aurora PG | Yes |
| Cloud SQL | Check extension list |
| Azure Flexible | Yes |
| Supabase | Pre-enabled |

```sql
-- RDS
CREATE EXTENSION vector;
```

---

## Performance Tips

| Tip | Reason |
|-----|--------|
| Match index ops to query operator | Cosine queries need `vector_cosine_ops` |
| Normalize embeddings for cosine | Consistent distance scale |
| Batch inserts | COPY faster than row-by-row |
| Limit dimensions | Storage = 4 bytes × dimensions per row |
| Use HNSW for production ANN | Better recall than IVFFlat at scale |
| `work_mem` for index build | Large indexes need memory |

---

## Related

- [Extensions Overview](extensions.md)
- [Indexing](../06-performance/indexing.md)
- [Creating Custom Extensions](creating-extensions.md)
