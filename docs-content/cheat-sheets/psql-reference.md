# psql — Complete Reference (Basics & Advanced)

Interactive terminal and batch SQL client for **PostgreSQL 18**. Binary: `/usr/pgsql-18/bin/psql`.

> Quick CLI cheat sheet: [psql-commands.md](psql-commands.md) · [Admin SQL](admin-sql.md)

---

## Connection

### Command line

```bash
# Basic
psql -h localhost -p 5432 -U postgres -d mydb

# URI (password via PGPASSWORD or .pgpass)
psql "postgresql://user:pass@host:5432/mydb?sslmode=require"

# Service file (~/.pg_service.conf)
psql service=production

# Single command, no interactive
psql -d mydb -c "SELECT version();"

# Execute SQL file
psql -d mydb -f /path/script.sql
psql -d mydb -f script.sql -o output.txt -L session.log

# On error stop (scripts)
psql -d mydb -v ON_ERROR_STOP=1 -f migrate.sql

# Quiet (scripts)
psql -q -d mydb -f seed.sql
```

### Environment variables

| Variable | Purpose |
|----------|---------|
| `PGHOST` | Server host |
| `PGPORT` | Port (default 5432) |
| `PGUSER` | Username |
| `PGPASSWORD` | Password (avoid in production shells) |
| `PGDATABASE` | Database name |
| `PGSSLMODE` | `disable`, `require`, `verify-full` |
| `PGAPPNAME` | Application name in `pg_stat_activity` |
| `PGOPTIONS` | Extra `-c` settings |
| `PGSERVICE` | Default service name |

### ~/.pgpass

```
hostname:port:database:username:password
*:*:mydb:app_user:secret
```

```bash
chmod 600 ~/.pgpass
```

### ~/.pg_service.conf

```ini
[production]
host=pg-primary.example.com
port=5432
dbname=app_db
user=dba
sslmode=verify-full
```

---

## Session Startup Files

Executed in order on connect:

1. `$PSQLRC` (env var)
2. `~/.psqlrc`
3. `./.psqlrc` (current dir, if `-X` not used)

Example `~/.psqlrc`:

```sql
\pset pager on
\pset null '(null)'
\timing on
\set PROMPT1 '%[%033[1;32m%]%n@%M:%/%R%[%033[0m%]%# '
\set PROMPT2 '%R> '
```

Skip startup files: `psql -X`

---

## Meta-Commands (Backslash)

Meta-commands are psql-specific — not SQL. No semicolon required.

### Help

| Command | Action |
|---------|--------|
| `\?` | List all psql commands |
| `\h` | SQL command help list |
| `\h SELECT` | Help for SELECT |
| `\copyright` | PostgreSQL license |
| `\q` | Quit |

### Connection & databases

| Command | Action |
|---------|--------|
| `\conninfo` | Current connection info |
| `\c dbname` | Connect to database |
| `\c dbname user` | Connect as user |
| `\c -` | Reconnect to previous DB |
| `\l` | List databases |
| `\l+` | List with size, description |
| `\du` | List roles |
| `\du+` | Roles with attributes, description |
| `\dg` | List role grants (same as `\du`) |
| `\dn` | List schemas |
| `\dn+` | Schemas with description, access |

### Object listing

| Command | Action |
|---------|--------|
| `\dt` | Tables in search_path |
| `\dt *.*` | All tables all schemas |
| `\dt+` | Tables with size |
| `\dt schema.*` | Tables in schema |
| `\d table` | Describe table |
| `\d+ table` | Describe with storage, description |
| `\di` | Indexes |
| `\di+` | Indexes with size |
| `\ds` | Sequences |
| `\dv` | Views |
| `\dm` | Materialized views |
| `\df` | Functions |
| `\df+` | Functions with detail |
| `\dF` | Text search configurations |
| `\dT` | Data types |
| `\dC` | Casts |
| `\dx` | Extensions |
| `\dx+` | Extensions with version, schema |
| `\dy` | Event triggers |
| `\dE` | Foreign tables |
| `\dRp` | Publications (logical replication) |
| `\dRs` | Subscriptions |
| `\d` | All relations matching pattern |
| `\dp` | Access privileges |
| `\z table` | Same as `\dp table` |
| `\dd` | Object comments |
| `\dD` | Domains |
| `\do` | Operators |
| `\dO` | Collations |
| `\drds` | Role/database settings |

### Pattern modifiers (with `\d`, `\dt`, etc.)

| Pattern | Meaning |
|---------|---------|
| `*` | All objects |
| `t*` | Objects starting with `t` |
| `*abc*` | Contains `abc` |
| `schema.table` | Qualified name |

### Output formatting (`\pset`)

```sql
\pset pager off              -- disable less/more
\pset pager always           -- always use pager
\pset format aligned         -- default column layout
\pset format unaligned       -- no padding (for scripts)
\pset format wrapped         -- wrap wide columns
\pset format html            -- HTML table
\pset format latex           -- LaTeX tabular
\pset tuples_only on         -- no headers/footers (CSV-like)
\pset null '[NULL]'          -- display for NULL
\pset border 2               -- border style 0-2
\pset linestyle unicode       -- unicode box drawing
\pset columns 120            -- terminal width
\pset title 'My Report'      -- query result title
\pset footer off
\pset expanded on            -- vertical rows (same as \x)
\pset fieldsep ','           -- field separator
\pset recordsep '\n'         -- record separator
\pset tableattr 'border="1"' -- HTML attributes
```

Shorthand: `\a` (unaligned), `\t` (tuples only), `\x` (expanded).

### Query execution

| Command | Action |
|---------|--------|
| `\e` | Edit query in `$EDITOR` |
| `\ef funcname` | Edit function definition |
| `\ev viewname` | Edit view definition |
| `\s` | Show query history |
| `\s filename` | Save history to file |
| `\i file.sql` | Include/run SQL file |
| `\ir file.sql` | Include relative to current `\i` file |
| `\o file.txt` | Send query output to file |
| `\o` | Stop writing to file |
| `\g` | Execute current query buffer |
| `\gdesc` | Describe last query result columns |
| `\gx` | Execute in expanded mode |
| `\gset` | Store single-row result in variables |
| `\gexec` | Execute each row as SQL |
| `\watch [sec]` | Re-run every N seconds (default 5) |
| `\reset` | Clear query buffer |
| `\w filename` | Write buffer to file |

### Variables (`\set`, `\unset`)

```sql
\set foo bar
\echo :foo
\set mytable orders
SELECT count(*) FROM :mytable;        -- won't work — identifiers need different approach

-- Safe identifier substitution
\set mytable orders
SELECT count(*) FROM :"mytable";

-- From query result
SELECT 42 AS answer \gset
\echo :answer

-- Multiple columns
SELECT current_database() AS db, current_user AS usr \gset
\echo Connected to :db as :usr

-- Shell interpolation (careful — injection risk)
\set dbname mydb
\connect :dbname
```

```sql
\unset foo
\set ECHO all                 -- print each command before execute
\set ECHO queries             -- print queries only
\set ON_ERROR_STOP on         -- exit on first SQL error (scripts)
\set AUTOCOMMIT off           -- manual COMMIT
\set FETCH_COUNT 1000         -- fetch in batches (large results)
```

### Copy & shell

```sql
\copy table TO '/tmp/out.csv' CSV HEADER
\copy table FROM '/tmp/in.csv' CSV HEADER
\copy (SELECT * FROM orders WHERE id < 100) TO STDOUT CSV HEADER

\! ls -la /tmp                -- shell command
\cd /tmp                      -- change shell cwd (not SQL)
\timing on                    -- show query duration
```

### Transaction visibility

```sql
\echo :AUTOCOMMIT
\set AUTOCOMMIT off
BEGIN;
UPDATE ...;
COMMIT;
```

### Information & system

```sql
\df+ pg_catalog.pg_get_
\lo_list                      -- large objects
\lo_export 12345 /tmp/file
\encoding UTF8
\password                     -- change own password
\conninfo
\sf funcname                  -- show function source
\sv viewname                  -- show view definition
```

---

## Advanced Patterns

### Script with variables

```sql
-- deploy_check.sql
\set ON_ERROR_STOP on
\timing on

\echo '=== Version ==='
SELECT version();

\echo '=== Replication ==='
SELECT pg_is_in_recovery();

\echo '=== Archive ==='
SELECT * FROM pg_stat_archiver;

\echo '=== Top 5 tables ==='
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 5;
```

```bash
psql service=prod -f deploy_check.sql -o report.txt
```

### Dynamic SQL from query (`\gexec`)

```sql
SELECT format('SELECT pg_terminate_backend(%s);', pid)
FROM pg_stat_activity
WHERE datname = 'app_db' AND state = 'idle'
  AND state_change < now() - interval '2 hours'
\gexec
```

### Conditional connect

```sql
\if :{?PROD}
  \connect service=production
\else
  \connect service=dev
\endif
```

Run: `psql -v PROD=1 -f script.sql`

### Export query to CSV (no superuser file access)

```sql
\pset format unaligned
\pset tuples_only on
\pset fieldsep ','
\o /tmp/report.csv
SELECT id, name, created_at FROM orders;
\o
```

Or `\copy` (client-side, uses your filesystem permissions).

### Watch replication lag

```sql
SELECT now(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp()
\watch 5
```

### Repeatable performance test

```sql
\timing on
\set iterations 10
SELECT i FROM generate_series(1, :iterations) i \gset

-- run query manually between timing checks, or use shell loop
```

---

## SQL in psql — Useful DBA Snippets

```sql
-- Settings
SHOW ALL;
SHOW shared_buffers;
SELECT name, setting, unit, source, context
FROM pg_settings WHERE name LIKE 'log%';

-- Sizes
SELECT pg_size_pretty(pg_database_size(current_database()));
\dt+

-- Activity
SELECT pid, usename, datname, state, wait_event_type, wait_event,
       left(query, 80) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid();

-- Locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Cancel / terminate
SELECT pg_cancel_backend(12345);
SELECT pg_terminate_backend(12345);

-- Reload config
SELECT pg_reload_conf();

-- Checkpoint
CHECKPOINT;

-- Extension list
\dx
```

---

## Output for Automation

```bash
# CSV export one query
psql -d mydb -t -A -F',' -c "SELECT id, name FROM users" > users.csv

# JSON (PG 18+ psql supports \pset format, or use SQL)
psql -d mydb -t -c "SELECT json_agg(t) FROM (SELECT * FROM users LIMIT 10) t"

# Quiet exit code check
psql -d mydb -c "SELECT 1" -q -t -A && echo OK || echo FAIL
```

| Flag | Meaning |
|------|---------|
| `-t` | Tuples only |
| `-A` | Unaligned |
| `-F','` | Field separator |
| `-R '---'` | Record separator |
| `-P format=unaligned` | Same as `-A` |
| `-P tuples_only=on` | Same as `-t` |
| `-v var=value` | Set variable |
| `-1` | Single transaction (all `-c` / `-f`) |
| `-L file` | Log session to file |
| `-o file` | Put query output in file |
| `-e` | Echo queries (same as `\set ECHO queries`) |
| `-E` | Echo `\d` generated queries |
| `-n` | Read-only (PG 14+ `default_transaction_read_only`) |

---

## Read-Only & Role Restrictions

```bash
# PG 14+
psql -n -d mydb   # default_transaction_read_only = on

# Limit via pg_hba + role
ALTER ROLE readonly SET default_transaction_read_only = on;
```

---

## Common Issues

| Issue | Fix |
|-------|-----|
| `FATAL: password authentication failed` | Check `.pgpass`, `pg_hba.conf` |
| `could not connect to server` | `pg_isready`; firewall; `listen_addresses` |
| `\copy: permission denied` | Client path permissions (not server) |
| `SSL connection required` | `sslmode=require` in connection |
| Garbled `\pset linestyle unicode` | Use `ascii` or `old-ascii` |
| `:variable` not expanded | Use `\set` first; `\echo :var` to test |
| Script continues after error | `\set ON_ERROR_STOP on` |

---

## psql vs Other Clients

| Feature | psql | GUI (DBeaver, pgAdmin) |
|---------|------|------------------------|
| Scripting / CI | Excellent | Limited |
| `\copy` client-side | Yes | Varies |
| `\watch` | Built-in | Manual refresh |
| `\gexec` dynamic SQL | Yes | Rare |
| Visual plans | `\x` + EXPLAIN | Graphical |

---

## Related

- [psql-commands.md](psql-commands.md) — CLI quick reference
- [admin-sql.md](admin-sql.md) — DBA SQL queries
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
- [Cluster Management](../03-administration/cluster-management.md)
- [Logging](../07-monitoring/logging.md)
