# Cheat Sheets — Quick Reference Index

Fast lookup for daily DBA work. All examples target **PostgreSQL 18**.

→ Full knowledge base: [README.md](../README.md) · [INDEX.md](../INDEX.md)

---

## Documents

| Sheet | Best for |
|-------|----------|
| [psql-reference.md](psql-reference.md) | **Complete psql** — meta-commands, `\pset`, `\gexec`, `\watch`, scripting, variables |
| [psql-commands.md](psql-commands.md) | **CLI one-liners** — pg_ctl, pg_dump, pg_basebackup, pgBackRest, pgbench |
| [admin-sql.md](admin-sql.md) | **DBA SQL** — sizes, connections, replication, archive, locks, vacuum |
| [parameters-quick-ref.md](parameters-quick-ref.md) | **GUC table** — memory, WAL, replication, PG 18 AIO |

---

## When to Use Which

| Task | Open |
|------|------|
| Interactive psql session | [psql-reference.md](psql-reference.md) |
| Shell backup / restore | [psql-commands.md](psql-commands.md) |
| On-call diagnostics in SQL | [admin-sql.md](admin-sql.md) |
| Tune postgresql.conf | [parameters-quick-ref.md](parameters-quick-ref.md) → [postgresql.conf](../02-configuration/postgresql-conf.md) |

---

## Related Deep Dives

- [DBA Health Checks](../07-monitoring/dba-health-checks.md)
- [Investigation Runbook](../11-troubleshooting/investigation-runbook.md)
- [Tuning Parameters](../06-performance/tuning-parameters.md)
