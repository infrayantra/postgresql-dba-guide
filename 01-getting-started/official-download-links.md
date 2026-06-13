# Official Download Links — PostgreSQL, pgAdmin & Tools

**Genuine official sources only.** Prefer these URLs over third-party mirrors. This KB targets **PostgreSQL 18**; links below point to vendor pages that list current versions.

> **Install guides:** [Installation Overview](installation.md) · [Linux (PGDG)](install-linux.md) · [Docker](install-docker.md)

---

## Primary hub (start here)

| Resource | Official URL |
|----------|--------------|
| **PostgreSQL downloads (all platforms)** | https://www.postgresql.org/download/ |
| **Official file browser / FTP** | https://www.postgresql.org/ftp/ |
| **Release announcements** | https://www.postgresql.org/about/newsarchive/ |
| **Documentation (PG 18)** | https://www.postgresql.org/docs/18/ |
| **Extension catalogue** | https://www.postgresql.org/download/products/ |

---

## Windows

### EDB interactive installer (recommended for dev / learning)

Certified Windows installer — includes **PostgreSQL server**, **pgAdmin 4**, **StackBuilder**, and contrib modules.

| Link | Notes |
|------|-------|
| **Windows download page** | https://www.postgresql.org/download/windows/ |
| **EDB installer downloads** | https://www.enterprisedb.com/downloads/postgres-postgresql-downloads |

The download button on postgresql.org/download/windows redirects to EDB-hosted installers (this is **official and expected**).

**Includes by default:**
- PostgreSQL server
- pgAdmin 4
- StackBuilder (ODBC/JDBC drivers, add-ons)
- Graphical or silent install

**Supported Windows (PG 18):** Windows Server 2022, 2025 (64-bit) — see platform table on download page.

### Windows binaries only (no installer)

For embedding or advanced setups:

| Link | Notes |
|------|-------|
| **EDB zip binaries** | Listed on https://www.postgresql.org/download/windows/ under advanced / zip archive |

After zip install, run `initdb` and register as a Windows service manually — see [PostgreSQL wiki — Windows](https://wiki.postgresql.org/wiki/Running_%26_Installing_PostgreSQL_On_Native_Windows).

### Windows — what to avoid

- Random “PostgreSQL crack” or repack sites
- Unverified SourceForge copies
- Installers bundled with unrelated toolbars

Always verify SHA256 if the page provides checksums.

---

## Linux

PostgreSQL.org does **not** host generic Linux `.deb`/`.rpm` for all distros — it links to **PGDG** (PostgreSQL Global Development Group packaging) or your distro.

### Linux hub

| Link | Purpose |
|------|---------|
| **Linux downloads index** | https://www.postgresql.org/download/linux/ |

Per-distribution pages (official):

| Distribution | Official page |
|--------------|---------------|
| **Red Hat / Rocky / Alma / Fedora** | https://www.postgresql.org/download/linux/redhat/ |
| **Debian** | https://www.postgresql.org/download/linux/debian/ |
| **Ubuntu** | https://www.postgresql.org/download/linux/ubuntu/ |
| **SUSE** | https://www.postgresql.org/download/linux/suse/ |
| **Other / generic** | https://www.postgresql.org/download/linux/ |

### PGDG repository packages (direct repo RPMs)

**RHEL / Rocky / Alma (example EL-9 x86_64):**

```
https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

**EL-8:**

```
https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

**Fedora (replace `F-41` with your Fedora release):**

```
https://download.postgresql.org/pub/repos/yum/reporpms/F-41-x86_64/pgdg-fedora-repo-latest.noarch.rpm
```

Full repo tree: https://download.postgresql.org/pub/repos/yum/

**Debian / Ubuntu APT:**

```
https://www.postgresql.org/media/keys/ACCC4CF8.asc
```

APT source (example Debian bookworm PG 18):

```
deb https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main
```

Full repo tree: https://download.postgresql.org/pub/repos/apt/

### Amazon Linux

Use PGDG RHEL-compatible repo — see [install-linux.md](install-linux.md#amazon-linux-2--2023).

### Linux source code

| Link | Purpose |
|------|---------|
| **Source tarball browser** | https://ftp.postgresql.org/pub/source/ |
| **Latest stable source** | https://www.postgresql.org/ftp/source/ |
| **Git repository** | https://git.postgresql.org/git/postgresql.git |
| **Build docs** | https://www.postgresql.org/docs/18/installation.html |

Example tarball pattern:

```
https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.gz
```

(Replace version with current minor from download page.)

---

## macOS

| Link | Purpose |
|------|---------|
| **macOS download page** | https://www.postgresql.org/download/macosx/ |
| **Postgres.app** (popular dev bundle) | https://postgresapp.com/ |
| **Homebrew** | `brew install postgresql@18` — https://formulae.brew.sh/formula/postgresql@18 |

---

## pgAdmin 4

Graphical administration tool — **separate from server** on Linux; **bundled with Windows EDB installer**.

| Resource | Official URL |
|----------|--------------|
| **pgAdmin download page** | https://www.pgadmin.org/download/ |
| **pgAdmin 4 downloads (FTP)** | https://ftp.postgresql.org/pub/pgadmin/pgadmin4/ |
| **pgAdmin documentation** | https://www.pgadmin.org/docs/ |
| **Source / GitHub** | https://github.com/pgadmin-org/pgadmin4 |

### pgAdmin by platform

| OS | Install method |
|----|----------------|
| **Windows** | Included in EDB PostgreSQL installer, or standalone from pgadmin.org/download |
| **macOS** | DMG from pgadmin.org/download |
| **Linux** | pgAdmin APT/YUM repos — https://www.pgadmin.org/download/pgadmin-4-apt/ and `-rpm/` |
| **Python pip** | `pip install pgadmin4` (web mode) — documented on pgAdmin site |

### Connect pgAdmin to local server

- Host: `localhost`
- Port: `5432` (default)
- User: `postgres` (or your role)
- Password: set during Windows install or Linux `postgres` user setup

---

## Docker (official image)

| Resource | URL |
|----------|-----|
| **Docker Hub — official `postgres`** | https://hub.docker.com/_/postgres |
| **Pull PG 18** | `docker pull postgres:18` |
| **Bookworm variant** | `docker pull postgres:18-bookworm` |

Dockerfile source: https://github.com/docker-library/postgres

See [install-docker.md](install-docker.md).

---

## Client tools only (no server)

Install on app servers or laptops:

| Platform | Package / command |
|----------|-------------------|
| RHEL | `dnf install postgresql18` (client + psql) |
| Debian/Ubuntu | `apt install postgresql-client-18` |
| Windows | EDB installer → custom → clients only, or zip binaries |
| macOS | `brew install libpq` (clients) |

**psql**, **pg_dump**, **pg_restore**, **pg_basebackup** ship with client packages.

---

## StackBuilder & drivers (Windows)

Launched from Start Menu after EDB install:

- ODBC driver
- JDBC driver
- Npgsql (.NET)
- Additional extensions/tools

Download page reference: included in Windows installer; also via EDB / PostgreSQL wiki links from StackBuilder UI.

**Npgsql (.NET):** https://www.npgsql.org/  
**psqlODBC:** https://odbc.postgresql.org/

---

## JDBC driver

| Driver | URL |
|--------|-----|
| **PostgreSQL JDBC (official)** | https://jdbc.postgresql.org/download/ |
| **Maven** | `org.postgresql:postgresql` — https://mvnrepository.com/artifact/org.postgresql/postgresql |

---

## .NET / Python / Node drivers (reference)

| Language | Official / de-facto standard |
|----------|------------------------------|
| Python | https://www.psycopg.org/psycopg3/ |
| Node.js | https://node-postgres.com/ |
| Go | https://github.com/jackc/pgx |
| Java | JDBC link above |

---

## Beta & development builds (not production)

| Resource | URL |
|----------|-----|
| **Beta / RC** | https://www.postgresql.org/download/#beta |
| **Development snapshots** | Linked from download page — testing only |

---

## Verify downloads

1. Prefer **postgresql.org** or **enterprisedb.com** (Windows installer) or **apt.postgresql.org** / **download.postgresql.org**
2. Check **release notes** for version: https://www.postgresql.org/docs/release/
3. After install:

```sql
SELECT version();
SHOW server_version_num;
```

```bash
psql --version
pg_config --version
```

---

## Quick install commands (after adding PGDG repo)

**RHEL / Rocky — PostgreSQL 18:**

```bash
sudo dnf install -y postgresql18-server postgresql18-contrib
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
sudo systemctl enable --now postgresql-18
```

**Debian / Ubuntu — PostgreSQL 18:**

```bash
sudo apt install -y postgresql-18 postgresql-contrib-18
sudo systemctl enable --now postgresql
```

Full steps: [install-linux.md](install-linux.md).

---

## Related

- [Knowledge Base Index](../INDEX.md)
- [Installation Overview](installation.md)
- [Linux Install](install-linux.md)
- [Windows Install](install-windows.md)
- [Docker Install](install-docker.md)
- [VERSION.md](../VERSION.md)
- [VERSION.md](../VERSION.md)
- [PostgreSQL History & Releases](postgresql-history-and-releases.md)

---

*Links verified against postgresql.org structure — minor version numbers change quarterly; always pick current stable from the download page.*
