# Architecture & Internals

> **PostgreSQL 18** adds an asynchronous I/O subsystem (`io_method`, `pg_aios`) and B-tree skip scan. Core MVCC/WAL/process model unchanged. See [postgresql-18.md](postgresql-18.md).

Understanding PostgreSQL internals helps DBAs diagnose performance issues, plan capacity, and make informed configuration choices.

## Multi-Process Architecture

PostgreSQL uses a **multi-process**, shared-memory model — not multi-threaded.

| Process | Role |
|---------|------|
| **postmaster** | Parent process; forks children, manages startup/shutdown |
| **backend** | One per client connection; executes SQL |
| **background writer** | Writes dirty shared buffers to disk gradually |
| **checkpointer** | Writes checkpoint records; flushes dirty pages at checkpoint |
| **WAL writer** | Flushes WAL buffers to `pg_wal/` |
| **autovacuum launcher** | Spawns autovacuum workers |
| **autovacuum worker** | Runs VACUUM/ANALYZE on selected tables |
| **stats collector** | Collects activity statistics (legacy; integrated in newer versions) |
| **archiver** | Copies completed WAL segments (if `archive_mode=on`) |
| **logical replication launcher** | Manages logical replication workers |
| **walsender / walreceiver** | Streaming replication processes |

## Memory Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Shared Memory                            │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ shared_     │  │ WAL buffers  │  │ lock tables, proc   │ │
│  │ buffers     │  │              │  │ array, clog, etc.   │ │
│  └─────────────┘  └──────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │                              │
   each backend also has private memory:
   work_mem, maintenance_work_mem, temp_buffers, catalog cache
```

### Key Memory Parameters

| Parameter | Scope | Purpose |
|-----------|-------|---------|
| `shared_buffers` | Cluster | Page cache for shared data |
| `effective_cache_size` | Planner hint | OS + PG cache estimate |
| `work_mem` | Per sort/hash op | Sorts, hashes, merges |
| `maintenance_work_mem` | Per maintenance op | VACUUM, CREATE INDEX |
| `wal_buffers` | Cluster | WAL write buffer |
| `temp_buffers` | Per session | Temp table buffer |

**Rule of thumb:** `shared_buffers` = 25% of RAM (up to ~8–16 GB on Linux); `effective_cache_size` = 50–75% of RAM.

→ Full guide: [In-Memory Features & Integration](../06-performance/in-memory-features-integration.md)

## Storage Model

### Pages and Tuples

- Default page size: **8 KB** (`BLCKSZ`, fixed at compile time)
- Rows (tuples) stored in pages within table files
- **TOAST** stores oversized values in separate tables
- **Visibility map** and **free space map** assist VACUUM and index-only scans

### File Layout

```
base/
  16384/          ← database OID
    16385         ← table filenode (can change after TRUNCATE/VACUUM FULL)
    16385_fsm     ← free space map
    16385_vm      ← visibility map
    16385_init    ← init fork (unlogged tables)
```

### OID vs. Relfilenode

```sql
SELECT oid, relfilenode, relname
FROM pg_class
WHERE relname = 'my_table';
-- After TRUNCATE or certain DDL, relfilenode changes
```

## MVCC (Multi-Version Concurrency Control)

Every row has system columns:

| Column | Meaning |
|--------|---------|
| `xmin` | Transaction ID that inserted the row |
| `xmax` | Transaction ID that deleted/updated (0 = live) |
| `ctid` | Physical location (block, offset) |

- **Readers don't block writers; writers don't block readers**
- `UPDATE` = DELETE + INSERT (new row version)
- Dead tuples remain until **VACUUM** reclaims space
- **Transaction ID wraparound** requires aggressive vacuuming of `pg_database.datfrozenxid`

```sql
-- Monitor XID age
SELECT datname, age(datfrozenxid) AS xid_age
FROM pg_database
ORDER BY xid_age DESC;
```

## Write-Ahead Log (WAL)

All changes go to WAL **before** data files (durability guarantee).

1. Backend modifies shared buffers + writes WAL record
2. WAL writer flushes WAL to disk (on commit if `synchronous_commit=on`)
3. Checkpointer creates checkpoint; background writer flushes dirty pages
4. Old WAL can be recycled after checkpoint

See [WAL Internals](../10-advanced/wal-internals.md) for depth.

## Query Processing Pipeline

```
SQL text
  → Parser (raw parse tree)
  → Analyzer (query tree, resolves names/types)
  → Rewriter (rules, views, RLS policies)
  → Planner/Optimizer (cost-based plan)
  → Executor (runs plan nodes: Seq Scan, Index Scan, Hash Join, etc.)
```

### Planner Inputs

- Table statistics (`pg_statistic`, from ANALYZE)
- Index definitions and selectivity estimates
- `random_page_cost`, `seq_page_cost`, `cpu_*_cost`
- `enable_*` flags (force/disable plan types for testing)

## System Catalogs

Metadata lives in `pg_catalog` schema:

```sql
-- Useful catalog tables
pg_class          -- tables, indexes, sequences
pg_attribute      -- columns
pg_index          -- index definitions
pg_constraint     -- PK, FK, CHECK, UNIQUE
pg_roles          -- roles/users
pg_database       -- databases
pg_settings       -- runtime parameters
pg_stat_*         -- activity and I/O statistics
```

## Connection Flow

```
Client → TCP 5432 → postmaster → fork backend
                                → read pg_hba.conf (auth method)
                                → authenticate (SCRAM, cert, etc.)
                                → SET parameters, run queries
```

## Table Access Methods

| AM | Use case |
|----|----------|
| **heap** | Default row storage |
| **btree** | Default index |
| **hash** | Equality-only indexes |
| **gin** | Full-text, arrays, jsonb |
| **gist** | Geometric, exclusion, full-text |
| **brin** | Very large, naturally ordered tables |
| **spgist** | Non-balanced data (text, networks) |

## Isolation Levels

| Level | Dirty read | Non-repeatable read | Phantom |
|-------|------------|---------------------|---------|
| Read Uncommitted | — (PG treats as Read Committed) | | |
| Read Committed | No | Yes | Yes |
| Repeatable Read | No | No | No* |
| Serializable | No | No | No |

*PostgreSQL's Repeatable Read prevents phantom reads via MVCC snapshot.

## Related

- [WAL Internals](../10-advanced/wal-internals.md)
- [Locking & Concurrency](../10-advanced/locking-concurrency.md)
- [VACUUM & Bloat](../06-performance/vacuum-bloat.md)
