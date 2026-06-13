# Patroni, repmgr & pgpool-II

> **Version:** Examples target **PostgreSQL 18** (`/usr/pgsql-18/bin`, `/var/lib/pgsql/18/data`). Full runbook: [PG 18 HA Setup](postgresql-18-ha-setup-runbook.md).

## Patroni (Recommended for Automated HA)

Python daemon managing PostgreSQL lifecycle with distributed consensus (etcd, Consul, ZooKeeper, Kubernetes).

### Architecture

```
                    ┌─────────┐
                    │  etcd   │  ← DCS (Distributed Config Store)
                    └────┬────┘
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
      ┌─────────┐   ┌─────────┐   ┌─────────┐
      │ Patroni │   │ Patroni │   │ Patroni │
      │ + PG    │   │ + PG    │   │ + PG    │
      │ LEADER  │   │ Replica │   │ Replica │
      └─────────┘   └─────────┘   └─────────┘
           ▲
      HAProxy / VIP (port 5000 leader, 5001 replicas)
```

### Minimal patroni.yml

```yaml
scope: postgres-cluster
namespace: /service/
name: node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.1.1:8008

etcd3:
  hosts: 10.0.0.1:2379,10.0.0.2:2379,10.0.0.3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        io_method: worker          # PG 18
  initdb:
    - encoding: UTF8
    - data-checksums              # default ON in PG 18 initdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 10.0.1.1:5432
  data_dir: /var/lib/pgsql/18/data
  bin_dir: /usr/pgsql-18/bin
  authentication:
    replication:
      username: replicator
      password: repl_pass
    superuser:
      username: postgres
      password: postgres_pass
```

### Operations

```bash
patronictl -c /etc/patroni/patroni.yml list
patronictl -c /etc/patroni/patroni.yml switchover --leader pg-node1 --candidate pg-node2
patronictl -c /etc/patroni/patroni.yml failover
patronictl -c /etc/patroni/patroni.yml reinit pg18-cluster pg-node3 --force
```

> **Full 3-node PG 18 runbook:** [PostgreSQL 18 HA Setup Runbook](postgresql-18-ha-setup-runbook.md) — step-by-step Patroni + etcd + HAProxy (based on production IntelliDB pattern).

## repmgr

Extension + tools for replication management and failover.

```bash
repmgr primary register
repmgr standby clone -h primary -U repmgr -d repmgr
repmgr standby register
repmgr daemon start   # repmgrd for auto-failover

repmgr cluster show
repmgr standby promote
repmgr node rejoin -h new_primary --force-rewind
```

## pgpool-II

Connection pooler + query router + optional automatic failover (with watchdog).

### Key Features

| Feature | Description |
|---------|-------------|
| Connection pooling | Multiplex client connections |
| Load balancing | SELECT to replicas, writes to primary |
| Query cache | Deprecated/limited use |
| Automatic failover | With watchdog + scripts |

### pgpool.conf Highlights

```ini
listen_addresses = '*'
port = 9999
backend_hostname0 = '10.0.1.1'
backend_port0 = 5432
backend_weight0 = 1
backend_flag0 = 'ALLOW_TO_FAILOVER'
backend_hostname1 = '10.0.1.2'
backend_port1 = 5432
backend_weight1 = 1
backend_flag1 = 'ALLOW_TO_FAILOVER'

load_balance_mode = on
master_slave_mode = on
master_slave_sub_mode = 'stream'
sr_check_period = 10
health_check_period = 10
failover_command = '/etc/pgpool-II/failover.sh %d %h'
```

Apps connect to pgpool port 9999, not directly to PostgreSQL.

## Tool Selection Guide

| Need | Tool |
|------|------|
| Auto failover + K8s/cloud native | Patroni |
| Simple replication mgmt | repmgr |
| Connection pooling + read split | PgBouncer + HAProxy, or pgpool |
| Pooling only | **PgBouncer** (lighter than pgpool) |

## HAProxy Example (with Patroni)

```
frontend postgres_write
  bind *:5000
  default_backend postgres_primary

backend postgres_primary
  option httpchk GET /primary
  server node1 10.0.1.1:5432 check port 8008
  server node2 10.0.1.2:5432 check port 8008
  server node3 10.0.1.3:5432 check port 8008
```

Patroni REST API exposes `/primary`, `/replica`, `/health` endpoints.

## Related

- [Failover](failover.md)
- [Connection Pooling](../10-advanced/connection-pooling.md)
- [Streaming Replication](streaming-replication.md)
