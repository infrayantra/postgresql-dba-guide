# PostgreSQL on Linux — Deep Install Guide

Complete installation reference for bare-metal and VM Linux servers. **Always prefer PGDG packages** over OS-bundled PostgreSQL — OS repos ship older versions and conflict with multiple major versions.

> **Official repo URLs:** [Official Download Links](official-download-links.md)

---

## Package Source Comparison

| Source | Pros | Cons |
|--------|------|------|
| **PGDG** (postgresql.org) | Latest minors, multiple majors side-by-side, contrib extensions | Extra repo setup |
| OS default (AppStream, Ubuntu universe) | Zero config | Often PG 13–15, single version, delayed patches |
| Source compile | Full control, custom `--with` flags | No package manager updates, you patch CVEs |
| Snap (Ubuntu) | Easy | Not for production — opaque paths, upgrade surprises |

**Production default:** PGDG + `systemd` + dedicated data disk + `data_checksums`.

---

## RHEL / Rocky / Alma / CentOS Stream

### 1. Add PGDG Repository

```bash
# Detect major version
EL_VERSION=$(rpm -E %{rhel})   # 8 or 9 on RHEL-family

# Install repo RPM (pick correct EL version)
sudo dnf install -y \
  "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${EL_VERSION}-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

# CRITICAL: disable built-in PostgreSQL module (conflicts with PGDG)
sudo dnf -qy module disable postgresql
sudo dnf -qy module reset postgresql
```

**CentOS Stream / Rocky / Alma:** same steps — replace `rhel` with your `$EL_VERSION`.

**Fedora:**

```bash
sudo dnf install -y \
  "https://download.postgresql.org/pub/repos/yum/reporpms/F-$(rpm -E %fedora)-x86_64/pgdg-fedora-repo-latest.noarch.rpm"
sudo dnf -qy module disable postgresql
```

### 2. Install PostgreSQL 18

```bash
sudo dnf install -y \
  postgresql18-server \
  postgresql18-contrib \
  postgresql18-libs

# Optional: client-only on app servers
sudo dnf install -y postgresql18
```

Available packages pattern: `postgresql{MAJOR}-{server,contrib,libs,devel,plpython3,plperl}` — e.g. `postgresql18-server` or `postgresql17-server` for other majors.

### 3. Initialize & Start

```bash
# RHEL packages ship helper script
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb

# Production initdb with checksums (if setup script doesn't use them, re-init):
sudo systemctl stop postgresql-18
sudo mv /var/lib/pgsql/18/data /var/lib/pgsql/18/data.bak
sudo -u postgres /usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data \
  --encoding=UTF8 --locale=en_US.UTF-8 \
  --auth-local=peer --auth-host=scram-sha-256
# PG 18: data checksums enabled by default — omit --data-checksums
# Legacy pg_upgrade from non-checksum cluster: add --no-data-checksums

sudo systemctl enable --now postgresql-18
sudo systemctl status postgresql-18
```

### 4. File Locations (RHEL-family)

| Item | Path |
|------|------|
| Binaries | `/usr/pgsql-18/bin/` |
| `$PGDATA` (default) | `/var/lib/pgsql/18/data/` |
| Config | `$PGDATA/postgresql.conf`, `pg_hba.conf` |
| Logs | `$PGDATA/log/` (if logging_collector=on) |
| systemd unit | `postgresql-18.service` |
| OS user | `postgres` |

Add to PATH for admins:

```bash
echo 'export PATH=/usr/pgsql-18/bin:$PATH' | sudo tee /etc/profile.d/postgresql18.sh
```

### 5. Post-Install Hardening

```bash
sudo -u postgres psql <<'SQL'
ALTER USER postgres PASSWORD 'CHANGE_ME';
SQL

# Allow remote connections (then restrict in pg_hba.conf)
sudo -u postgres sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" \
  /var/lib/pgsql/18/data/postgresql.conf

# Firewalld
sudo firewall-cmd --permanent --add-service=postgresql
sudo firewall-cmd --reload

sudo systemctl reload postgresql-18
```

### 6. SELinux

PostgreSQL data on custom paths requires SELinux context:

```bash
# Default path — usually fine
sudo semanage fcontext -a -t postgresql_db_t "/new/pgdata(/.*)?"
sudo restorecon -Rv /new/pgdata
```

If using NFS for `$PGDATA`, may need `setsebool -P postgresql_can_rsync on` or use local SSD.

### 7. Multiple Major Versions

```bash
sudo dnf install postgresql17-server postgresql18-server
sudo /usr/pgsql-17/bin/postgresql-17-setup initdb
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb

# Different ports
echo "port = 5433" | sudo -u postgres tee -a /var/lib/pgsql/17/data/postgresql.conf
sudo systemctl enable --now postgresql-17 postgresql-18
```

---

## Debian / Ubuntu

### 1. Add PGDG APT Repository

```bash
# Install prerequisites
sudo apt install -y postgresql-common wget gnupg2 lsb-release

# PGDG apt config helper (Debian/Ubuntu 22.04+)
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Import signing key (modern method)
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
  sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

# If using signed-by (recommended), update list file:
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
  sudo tee /etc/apt/sources.list.d/pgdg.list

sudo apt update
```

**Ubuntu versions:** `jammy` (22.04), `noble` (24.04) — PGDG supports LTS + current.

**Debian:** `bookworm` (12), `trixie` (13).

### 2. Install

```bash
sudo apt install -y \
  postgresql-18 \
  postgresql-contrib-18 \
  postgresql-client-18

# Optional extensions from PGDG
sudo apt install -y postgresql-18-pg-stat-statements
```

`apt install postgresql-18` automatically runs `initdb` via Debian maintainer scripts.

### 3. Debian/Ubuntu Cluster Layout

Debian uses **pg_createcluster** abstraction:

```bash
# List clusters
pg_lsclusters

# Output example:
# Ver Cluster Port Status Owner    Data directory              Log file
# 18  main    5432 online postgres /var/lib/postgresql/18/main /var/log/postgresql/postgresql-18-main.log
```

```bash
# Create additional cluster on port 5433
sudo pg_createcluster 18 analytics --port=5433 --start

# Start/stop/restart
sudo pg_ctlcluster 18 main start
sudo pg_ctlcluster 18 main stop
sudo pg_ctlcluster 18 main restart
sudo pg_ctlcluster 18 main reload

# Remove cluster (destructive)
sudo pg_dropcluster 18 analytics
```

| Item | Path |
|------|------|
| `$PGDATA` | `/var/lib/postgresql/18/main/` |
| Config | `/etc/postgresql/18/main/postgresql.conf` |
| `pg_hba.conf` | `/etc/postgresql/18/main/pg_hba.conf` |
| Logs | `/var/log/postgresql/postgresql-18-main.log` |
| systemd | `postgresql@18-main.service` |

**Important:** On Debian/Ubuntu, edit config in `/etc/postgresql/`, not only `$PGDATA`.

### 4. Production initdb with Checksums (Debian)

Default Debian init may omit checksums on older versions. Recreate:

```bash
sudo systemctl stop postgresql@18-main
sudo pg_dropcluster 18 main
sudo pg_createcluster 18 main -- --auth-host=scram-sha-256
sudo systemctl start postgresql@18-main
```

### 5. UFW Firewall

```bash
sudo ufw allow from 10.0.1.0/24 to any port 5432 proto tcp
sudo ufw reload
```

---

## Amazon Linux 2023 / Amazon Linux 2

### Amazon Linux 2023

```bash
sudo dnf install -y \
  "https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql18-server postgresql18-contrib
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
sudo systemctl enable --now postgresql-18
```

### Amazon Linux 2

Use EL-7 repo (PG 15 max on some setups) or EL-8 repo:

```bash
sudo amazon-linux-extras enable postgresql14   # AL2 bundled — older
# Prefer PGDG EL-7:
sudo yum install -y \
  "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
sudo yum -qy module disable postgresql
sudo yum install -y postgresql18-server postgresql18-contrib
```

**AWS EC2 tip:** attach gp3/io2 EBS volume for `$PGDATA`, enable encryption, use `data_checksums`.

---

## SUSE Linux Enterprise / openSUSE

### openSUSE Leap / Tumbleweed

```bash
sudo zypper addrepo \
  "https://download.opensuse.org/repositories/server:database:postgresql/pgdg/openSUSE_Leap_$VERSION/" \
  pgdg
sudo zypper --gpg-auto-import-keys refresh pgdg
sudo zypper install postgresql18-server postgresql18-contrib

# Or use PGDG generic RPM on SLE — see postgresql.org/download/linux/rpm
sudo /usr/pgsql-18/bin/initdb -D /var/lib/pgsql/18/data --data-checksums
sudo systemctl enable --now postgresql-18
```

### SLES 15

```bash
sudo zypper addrepo \
  "https://download.opensuse.org/repositories/server:database:postgresql/pgdg/SLE_15_SP5/" pgdg
sudo zypper ref pgdg
sudo zypper install postgresql18-server
```

---

## Alpine Linux (Containers / Minimal VMs)

Alpine ships PostgreSQL in main repo — good for dev, cautious for prod:

```bash
apk add postgresql18 postgresql18-contrib
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
su - postgres -c "initdb -D /var/lib/postgresql/data --data-checksums"
rc-update add postgresql default
rc-service postgresql start
```

Musl libc vs glibc — test extensions (especially PostGIS, Oracle FDW) before production.

---

## Compile from Source (Advanced)

Use when you need beta releases, custom patches, or non-standard `--with` options.

```bash
# Dependencies (RHEL example)
sudo dnf install -y gcc make readline-devel zlib-devel openssl-devel \
  libxml2-devel pam-devel systemd-devel

wget https://ftp.postgresql.org/pub/source/v18.0/postgresql-18.0.tar.gz
tar xzf postgresql-18.0.tar.gz && cd postgresql-18.0

./configure \
  --prefix=/usr/local/pgsql/18 \
  --with-openssl \
  --with-systemd \
  --with-icu \
  --with-llvm

make -j$(nproc)
sudo make install

# Add postgres user, initdb
sudo useradd -m postgres
sudo -u postgres /usr/local/pgsql/18/bin/initdb -D /usr/local/pgsql/18/data
# PG 18: checksums on by default
```

Create your own systemd unit pointing to custom prefix.

---

## Dedicated Data Disk Setup

Production pattern — OS on one volume, PostgreSQL on another:

```bash
# Format and mount (example: /dev/nvme1n1)
sudo mkfs.xfs /dev/nvme1n1
sudo mkdir -p /pgdata/18
echo '/dev/nvme1n1 /pgdata/18 xfs defaults,noatime 0 0' | sudo tee -a /etc/fstab
sudo mount -a

sudo mkdir -p /pgdata/18/data
sudo chown postgres:postgres /pgdata/18/data
sudo chmod 700 /pgdata/18/data

# RHEL: initdb to custom path (PG 18: checksums on by default)
sudo -u postgres /usr/pgsql-18/bin/initdb -D /pgdata/18/data

# Update systemd override
sudo systemctl edit postgresql-18
```

```ini
[Service]
Environment=PGDATA=/pgdata/18/data
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart postgresql-18
```

---

## OS Tuning (All Linux)

```bash
# /etc/sysctl.d/99-postgresql.conf
vm.swappiness = 1
vm.overcommit_memory = 2
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
kernel.shmmax = $(awk '/MemTotal/ {print $2*1024}' /proc/meminfo)
kernel.shmall = $(awk '/MemTotal/ {print $2*1024/4096}' /proc/meminfo)
net.core.somaxconn = 4096
net.ipv4.tcp_keepalive_time = 300

sudo sysctl -p /etc/sysctl.d/99-postgresql.conf
```

```bash
# Limits for postgres user — /etc/security/limits.d/postgresql.conf
postgres soft nofile 65536
postgres hard nofile 65536
postgres soft nproc 65536
postgres hard nproc 65536
```

Disable Transparent Huge Pages on RHEL:

```bash
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
# Make persistent via grub or tuned profile
```

---

## Verify & Smoke Test

```bash
sudo -u postgres psql -c "SELECT version();"
sudo -u postgres psql -c "SHOW data_checksums;"
ss -tlnp | grep 5432
```

```sql
CREATE TABLE install_test (id int PRIMARY KEY, created_at timestamptz DEFAULT now());
INSERT INTO install_test VALUES (1);
SELECT * FROM install_test;
DROP TABLE install_test;
```

---

## Troubleshooting Install Issues

| Problem | Fix |
|---------|-----|
| `Module postgresql is enabled` | `dnf module disable postgresql` |
| Port 5432 in use | Change `port` or stop conflicting cluster |
| `initdb: locale not found` | `localedef -i en_US -f UTF-8 en_US.UTF-8` |
| Permission denied on $PGDATA | `chown postgres:postgres; chmod 700` |
| Debian: config change ignored | Edit `/etc/postgresql/18/main/`, not only `$PGDATA` |
| APT key expired | Re-import ACCC4CF8 key from postgresql.org |

---

## Related

- [Installation Overview](installation.md)
- [Docker Install](install-docker.md)
- [Kubernetes Install](install-kubernetes.md)
- [DBaaS / Managed Postgres](install-dbaas.md)
- [postgresql.conf](../02-configuration/postgresql-conf.md)
