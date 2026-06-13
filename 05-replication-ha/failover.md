# Failover & Switchover

> **PostgreSQL 18 + Patroni:** prefer `patronictl switchover` / automatic failover. See [PG 18 HA Runbook](postgresql-18-ha-setup-runbook.md).

## Terminology

| Term | Meaning |
|------|---------|
| **Switchover** | Planned primary ↔ standby swap |
| **Failover** | Unplanned promotion after primary failure |
| **Split-brain** | Two nodes both accepting writes — catastrophic |

## Manual Failover (Streaming Replication)

### Planned Switchover

```bash
# 1. On primary — checkpoint and stop cleanly
psql -c "CHECKPOINT;"
pg_ctl -D $PGDATA stop -m smart

# 2. On standby — promote
pg_ctl -D $PGDATA promote
# removes standby.signal, starts accepting writes

# 3. Verify
psql -c "SELECT pg_is_in_recovery();"  # false

# 4. Repoint applications / VIP / DNS
# 5. Rebuild old primary as standby (pg_rewind or new basebackup)
```

### Emergency Failover

```bash
# Confirm primary is truly dead (avoid split-brain!)
# Promote most caught-up standby
pg_ctl -D $PGDATA promote

# Or touch trigger file (legacy):
# touch $PGDATA/failover.trigger  # if using older tooling
```

### Rebuild Old Primary with pg_rewind

```bash
# After old primary comes back, avoid full re-clone
pg_rewind --target-pgdata=$PGDATA \
  --source-server='host=new_primary user=postgres'
touch $PGDATA/standby.signal
pg_ctl -D $PGDATA start
```

Requires `wal_log_hints = on` or data checksums enabled at init.

## Choosing Standby to Promote

```sql
-- Compare replay lag on candidates
SELECT pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
```

Promote the standby with smallest lag to minimize data loss (async replication).

## Application Cutover Checklist

- [ ] Stop writes to old primary (or confirm it's down)
- [ ] Promote standby
- [ ] Update connection strings / load balancer / DNS
- [ ] Verify sequences, replication slots, cron jobs
- [ ] Recreate subscriptions/publications if needed
- [ ] Monitor for errors post-cutover

## Timeline Considerations

After promotion, cluster gets new **timeline**. Standbys and backups must follow new timeline.

## Automated HA Tools

See [Patroni & pgpool](patroni-pgpool.md) for:
- Leader election (etcd/Consul/ZooKeeper)
- Automatic failover
- Health checks

## Split-Brain Prevention

1. Use odd-number quorum (etcd/Consul)
2. STONITH — fence old primary (disable IP, shutdown VM)
3. `synchronous_commit` with quorum standbys
4. Never promote if old primary might still be alive without fencing

## Delayed Standby (Human Error Protection)

```sql
-- recovery.conf / postgresql.auto.conf on dedicated standby
recovery_min_apply_delay = '4h'
```

Replay lag intentionally — use for "oops DROP TABLE" recovery within window.

## Related

- [Streaming Replication](streaming-replication.md)
- [Patroni & pgpool](patroni-pgpool.md)
- [PITR](../04-backup-recovery/point-in-time-recovery.md)
