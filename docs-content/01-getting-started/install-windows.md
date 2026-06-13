# PostgreSQL on Windows — Install & Dev Setup

Windows install guide for **development and learning**. For production at scale, prefer **Linux** or **managed DBaaS** — see [Production Cluster Layout](../03-administration/production-cluster-layout.md).

> **Official downloads:** [Official Download Links](official-download-links.md)

---

## Recommended: EDB Interactive Installer

| Step | Action |
|------|--------|
| 1 | Open https://www.postgresql.org/download/windows/ |
| 2 | Download installer from https://www.enterprisedb.com/downloads/postgres-postgresql-downloads |
| 3 | Run installer (64-bit) — select **PostgreSQL 18** |
| 4 | Components: Server, pgAdmin 4, StackBuilder, Command Line Tools |
| 5 | Set **superuser (`postgres`) password** — store securely |
| 6 | Port: **5432** (default) |
| 7 | Locale: default or **English, United States** |

**Includes:** PostgreSQL server, **pgAdmin 4**, **StackBuilder**, psql, pg_dump, pg_restore.

---

## Default Paths (EDB Install)

| Item | Typical path |
|------|----------------|
| Binaries | `C:\Program Files\PostgreSQL\18\bin\` |
| Data (PGDATA) | `C:\Program Files\PostgreSQL\18\data\` |
| pgAdmin | Start Menu → pgAdmin 4 |
| Service | `postgresql-x64-18` (Windows Service) |

Add to PATH (optional):

```
C:\Program Files\PostgreSQL\18\bin
```

---

## Verify Install

**Command Prompt / PowerShell:**

```powershell
psql -U postgres -c "SELECT version();"
psql -U postgres -c "SHOW data_directory;"
pg_isready
```

**Services:** `Win+R` → `services.msc` → **postgresql-x64-18** → Running.

---

## pgAdmin 4

1. Launch **pgAdmin 4** from Start Menu
2. Register server: right-click **Servers** → Register → Server
3. **Connection** tab: Host `localhost`, Port `5432`, User `postgres`, password from install

Standalone pgAdmin updates: https://www.pgadmin.org/download/

---

## psql on Windows

```powershell
psql -U postgres
psql -U postgres -d postgres -c "\l"
```

Password file: `%APPDATA%\postgresql\pgpass.conf` (same format as Linux `.pgpass`).

---

## StackBuilder (optional)

Post-install — adds ODBC/JDBC drivers, spatial tools, etc.

---

## Docker on Windows (alternative)

```powershell
docker pull postgres:18
docker run --name pg18 -e POSTGRES_PASSWORD=secret -p 5432:5432 -d postgres:18
docker exec -it pg18 psql -U postgres -c "SELECT version();"
```

See [Docker Install](install-docker.md).

---

## WSL2 + Linux PGDG (advanced dev)

Run production-like Linux PostgreSQL inside WSL:

```bash
# In WSL Ubuntu
sudo apt install -y postgresql-common
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
sudo apt update && sudo apt install -y postgresql-18
```

See [install-linux.md](install-linux.md).

---

## Windows vs Linux Production

| Aspect | Windows (dev) | Linux (production) |
|--------|---------------|---------------------|
| HA (Patroni) | Rare | Standard |
| pgBackRest | Possible | Standard |
| Performance tuning | Limited | Full (huge pages, etc.) |
| KB examples | Adapt paths | Native paths |

---

## Common Issues

| Issue | Fix |
|-------|-----|
| Port 5432 in use | Change port in install or stop other service |
| psql not found | Add `PostgreSQL\18\bin` to PATH |
| Service won't start | Check Event Viewer; verify data dir permissions |
| pg_hba rejects connection | Edit `pg_hba.conf` in data directory; reload service |

---

## Next Steps

1. [psql Complete Reference](../cheat-sheets/psql-reference.md)
2. [postgresql.conf](../02-configuration/postgresql-conf.md)
3. [pg_hba.conf](../02-configuration/pg-hba-conf.md)
4. [Official Download Links](official-download-links.md)

---

## Related

- [Installation Overview](installation.md)
- [Official Download Links](official-download-links.md)
- [Linux Install](install-linux.md)
- [Docker Install](install-docker.md)
