# PostgreSQL 18 HA — Production Setup Runbook

| | |
|---|---|
| **Topology** | 3 nodes · 1 primary + 2 synchronous-capable replicas |
| **OS** | RHEL 9 / Rocky 9 / AlmaLinux 9 |
| **Database** | PostgreSQL **18** · port **5432** |
| **App entry (writes)** | HAProxy **5000** on `pg-node1` |
| **App entry (reads)** | HAProxy **5001** on `pg-node1` (optional) |
| **Components** | Patroni 3.x + etcd 3.5.x + HAProxy 2.x |

> **Based on:** IntelliDB HA runbook pattern — adapted for standard PostgreSQL 18 with SCRAM auth, etcd v3, PG 18 tuning, and split read/write routing.

---

## Node Reference

Replace IPs/hostnames with your environment before executing.

| Role | Hostname | IP Address |
|------|----------|------------|
| pg-node1 — Primary bootstrap + HAProxy | pg-node1 | **10.0.1.11** |
| pg-node2 — Replica | pg-node2 | **10.0.1.12** |
| pg-node3 — Replica | pg-node3 | **10.0.1.13** |

## Directory Reference

| Purpose | Path |
|---------|------|
| PostgreSQL data | `/data/pgdata` |
| PostgreSQL logs | `/data/pglog` |
| WAL archive (PITR) | `/data/pgarchive` |
| etcd data | `/var/lib/etcd` |
| Patroni config | `/etc/patroni/patroni.yml` |
| etcd config | `/etc/etcd/etcd.conf` |
| PostgreSQL binaries (PGDG) | `/usr/pgsql-18/bin` |
| postgres OS home | `/var/lib/pgsql` |
| pgpass file | `/var/lib/pgsql/.pgpass` |

---

## Master Progress Checklist

| # | Phase | Step | pg-node1 | pg-node2 | pg-node3 |
|---|-------|------|:--------:|:--------:|:--------:|
| 1 | **Pre** | §2 — OS prep + PG 18 installed | ☐ | ☐ | ☐ |
| 2 | **II** | §4 — HAProxy + Python deps | ☐ | ☐ | ☐ |
| 3 | **II** | §5 — etcd binary installed | ☐ | ☐ | ☐ |
| 4 | **II** | §6 — Patroni installed | ☐ | ☐ | ☐ |
| 5 | **II** | §7 — Standalone PG disabled; dirs created | ☐ | ☐ | ☐ |
| 6 | **II** | §8 — Firewall ports open | ☐ | ☐ | ☐ |
| 7 | **III** | §9 — etcd cluster running (quorum verified) | ☐ | ☐ | ☐ |
| 8 | **III** | §10 — patroni.yml + systemd (not started) | ☐ | ☐ | ☐ |
| 9 | **III** | §11 — haproxy.cfg written (pg-node1) | ☐ | — | — |
| 10 | **III** | §12 — SELinux contexts | ☐ | ☐ | ☐ |
| 11 | **IV** | §13.3 — Patroni started on pg-node1 (bootstrap) | ☐ | — | — |
| 12 | **IV** | §13.4 — Replica data dirs empty | — | ☐ | ☐ |
| 13 | **IV** | §13.5 — replicator + pg_hba verified | ☐ | — | — |
| 14 | **IV** | §13.6 — Replicas started | — | ☐ | ☐ |
| 15 | **IV** | §13.8 — HAProxy started | ☐ | — | — |
| 16 | **V** | §14 — Full validation + failover test | ☐ | ☐ | ☐ |

---

## Architecture

```
                         Applications
                              |
              +---------------+---------------+
              |                               |
         psql / JDBC                     read-only apps
              |                               |
              v                               v
     +------------------+            +------------------+
     | HAProxy :5000    |            | HAProxy :5001    |   pg-node1 only
     | (writes/primary) |            | (read replicas)  |
     +------------------+            +------------------+
              |                               |
              +---------------+---------------+
                              |
         +--------------------+--------------------+
         |                    |                    |
   10.0.1.11:5432      10.0.1.12:5432      10.0.1.13:5432
     pg-node1              pg-node2              pg-node3
    (Primary)             (Replica)             (Replica)
         |                    |                    |
   Patroni :8008        Patroni :8008        Patroni :8008
         |                    |                    |
   etcd :2379            etcd :2379            etcd :2379
         +--------------------+--------------------+
                        etcd cluster (quorum = 2/3)
```

### Why 3 nodes?

| Nodes | etcd quorum | PG failover | Recommendation |
|-------|-------------|-------------|----------------|
| 1 | N/A | No HA | Dev only |
| 2 | Split-brain risk | Possible | **Avoid** for etcd + Patroni |
| **3** | Tolerates 1 loss | Automatic | **Production minimum** |
| 5 | Tolerates 2 loss | Automatic | Large / critical systems |

### Network ports

| Port | Protocol | Service | Open between |
|------|----------|---------|--------------|
| 5432 | TCP | PostgreSQL | All 3 nodes + admin hosts |
| 8008 | TCP | Patroni REST API | All 3 nodes + HAProxy host |
| 2379 | TCP | etcd client | All 3 nodes |
| 2380 | TCP | etcd peer | All 3 nodes |
| 5000 | TCP | HAProxy write frontend | App subnet → pg-node1 |
| 5001 | TCP | HAProxy read frontend | App subnet → pg-node1 |

---

# Part I — Prerequisites

## §1 — Requirements

- Three RHEL 9 / Rocky 9 / AlmaLinux 9 VMs (2 vCPU, 8 GB RAM minimum; scale for production)
- Static IPs and resolvable hostnames (`/etc/hosts` or DNS)
- NTP/chrony synchronized on all nodes
- Dedicated disk or LVM for `/data` (SSD/NVMe recommended)
- Passwords prepared (store in vault — **change all defaults below**)

| Secret | Variable in doc | Default (CHANGE ME) |
|--------|-----------------|---------------------|
| Superuser | `postgres` | `PgSuperSecure2026!` |
| Replication | `replicator` | `ReplSecure2026!` |
| App user | `app_user` | `AppSecure2026!` |

## §2 — Install PostgreSQL 18 (all nodes)

```bash
# PGDG repo
sudo dnf install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql

sudo dnf install -y \
  postgresql18-server \
  postgresql18-contrib \
  postgresql18-libs

# DO NOT run postgresql-18-setup initdb — Patroni will initialize the cluster
sudo systemctl disable postgresql-18 2>/dev/null || true
sudo systemctl stop postgresql-18 2>/dev/null || true
sudo ss -lntp | grep 5432    # must be empty
```

**Verify binaries:**

```bash
/usr/pgsql-18/bin/postgres --version
# PostgreSQL 18.x
```

---

# Part II — Installation (all nodes unless noted)

## §4 — Install HAProxy and dependencies

```bash
sudo dnf install -y epel-release
sudo dnf install -y haproxy firewalld python3-pip python3-psycopg2 python3-pyyaml python3-devel gcc
```

**Verify:**

```bash
haproxy -v
python3 -c "import yaml, psycopg2; print('OK')"
```

> HAProxy is only **required on pg-node1** for routing, but installing on all nodes simplifies troubleshooting.

---

## §5 — Install etcd 3.5.x

```bash
ETCD_VER=v3.5.16
curl -sL -o etcd-${ETCD_VER}-linux-amd64.tar.gz \
  https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz

tar xzf etcd-${ETCD_VER}-linux-amd64.tar.gz
sudo cp etcd-${ETCD_VER}-linux-amd64/etcd etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
sudo chmod 755 /usr/local/bin/etcd /usr/local/bin/etcdctl
etcd --version

sudo mkdir -p /var/lib/etcd
sudo chmod 700 /var/lib/etcd
```

---

## §6 — Install Patroni

```bash
sudo pip3 install 'patroni[etcd]==3.3.*' psycopg2-binary
```

**Verify:**

```bash
export PATH="/usr/local/bin:$PATH"
patroni --version
python3 -c "import patroni.etcd; print('Patroni etcd DCS OK')"
```

---

## §7 — Prepare PostgreSQL directories

> **Critical:** `data_dir` must be an **empty dedicated subdirectory** Patroni owns — not `/data` itself.

```bash
# Disable standalone PostgreSQL — Patroni manages the process
sudo systemctl stop postgresql-18 2>/dev/null || true
sudo systemctl disable postgresql-18 2>/dev/null || true

# OS user
sudo id postgres || sudo useradd -r -s /bin/bash -d /var/lib/pgsql -m postgres
sudo chown postgres:postgres /var/lib/pgsql
sudo chmod 700 /var/lib/pgsql

# Data, log, archive paths
sudo mkdir -p /data/pgdata /data/pglog /data/pgarchive
sudo chown -R postgres:postgres /data
sudo chmod 755 /data
sudo chmod 700 /data/pgdata /data/pglog /data/pgarchive

# pgpass for Patroni replication connections
sudo -u postgres bash -c 'cat > /var/lib/pgsql/.pgpass <<EOF
*:*:replication:replicator:ReplSecure2026!
*:*:*:postgres:PgSuperSecure2026!
EOF'
sudo chmod 600 /var/lib/pgsql/.pgpass

# Verify
ls -ld /data /data/pgdata /data/pglog /data/pgarchive
sudo ss -lntp | grep 5432    # empty
```

---

## §8 — Firewall

```bash
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --permanent --add-port=8008/tcp
sudo firewall-cmd --permanent --add-port=2379/tcp
sudo firewall-cmd --permanent --add-port=2380/tcp
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --permanent --add-port=5001/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

Restrict source IPs in production:

```bash
# Example: app subnet only for HAProxy
sudo firewall-cmd --permanent --remove-port=5000/tcp
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.2.0/24" port port="5000" protocol="tcp" accept'
sudo firewall-cmd --reload
```

---

# Part III — Configuration

## §9 — Configure etcd

### Create config directory (all nodes)

```bash
sudo mkdir -p /etc/etcd
```

### etcd.conf — pg-node1 (`10.0.1.11`)

`/etc/etcd/etcd.conf`:

```ini
ETCD_NAME=pg-node1
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://10.0.1.11:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.1.11:2379"

ETCD_LISTEN_PEER_URLS="http://10.0.1.11:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.1.11:2380"

ETCD_INITIAL_CLUSTER="pg-node1=http://10.0.1.11:2380,pg-node2=http://10.0.1.12:2380,pg-node3=http://10.0.1.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="pg18-ha-etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
```

### etcd.conf — pg-node2 (`10.0.1.12`)

```ini
ETCD_NAME=pg-node2
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://10.0.1.12:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.1.12:2379"

ETCD_LISTEN_PEER_URLS="http://10.0.1.12:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.1.12:2380"

ETCD_INITIAL_CLUSTER="pg-node1=http://10.0.1.11:2380,pg-node2=http://10.0.1.12:2380,pg-node3=http://10.0.1.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="pg18-ha-etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
```

### etcd.conf — pg-node3 (`10.0.1.13`)

```ini
ETCD_NAME=pg-node3
ETCD_DATA_DIR="/var/lib/etcd"

ETCD_LISTEN_CLIENT_URLS="http://10.0.1.13:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.1.13:2379"

ETCD_LISTEN_PEER_URLS="http://10.0.1.13:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.1.13:2380"

ETCD_INITIAL_CLUSTER="pg-node1=http://10.0.1.11:2380,pg-node2=http://10.0.1.12:2380,pg-node3=http://10.0.1.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="pg18-ha-etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
```

> **Do not** wrap IPs in `[` `]` brackets — Patroni and etcd expect plain IPv4.

### etcd systemd unit (all nodes)

`/etc/systemd/system/etcd.service`:

```ini
[Unit]
Description=etcd key-value store for Patroni DCS
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### Bootstrap etcd cluster

> Stop etcd on **all** nodes, clear data, start **all three within 60 seconds**.

```bash
# ALL 3 nodes
sudo systemctl stop etcd 2>/dev/null || true
sudo rm -rf /var/lib/etcd/*
sudo mkdir -p /var/lib/etcd && sudo chmod 700 /var/lib/etcd

sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
```

### Verify etcd

```bash
export ETCDCTL_API=3
export ENDPOINTS=http://10.0.1.11:2379,http://10.0.1.12:2379,http://10.0.1.13:2379

etcdctl --endpoints=$ENDPOINTS member list -w table
etcdctl --endpoints=$ENDPOINTS endpoint health
etcdctl --endpoints=$ENDPOINTS endpoint status -w table
```

All three members must show `started` and `healthy`.

---

## §10 — Configure Patroni

### Per-node differences in patroni.yml

| Key | pg-node1 | pg-node2 | pg-node3 |
|-----|----------|----------|----------|
| `name` | `pg-node1` | `pg-node2` | `pg-node3` |
| `restapi.listen` | `10.0.1.11:8008` | `10.0.1.12:8008` | `10.0.1.13:8008` |
| `restapi.connect_address` | `10.0.1.11:8008` | `10.0.1.12:8008` | `10.0.1.13:8008` |
| `postgresql.listen` | `10.0.1.11:5432` | `10.0.1.12:5432` | `10.0.1.13:5432` |
| `postgresql.connect_address` | `10.0.1.11:5432` | `10.0.1.12:5432` | `10.0.1.13:5432` |

All other keys are **identical** on every node.

---

### patroni.yml — pg-node1 (template — copy to all nodes with per-node edits)

`/etc/patroni/patroni.yml`:

```yaml
scope: pg18-cluster
namespace: /service/
name: pg-node1

restapi:
  listen: 10.0.1.11:8008
  connect_address: 10.0.1.11:8008

etcd3:
  hosts: 10.0.1.11:2379,10.0.1.12:2379,10.0.1.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: false          # set true for zero data loss (adds write latency)
    synchronous_mode_strict: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 2GB
        max_connections: 500
        shared_buffers: 2GB
        effective_cache_size: 6GB
        work_mem: 32MB
        maintenance_work_mem: 512MB
        logging_collector: "on"
        log_directory: /data/pglog
        log_filename: postgresql-%Y-%m-%d_%H%M%S.log
        log_rotation_age: 1d
        log_rotation_size: 100MB
        log_min_duration_statement: 500
        archive_mode: "on"
        archive_command: test ! -f /data/pgarchive/%f && cp %p /data/pgarchive/%f
        shared_preload_libraries: pg_stat_statements
        pg_stat_statements.track: all
        # PG 18 — async I/O (enable after baseline validation)
        io_method: worker
        io_combine_limit: 128kB
  initdb:
    - encoding: UTF8
    - locale: en_US.UTF-8
    # PG 18: data-checksums ON by default; list explicitly for clarity:
    - data-checksums
  pg_hba:
    - local all all peer
    - host all all 127.0.0.1/32 scram-sha-256
    - host replication replicator 10.0.1.11/32 scram-sha-256
    - host replication replicator 10.0.1.12/32 scram-sha-256
    - host replication replicator 10.0.1.13/32 scram-sha-256
    - host all all 10.0.1.0/24 scram-sha-256
    - host all all 10.0.2.0/24 scram-sha-256
  users:
    replicator:
      password: ReplSecure2026!
      options:
        - replication
    postgres:
      password: PgSuperSecure2026!
      options:
        - superuser
        - createdb
    app_user:
      password: AppSecure2026!
      options:
        - createdb

postgresql:
  listen: 10.0.1.11:5432
  connect_address: 10.0.1.11:5432
  data_dir: /data/pgdata
  bin_dir: /usr/pgsql-18/bin
  config_dir: /data/pgdata
  pgpass: /var/lib/pgsql/.pgpass
  authentication:
    replication:
      username: replicator
      password: ReplSecure2026!
    superuser:
      username: postgres
      password: PgSuperSecure2026!
  parameters:
    unix_socket_directories: /var/run/postgresql
  create_replica_methods:
    - basebackup
  basebackup:
    max-rate: 100M
    checkpoint: fast
```

**pg-node2:** copy file; change `name`, `restapi.*`, `postgresql.listen`, `postgresql.connect_address` to `10.0.1.12`.

**pg-node3:** same with `10.0.1.13`.

### Validate and permissions (all nodes)

```bash
sudo mkdir -p /etc/patroni
sudo chown postgres:postgres /etc/patroni/patroni.yml
sudo chmod 600 /etc/patroni/patroni.yml

export PATH="/usr/local/bin:$PATH"
sudo -u postgres patroni /etc/patroni/patroni.yml validate-config
```

### Patroni systemd unit (all nodes)

`/etc/systemd/system/patroni.service`:

```ini
[Unit]
Description=Patroni PostgreSQL 18 HA Manager
After=network-online.target etcd.service
Wants=network-online.target
Requires=etcd.service

[Service]
Type=simple
User=postgres
Group=postgres
Environment=PATH=/usr/pgsql-18/bin:/usr/local/bin:/usr/bin
ExecStart=/usr/local/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
TimeoutSec=60

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable patroni
# Do NOT start yet — §13.3
```

---

## §11 — Configure HAProxy (pg-node1 only)

`/etc/haproxy/haproxy.cfg`:

```text
global
    log         127.0.0.1 local0
    chroot      /var/lib/haproxy
    stats       socket /run/haproxy/stats mode 660 level admin expose-fd listeners
    stats       timeout 30s
    user        haproxy
    group       haproxy
    daemon

defaults
    log                     global
    mode                    tcp
    option                  tcplog
    option                  dontlognull
    timeout connect         5s
    timeout client          30m
    timeout server          30m
    timeout check           5s

# ── Writes → current Patroni leader only ──
frontend pg_write_frontend
    bind 10.0.1.11:5000
    default_backend pg_write_backend

backend pg_write_backend
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 10.0.1.11:5432 check port 8008
    server pg-node2 10.0.1.12:5432 check port 8008
    server pg-node3 10.0.1.13:5432 check port 8008

# ── Reads → Patroni replicas (standbys) ──
frontend pg_read_frontend
    bind 10.0.1.11:5001
    default_backend pg_read_backend

backend pg_read_backend
    balance roundrobin
    option httpchk GET /replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2
    server pg-node1 10.0.1.11:5432 check port 8008
    server pg-node2 10.0.1.12:5432 check port 8008
    server pg-node3 10.0.1.13:5432 check port 8008
```

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable haproxy
# Do NOT start yet — §13.8
```

> Patroni REST endpoints: `/primary` (leader), `/replica` (standby), `/health` — available on port **8008**.

---

## §12 — SELinux (all nodes)

```bash
sudo semanage fcontext -a -t postgresql_db_t "/data/pgdata(/.*)?" 2>/dev/null || true
sudo semanage fcontext -a -t postgresql_log_t "/data/pglog(/.*)?" 2>/dev/null || true
sudo restorecon -Rv /data /var/lib/etcd /etc/patroni 2>/dev/null || true

# If archive writes blocked:
sudo chcon -R -t postgresql_db_t /data/pgarchive 2>/dev/null || true

sudo ausearch -m avc -ts recent
```

---

# Part IV — Bootstrap and Go-live

> Execute **in order**. Skipping steps causes clone failures or split-brain.

## §13.1 — Confirm etcd active (all nodes)

```bash
systemctl is-active etcd    # → active on all 3
```

## §13.2 — Clear stale Patroni state (rebuilds only)

Skip on fresh install. For rebuild:

```bash
sudo systemctl stop patroni    # all nodes
export ETCDCTL_API=3
etcdctl --endpoints=$ENDPOINTS del /service/pg18-cluster --prefix
```

## §13.3 — Start leader on pg-node1

**Pre-flight on pg-node1:**

```bash
systemctl is-active etcd
sudo ss -lntp | grep 5432          # empty
ls -la /data/pgdata                # empty directory
sudo -u postgres test -w /data/pgdata && echo "writable OK"
sudo -u postgres patroni /etc/patroni/patroni.yml validate-config
```

**Start Patroni on pg-node1 only:**

```bash
sudo systemctl start patroni
sleep 20
export PATH="/usr/local/bin:$PATH"
patronictl -c /etc/patroni/patroni.yml list
```

Expected: `pg-node1` · Role **Leader** · State **running**.

```bash
# If not up within 60s:
journalctl -u patroni -f --no-pager
```

**Verify bootstrap:**

```bash
psql -h 10.0.1.11 -p 5432 -U postgres -d postgres -c "SELECT version();"
psql -h 10.0.1.11 -p 5432 -U postgres -d postgres -c "SHOW data_checksums;"
sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
```

## §13.4 — Prepare replica data directories (pg-node2, pg-node3)

```bash
sudo systemctl stop patroni 2>/dev/null || true

# Fresh install: dir is empty. Rebuild: move stale data away.
if [ -n "$(sudo ls -A /data/pgdata 2>/dev/null)" ]; then
  sudo mv /data/pgdata /data/pgdata.bak-$(date +%Y%m%d%H%M%S)
fi
sudo mkdir -p /data/pgdata
sudo chown postgres:postgres /data/pgdata
sudo chmod 700 /data/pgdata
ls -la /data/pgdata    # must be empty
```

## §13.5 — Verify replication user (pg-node1)

```bash
psql -h 10.0.1.11 -p 5432 -U postgres -d postgres -c "\du replicator"
```

Expected: `replicator` with `Replication` attribute.

```bash
grep replicator /data/pgdata/pg_hba.conf
```

Reload if you edited pg_hba manually:

```bash
patronictl -c /etc/patroni/patroni.yml reload pg18-cluster pg-node1
```

## §13.6 — Start replicas

Start **pg-node2**, wait for `pg_basebackup` to finish, then **pg-node3**:

```bash
# pg-node2 then pg-node3
sudo systemctl start patroni
journalctl -u patroni -n 100 --no-pager
```

On pg-node1:

```bash
patronictl -c /etc/patroni/patroni.yml list
```

Expected:

| Member | Role | State | Lag in MB |
|--------|------|-------|-----------|
| pg-node1 | Leader | running | — |
| pg-node2 | Replica | streaming | 0 |
| pg-node3 | Replica | streaming | 0 |

## §13.7 — Confirm topology

```bash
patronictl -c /etc/patroni/patroni.yml topology
curl -s http://10.0.1.11:8008/primary
curl -s http://10.0.1.12:8008/replica
curl -s http://10.0.1.13:8008/replica
```

## §13.8 — Start HAProxy (pg-node1)

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl start haproxy
systemctl is-active haproxy
```

---

# Part V — Validation

## §14.1 — Service health

```bash
# All nodes
systemctl is-active etcd patroni

# pg-node1
systemctl is-active haproxy
```

## §14.2 — Patroni cluster

```bash
patronictl -c /etc/patroni/patroni.yml list
```

1 Leader · 2 Replicas · lag ≈ 0.

## §14.3 — HAProxy write routing

```bash
psql -h 10.0.1.11 -p 5000 -U postgres -d postgres \
  -c "SELECT inet_server_addr() AS server_ip, pg_is_in_recovery() AS is_replica;"
```

`is_replica` must be **`f`**.

## §14.4 — HAProxy read routing

```bash
psql -h 10.0.1.11 -p 5001 -U postgres -d postgres \
  -c "SELECT inet_server_addr(), pg_is_in_recovery();"
```

`is_replica` must be **`t`** (when connected to a standby).

## §14.5 — Replication data test

Via write endpoint:

```sql
CREATE TABLE ha_validation (
  id int PRIMARY KEY,
  node text,
  created_at timestamptz DEFAULT now()
);
INSERT INTO ha_validation VALUES (1, 'leader');
```

On each replica directly:

```bash
psql -h 10.0.1.12 -p 5432 -U postgres -d postgres -c "SELECT * FROM ha_validation;"
psql -h 10.0.1.13 -p 5432 -U postgres -d postgres -c "SELECT * FROM ha_validation;"
```

## §14.6 — WAL archive

```bash
ls -lh /data/pgarchive/    # WAL segments appear after activity
```

## §14.7 — Failover test (maintenance window)

```bash
# Controlled switchover (graceful)
patronictl -c /etc/patroni/patroni.yml switchover --leader pg-node1 --candidate pg-node2 --force

patronictl -c /etc/patroni/patroni.yml list

# HAProxy must route writes to new leader
psql -h 10.0.1.11 -p 5000 -U postgres -d postgres -c "SELECT pg_is_in_recovery();"
```

Switch back when done:

```bash
patronictl -c /etc/patroni/patroni.yml switchover --leader pg-node2 --candidate pg-node1 --force
```

## §14.8 — PG 18 feature smoke test

```sql
SELECT uuidv7();
SELECT * FROM pg_aios;
SELECT name, setting FROM pg_settings WHERE name LIKE 'io_%';
```

---

# Application Connectivity

| Use | Host | Port | User | Notes |
|-----|------|------|------|-------|
| **Writes / DDL** | `10.0.1.11` | **5000** | `app_user` | Via HAProxy → leader |
| **Read-only** | `10.0.1.11` | **5001** | `app_user` | Via HAProxy → replicas |
| DBA direct | Leader IP | **5432** | `postgres` | Bypass HAProxy |
| Replica direct | Replica IP | **5432** | `postgres` | Read queries / monitoring |

```bash
psql "postgresql://app_user:AppSecure2026!@10.0.1.11:5000/postgres"
```

```text
# JDBC — writes
jdbc:postgresql://10.0.1.11:5000/myapp?targetServerType=primary

# JDBC — reads
jdbc:postgresql://10.0.1.11:5001/myapp?targetServerType=preferSecondary
```

---

# Day-2 Operations

| Task | Command |
|------|---------|
| Cluster status | `patronictl -c /etc/patroni/patroni.yml list` |
| Topology | `patronictl -c /etc/patroni/patroni.yml topology` |
| Planned switchover | `patronictl switchover --leader pg-node1 --candidate pg-node2` |
| Emergency failover | `patronictl failover pg18-cluster --candidate pg-node2 --force` |
| Reinit broken replica | `patronictl reinit pg18-cluster pg-node3 --force` |
| Reload PG config | `patronictl reload pg18-cluster pg-node1` |
| Pause auto failover | `patronictl pause pg18-cluster` |
| Resume | `patronictl resume pg18-cluster` |
| Patroni logs | `journalctl -u patroni -n 200 --no-pager` |
| etcd health | `etcdctl --endpoints=$ENDPOINTS endpoint health` |
| Replication lag | `patronictl list` · SQL: `pg_stat_replication` |

---

# Production Hardening (post go-live)

See [SSL/TLS Implementation](../08-security/ssl-tls-implementation.md) and [TDE at Rest](../08-security/tde-implementation.md) for encryption.

## Enable synchronous replication (optional — zero data loss)

Edit Patroni DCS or `patroni.yml` bootstrap section:

```yaml
bootstrap:
  dcs:
    synchronous_mode: true
    synchronous_node_count: 1    # at least 1 sync standby
```

Then `patronictl reload` / rolling restart per Patroni docs. **Adds write latency.**

## Replace shell archive with pgBackRest

See [pgBackRest](../04-backup-recovery/pg-backrest.md) — configure `archive_command` via Patroni `postgresql.parameters`.

## TLS

- Terminate TLS at HAProxy, or
- Enable `hostssl` in `pg_hba.conf` + PostgreSQL SSL certs on each node

## etcd TLS (recommended for regulated environments)

Upgrade etcd to HTTPS peer/client URLs — update `etcd.conf` and Patroni `etcd3` section with certs.

## Monitoring alerts

| Alert | Threshold |
|-------|-----------|
| No Patroni leader | > 30s |
| Replication lag | > 100 MB or > 30s |
| etcd no quorum | any member down > 5 min |
| HAProxy backend down | any backend `DOWN` |
| `/data` disk usage | > 85% |
| `pg_archive` failures | any failed `archive_command` |

---

# Troubleshooting

## Patroni

| Symptom | Fix |
|---------|-----|
| `data_dir is not empty` | Empty `/data/pgdata` on replicas (§13.4) |
| Port 5432 in use | `systemctl disable --now postgresql-18` |
| Wrong `bin_dir` | Must be `/usr/pgsql-18/bin` |
| `Permission denied` on `/data/*` | `chown -R postgres:postgres /data` |
| Config validate fails | `patroni ... validate-config`; check YAML indentation |
| IPv6 URL error | Remove `[` `]` around IPs |

## etcd

| Symptom | Fix |
|---------|-----|
| Member won't join | All nodes same `ETCD_INITIAL_CLUSTER`; start within 60s |
| `cluster ID mismatch` | Clear `/var/lib/etcd/*` on all nodes; rebootstrap |
| No quorum | Need 2/3 nodes up |

## HAProxy

| Symptom | Fix |
|---------|-----|
| `no server available` | `curl http://10.0.1.11:8008/primary` → must be HTTP 200 |
| Writes hit replica | Check `GET /primary` backend check — not `/master` on older Patroni |
| Read pool hits primary | `/replica` returns 503 on leader — expected; use roundrobin |

## Replication

| Symptom | Fix |
|---------|-----|
| `system identifier mismatch` | Empty replica `data_dir`, `patronictl reinit` |
| `password authentication failed for replicator` | Match `.pgpass`, patroni.yml, and role password |
| `no pg_hba.conf entry` | Add replica IP with `scram-sha-256` |
| Clone slow | Increase `basebackup max-rate`; check network/firewall |
| Slot lag / WAL bloat | `patronictl list`; ensure slots active on replicas |

**Bracket cleanup:**

```bash
sudo sed -i 's/\[\([0-9][0-9.]*\)\]/\1/g' /etc/etcd/etcd.conf /etc/patroni/patroni.yml
sudo systemctl restart etcd patroni
```

---

# File Reference

| Path | Nodes | Purpose |
|------|-------|---------|
| `/data/pgdata` | All | PostgreSQL data directory |
| `/data/pglog` | All | Log directory |
| `/data/pgarchive` | All | WAL archive for PITR |
| `/etc/patroni/patroni.yml` | All | Patroni config |
| `/etc/systemd/system/patroni.service` | All | Patroni unit |
| `/etc/etcd/etcd.conf` | All | etcd config |
| `/etc/systemd/system/etcd.service` | All | etcd unit |
| `/etc/haproxy/haproxy.cfg` | pg-node1 | Connection routing |
| `/usr/pgsql-18/bin` | All | PostgreSQL 18 binaries |
| `/var/lib/pgsql/.pgpass` | All | Patroni local auth |

---

# Glossary

| Term | Meaning |
|------|---------|
| **Leader / Primary** | Read-write PostgreSQL instance |
| **Replica / Standby** | Hot standby — receives WAL via streaming replication |
| **DCS** | Distributed configuration store (etcd) for leader election |
| **Patroni** | HA manager — starts, stops, fails over PostgreSQL |
| **Scope** | Cluster name (`pg18-cluster`) |
| **pg_rewind** | Resyncs old primary after failover so it can rejoin as replica |
| **Replication slot** | Prevents WAL removal until replica consumes it |

---

## Related

- [Patroni & pgpool](patroni-pgpool.md)
- [Streaming Replication](streaming-replication.md)
- [Failover](failover.md)
- [PostgreSQL 18 Reference](../01-getting-started/postgresql-18.md)
- [Linux Install](../01-getting-started/install-linux.md)
- [pgBackRest](../04-backup-recovery/pg-backrest.md)

---

*Template version: 2026-06 · PostgreSQL 18 · Patroni 3.3 · etcd 3.5*
