# Creating Custom PostgreSQL Extensions

Guide to building, packaging, and deploying your own PostgreSQL extension for **PostgreSQL 18** (compatible with PG 14–17 where noted).

---

## When to Build an Extension vs. Alternatives

| Approach | Use when |
|----------|----------|
| **SQL-only extension** | New functions, views, types in SQL/plpgsql |
| **C extension** | Performance-critical code, new index AMs, hooks |
| **Background worker** | Scheduled/long-running in-process tasks |
| **Plain SQL migration** | One-off functions — no versioning needed |
| **Foreign Data Wrapper** | Remote data sources |

Extensions provide: **versioning**, **`CREATE EXTENSION`**, **`ALTER EXTENSION UPDATE`**, dependency tracking.

---

## Extension Structure

```
my_extension/
├── my_extension.control      # metadata
├── my_extension--1.0.sql       # install script
├── my_extension--1.0--1.1.sql  # upgrade script (optional)
├── my_extension.c              # C source (optional)
├── Makefile                    # PGXS build
└── README.md
```

---

## Step 1 — SQL-Only Extension (Simplest)

### my_extension.control

```ini
comment = 'My company utility functions'
default_version = '1.0'
module_pathname = '$libdir/my_extension'
relocatable = true
schema = public
requires = 'plpgsql'
superuser = false
```

For **pure SQL** extensions (no C code), omit `module_pathname` or use:

```ini
default_version = '1.0'
comment = 'SQL-only extension'
relocatable = true
```

### my_extension--1.0.sql

```sql
-- my_extension--1.0.sql
\echo Use "CREATE EXTENSION my_extension" to load this file. \quit

CREATE OR REPLACE FUNCTION my_extension.hello(name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'Hello, ' || name || ' from PG ' || current_setting('server_version');
$$;

CREATE OR REPLACE FUNCTION my_extension.add_audit_row(
  p_table regclass,
  p_action text,
  p_user text DEFAULT current_user
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO my_extension.audit_events (tbl, action, who, at)
  VALUES (p_table::text, p_action, p_user, now());
END;
$$;

CREATE TABLE IF NOT EXISTS my_extension.audit_events (
  id bigserial PRIMARY KEY,
  tbl text,
  action text,
  who text,
  at timestamptz DEFAULT now()
);

REVOKE ALL ON SCHEMA my_extension FROM PUBLIC;
GRANT USAGE ON SCHEMA my_extension TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA my_extension TO PUBLIC;
```

### Install manually (dev)

```bash
sudo mkdir -p /usr/share/pgsql/extension
sudo cp my_extension.control my_extension--1.0.sql /usr/share/pgsql/extension/

psql -c "CREATE EXTENSION my_extension;"
psql -c "SELECT my_extension.hello('DBA');"
```

On PGDG RHEL, path is often `/usr/pgsql-18/share/extension/`.

---

## Step 2 — C Extension with PGXS

### my_extension.c

```c
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(my_extension_add);

Datum
my_extension_add(PG_FUNCTION_ARGS)
{
    int32 arg1 = PG_GETARG_INT32(0);
    int32 arg2 = PG_GETARG_INT32(1);

    PG_RETURN_INT32(arg1 + arg2);
}
```

### my_extension--1.0.sql (with C function)

```sql
CREATE OR REPLACE FUNCTION my_extension.add(integer, integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'my_extension_add'
LANGUAGE C IMMUTABLE STRICT;
```

### Makefile (PGXS)

```makefile
EXTENSION = my_extension
DATA = my_extension--1.0.sql
MODULES = my_extension

PG_CONFIG = /usr/pgsql-18/bin/pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

### Build & install

```bash
sudo dnf install -y postgresql18-devel gcc make

cd my_extension
make
sudo make install

# Installs to:
# $(pg_config --pkglibdir)/my_extension.so
# $(pg_config --sharedir)/extension/my_extension*
```

```sql
CREATE EXTENSION my_extension;
SELECT my_extension.add(2, 3);   -- 5
```

---

## Step 3 — Version Upgrades

Add upgrade script `my_extension--1.0--1.1.sql`:

```sql
-- New function in 1.1
CREATE OR REPLACE FUNCTION my_extension.version()
RETURNS text LANGUAGE sql IMMUTABLE
AS $$ SELECT '1.1'::text $$;
```

Update control file:

```ini
default_version = '1.1'
```

Add `my_extension--1.1.sql` for fresh installs (copy of full schema at 1.1).

```sql
ALTER EXTENSION my_extension UPDATE TO '1.1';
SELECT extversion FROM pg_extension WHERE extname = 'my_extension';
```

---

## Step 4 — Packaging (RPM / Debian)

### RPM spec snippet

```spec
Name:           my_extension_18
Version:        1.0
Release:        1
Summary:        Custom PostgreSQL 18 extension
Requires:       postgresql18-server

%build
make PG_CONFIG=/usr/pgsql-18/bin/pg_config

%install
make install DESTDIR=%{buildroot} PG_CONFIG=/usr/pgsql-18/bin/pg_config

%files
%{_libdir}/my_extension.so
%{_datadir}/extension/my_extension*
```

---

## Step 5 — Background Worker Extension (Advanced)

For in-process schedulers or listeners:

```c
#include "postgres.h"
#include "postmaster/bgworker.h"
#include "storage/ipc.h"
#include "storage/latch.h"
#include "miscadmin.h"

PG_MODULE_MAGIC;

void _PG_init(void);

void
_PG_init(void)
{
    BackgroundWorker worker;

    if (!process_shared_preload_libraries_in_progress)
        return;

    MemSet(&worker, 0, sizeof(BackgroundWorker));
    worker.bgw_flags = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
    worker.bgw_start_time = BgWorkerStart_RecoveryFinished;
    snprintf(worker.bgw_name, BGW_MAXLEN, "my_extension worker");
    snprintf(worker.bgw_library_name, BGW_MAXLEN, "my_extension");
    snprintf(worker.bgw_function_name, BGW_MAXLEN, "my_extension_worker_main");
    worker.bgw_restart_time = BGW_DEFAULT_RESTART_INTERVAL;

    RegisterBackgroundWorker(&worker);
}
```

Requires `shared_preload_libraries = 'my_extension'` and restart.

---

## Extension Best Practices

| Practice | Why |
|----------|-----|
| Use dedicated schema (`my_extension`) | Avoid polluting `public` |
| `REVOKE ALL FROM PUBLIC` | Least privilege |
| Mark functions `IMMUTABLE`/`STABLE` correctly | Planner optimization |
| SQL upgrade scripts idempotent where possible | Safe re-run |
| Test on PG 14–18 if supporting multiple | API differences |
| Sign extensions in enterprise | Supply chain security |

---

## Testing

```bash
# Install check
make installcheck PG_CONFIG=/usr/pgsql-18/bin/pg_config

# Or manual regression SQL
psql -f sql/my_extension_test.sql
```

Example test:

```sql
BEGIN;
CREATE EXTENSION my_extension;
SELECT my_extension.add(1, 2) = 3 AS ok;
ROLLBACK;
```

---

## pg_upgrade Compatibility

- SQL-only extensions: usually fine
- C extensions: must rebuild `.so` for new major PG version
- After upgrade: `ALTER EXTENSION my_extension UPDATE;`

---

## Publish & Share

| Method | Audience |
|--------|----------|
| Internal RPM/DEB repo | Your organization |
| PGXN (pgxn.org) | PostgreSQL community |
| GitHub + releases | Open source |
| Private container image | K8s deployments |

### PGXN META.json (optional)

```json
{
  "name": "my_extension",
  "abstract": "Company utility functions",
  "version": "1.0.0",
  "maintainer": "dba@example.com",
  "license": "postgresql",
  "provides": { "my_extension": { "file": "sql/my_extension--1.0.sql", "version": "1.0.0" } },
  "meta-spec": { "version": "1.0.0", "url": "http://pgxn.org/meta/spec/" },
  "tags": ["utility", "audit"]
}
```

---

## Quick Reference Commands

```sql
CREATE EXTENSION my_extension;
CREATE EXTENSION my_extension SCHEMA app;
DROP EXTENSION my_extension;
DROP EXTENSION my_extension CASCADE;
ALTER EXTENSION my_extension UPDATE;
ALTER EXTENSION my_extension SET SCHEMA audit;
SELECT * FROM pg_available_extensions WHERE name = 'my_extension';
SELECT * FROM pg_extension;
```

```bash
pg_config --sharedir    # extension SQL/control files
pg_config --pkglibdir   # .so files
ls $(pg_config --sharedir)/extension/
```

---

## Related

- [Extensions Overview](extensions.md)
- [pgvector](pgvector.md)
- [pgAudit](pgaudit.md)
- [Major Version Upgrade](../09-maintenance/major-version-upgrade.md)
