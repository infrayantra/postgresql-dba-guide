# psql & CLI Commands

> **Full reference:** [psql-reference.md](psql-reference.md) — basics, advanced `\pset`, `\gexec`, `\watch`, scripting, variables.

> **PostgreSQL 18** (PGDG): binaries at `/usr/pgsql-18/bin`, service `postgresql-18`. See [VERSION.md](../VERSION.md).

## psql Connection

```bash
psql -h host -p 5432 -U user -d dbname
psql "postgresql://user:pass@host:5432/db?sslmode=require"
psql service=myapp
```

## psql Meta-Commands

| Command | Action |
|---------|--------|
| `\l` | List databases |
| `\c dbname` | Connect to database |
| `\dt` | List tables |
| `\dt+` | Tables with sizes |
| `\d table` | Describe table |
| `\di` | List indexes |
| `\du` | List roles |
| `\dn` | List schemas |
| `\df` | List functions |
| `\dv` | List views |
| `\dx` | List extensions |
| `\timing` | Toggle query timing |
| `\x` | Expanded output (vertical) |
| `\copy` | Import/export CSV |
| `\! cmd` | Run shell command |
| `\q` | Quit |
| `\?` | Help for psql commands |
| `\h` | SQL command help |
| `\watch 5` | Re-run last query every 5s |

## Useful psql Settings

```sql
\pset pager off
\pset format aligned
\set ECHO queries
\set ON_ERROR_STOP on
```

## Service Control (RHEL PGDG)

```bash
sudo systemctl start postgresql-18
sudo systemctl stop postgresql-18
sudo systemctl reload postgresql-18
sudo /usr/pgsql-18/bin/pg_ctl -D /var/lib/pgsql/18/data status
```

## pg_ctl

```bash
pg_ctl -D $PGDATA start|stop|restart|reload|promote|status
pg_ctl -D $PGDATA stop -m fast|smart|immediate
```

## pg_dump / pg_restore

```bash
pg_dump -Fc -f backup.dump dbname
pg_dumpall -f all.sql
pg_restore -d dbname -j 4 backup.dump
pg_restore -l backup.dump   # list contents
```

## pg_basebackup

```bash
# Standby bootstrap (PG 18)
pg_basebackup -h primary -U replicator -D /var/lib/pgsql/18/data -Fp -Xs -P -R -S repl_slot

# Tar + verify
pg_basebackup -h primary -U replicator -D /backup/base -Ft -z -Xs -P -j 4
pg_verifybackup /backup/base
```

→ Full guide: [pg-basebackup.md](../04-backup-recovery/pg-basebackup.md)

## pgBackRest

```bash
pgbackrest --stanza=main check
pgbackrest --stanza=main --type=full backup
pgbackrest --stanza=main info
pgbackrest --stanza=main --delta restore
```

→ Full guide: [pg-backrest.md](../04-backup-recovery/pg-backrest.md)

## pg_isready

```bash
pg_isready -h localhost -p 5432
# exit 0 = accepting connections
```

## pgbench (Benchmark)

```bash
pgbench -i -s 50 dbname                    # init (~750 MB at scale 50)
pgbench -c 10 -j 2 -T 60 dbname            # 10 clients, 60 seconds
pgbench -c 32 -j 8 -T 300 -P 5 dbname      # progress every 5s
pgbench --protocol=extended -h pgbouncer -p 6432 -c 100 -T 60 dbname
```

→ Full guide: [pgbench.md](../06-performance/pgbench.md)

## Vacuum / Reindex CLI

```bash
vacuumdb -d dbname --analyze --verbose
reindexdb -d dbname --concurrently --table orders
```

## Configuration Inspection

```bash
postgres -C config_file -D $PGDATA
postgres -C data_directory -D $PGDATA
```

## Environment Variables

```bash
export PGHOST PGPORT PGUSER PGDATABASE PGSSLMODE
```

## Related

- [Knowledge Base Index](../INDEX.md)
- [Cheat Sheets Index](README.md)
- [psql Complete Reference](psql-reference.md)
- [Admin SQL](admin-sql.md)
- [Installation](../01-getting-started/installation.md)
