# SSL / TLS Implementation Guide

End-to-end guide for encrypting PostgreSQL **18** client connections with TLS — certificate generation, server config, client setup, HA, and mTLS.

> **PostgreSQL 18** supports TLS 1.2+ (TLS 1.3 recommended). See [VERSION.md](../VERSION.md).

---

## TLS vs SSL Terminology

PostgreSQL uses OpenSSL and refers to settings as `ssl = on`. In practice this means **TLS** (TLS 1.2/1.3). This guide uses TLS throughout.

| Layer | Protects against |
|-------|------------------|
| **TLS in transit** | Eavesdropping, MITM on network |
| **TDE / disk encryption** | Stolen disks/backups — see [TDE Implementation](tde-implementation.md) |

---

## Architecture Options

```
Option A — End-to-end TLS (recommended for compliance)
  App ──TLS──► PostgreSQL :5432

Option B — TLS at load balancer
  App ──TLS──► HAProxy/PgBouncer ──TLS or plain──► PostgreSQL

Option C — TLS only at app-to-proxy; plain in trusted VPC (common in cloud)
  App ──TLS──► RDS Proxy / HAProxy ──► RDS (AWS manages internal)
```

---

## Step 1 — Create Certificate Authority (Internal PKI)

### Option A — OpenSSL (simple lab / small org)

```bash
sudo mkdir -p /etc/postgresql/ssl/{ca,server,client}
cd /etc/postgresql/ssl/ca

# CA private key + self-signed CA cert (10 years)
openssl genrsa -out ca.key 4096
chmod 600 ca.key

openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=PostgreSQL-Internal-CA/O=MyOrg/C=US"

# Verify
openssl x509 -in ca.crt -text -noout | head -20
```

### Option B — cfssl (production internal CA)

```bash
# Install cfssl
curl -sL https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64 -o cfssl
curl -sL https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64 -o cfssljson
chmod +x cfssl cfssljson

cat > ca-config.json <<'EOF'
{
  "signing": {
    "default": { "expiry": "8760h" },
    "profiles": {
      "server": { "usages": ["signing", "key encipherment", "server auth"], "expiry": "8760h" },
      "client": { "usages": ["signing", "key encipherment", "client auth"], "expiry": "8760h" }
    }
  }
}
EOF

cat > ca-csr.json <<'EOF'
{ "CN": "PostgreSQL CA", "key": { "algo": "rsa", "size": 4096 }, "names": [{ "C": "US", "O": "MyOrg", "OU": "DBA" }] }
EOF

./cfssl gencert -initca ca-csr.json | ./cfssljson -bare ca
```

---

## Step 2 — Server Certificate

Certificate **CN or SAN** must match hostname clients use (`db.example.com`, not only IP).

### OpenSSL server cert with SAN

```bash
cd /etc/postgresql/ssl/server

cat > server.cnf <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = pg-node1.example.com

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = pg-node1.example.com
DNS.2 = pg-node2.example.com
DNS.3 = pg-node3.example.com
DNS.4 = db.example.com
IP.1 = 10.0.1.11
IP.2 = 10.0.1.12
IP.3 = 10.0.1.13
EOF

openssl genrsa -out server.key 2048
chmod 600 server.key

openssl req -new -key server.key -out server.csr -config server.cnf

openssl x509 -req -in server.csr -CA ../ca/ca.crt -CAkey ../ca/ca.key \
  -CAcreateserial -out server.crt -days 825 -sha256 \
  -extensions v3_req -extfile server.cnf

# Ownership for postgres OS user
sudo chown postgres:postgres server.key server.crt
sudo chmod 600 server.key
```

### Copy CA to clients

Distribute `ca.crt` to all application servers and DBAs (not the CA private key).

---

## Step 3 — PostgreSQL Server Configuration

### postgresql.conf (PG 18)

```ini
# ── Enable TLS ──
ssl = on
ssl_cert_file = '/etc/postgresql/ssl/server/server.crt'
ssl_key_file = '/etc/postgresql/ssl/server/server.key'
ssl_ca_file = '/etc/postgresql/ssl/ca/ca.crt'

# ── Protocol & cipher hardening ──
ssl_min_protocol_version = 'TLSv1.2'
# PG 15+: prefer TLS 1.3 when client supports it
ssl_max_protocol_version = 'TLSv1.3'

ssl_prefer_server_ciphers = on
ssl_ciphers = 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384'

# Optional: require strong DH
# ssl_dh_params_file = '/etc/postgresql/ssl/server/dhparam.pem'

# Client cert verification (mTLS) — see Step 6
# ssl_ca_file already set; enable in pg_hba with cert method
```

Generate DH params (optional, older TLS 1.2):

```bash
openssl dhparam -out /etc/postgresql/ssl/server/dhparam.pem 2048
chown postgres:postgres /etc/postgresql/ssl/server/dhparam.pem
```

### Apply and restart

```bash
# SSL changes require RESTART (not reload)
sudo systemctl restart postgresql-18
# Patroni-managed: patronictl restart pg18-cluster pg-node1
```

### Verify server

```bash
openssl s_client -connect 10.0.1.11:5432 -starttls postgres \
  -CAfile /etc/postgresql/ssl/ca/ca.crt </dev/null 2>/dev/null | openssl x509 -noout -subject -dates
```

```sql
SHOW ssl;
SHOW ssl_cert_file;
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

---

## Step 4 — pg_hba.conf — Force TLS

```
# Reject all non-SSL remote connections
hostnossl all             all             0.0.0.0/0               reject

# Application subnet — password over TLS
hostssl  all              all             10.0.2.0/24             scram-sha-256

# Replication over TLS
hostssl  replication       replicator      10.0.1.0/24             scram-sha-256

# Local socket — no TLS needed
local    all               all                                     peer
hostssl  all               all             127.0.0.1/32            scram-sha-256
```

```bash
SELECT pg_reload_conf();
```

---

## Step 5 — Client Configuration

### libpq / psql sslmode

| sslmode | Encrypted | Verifies CA | Verifies hostname |
|---------|-----------|-------------|-------------------|
| disable | No | — | — |
| allow | Try TLS | No | No |
| prefer | Try TLS | No | No |
| require | Yes | No | No |
| verify-ca | Yes | Yes | No |
| verify-full | Yes | Yes | Yes |

**Production:** use `verify-full` with correct hostname in connection string.

### psql

```bash
psql "host=db.example.com port=5432 dbname=app_db user=app_user \
  sslmode=verify-full sslrootcert=/etc/ssl/certs/pg-ca.crt"
```

### ~/.pg_service.conf

```ini
[app_prod]
host=db.example.com
port=5432
dbname=app_db
user=app_user
sslmode=verify-full
sslrootcert=/etc/ssl/certs/pg-ca.crt
```

### JDBC

```text
jdbc:postgresql://db.example.com:5432/app_db?sslmode=verify-full&sslrootcert=/path/to/ca.crt
```

### Python (psycopg3)

```python
conninfo = "host=db.example.com dbname=app_db user=app_user sslmode=verify-full sslrootcert=/etc/ssl/certs/pg-ca.crt"
```

### Node.js (pg)

```javascript
const pool = new Pool({
  host: 'db.example.com',
  ssl: { ca: fs.readFileSync('/etc/ssl/certs/pg-ca.crt'), rejectUnauthorized: true }
});
```

---

## Step 6 — Mutual TLS (mTLS) — Client Certificates

Server verifies client cert in addition to (or instead of) password.

### Issue client certificate

```bash
cd /etc/postgresql/ssl/client

openssl genrsa -out app_user.key 2048
chmod 600 app_user.key

openssl req -new -key app_user.key -out app_user.csr \
  -subj "/CN=app_user/O=MyOrg"

openssl x509 -req -in app_user.csr -CA ../ca/ca.crt -CAkey ../ca/ca.key \
  -out app_user.crt -days 825 -sha256
```

### pg_hba.conf

```
hostssl all app_user 10.0.2.0/24 cert clientcert=verify-full
```

Map cert CN to role if names differ (`pg_ident.conf`):

```
# pg_ident.conf
certmap   /^(.*)@example\.com$   \1
```

```
hostssl all all 10.0.2.0/24 cert map=certmap clientcert=verify-full
```

### Client connects with cert

```bash
psql "host=db.example.com dbname=app_db user=app_user sslmode=verify-full \
  sslrootcert=ca.crt sslcert=app_user.crt sslkey=app_user.key"
```

---

## Step 7 — TLS in HA / Patroni Cluster

### Each PostgreSQL node needs a server cert

- **Same cert** with all node SANs (simplest), or
- **Per-node cert** with matching SAN

### Patroni patroni.yml

```yaml
postgresql:
  parameters:
    ssl: "on"
    ssl_cert_file: /etc/postgresql/ssl/server/server.crt
    ssl_key_file: /etc/postgresql/ssl/server/server.key
    ssl_ca_file: /etc/postgresql/ssl/ca/ca.crt
    ssl_min_protocol_version: "TLSv1.2"
  pg_hba:
    - hostssl all all 10.0.2.0/24 scram-sha-256
    - hostssl replication replicator 10.0.1.0/24 scram-sha-256
    - hostnossl all all 0.0.0.0/0 reject
```

### Replication with SSL

```yaml
postgresql:
  parameters:
    primary_conninfo: "host=10.0.1.12 port=5432 user=replicator sslmode=verify-full sslrootcert=/etc/postgresql/ssl/ca/ca.crt"
```

Or in `postgresql.auto.conf` on standby:

```ini
primary_conninfo = 'host=10.0.1.11 port=5432 user=replicator password=... sslmode=verify-full sslrootcert=/etc/postgresql/ssl/ca/ca.crt'
```

### HAProxy TLS termination

```text
frontend pg_tls_frontend
    bind *:5432 ssl crt /etc/haproxy/certs/db.example.com.pem
    default_backend pg_write_backend

backend pg_write_backend
    option httpchk GET /primary
    server pg-node1 10.0.1.11:5432 check port 8008 ssl verify none
```

Apps connect to HAProxy with TLS; backend can use TLS or plain within trusted network.

---

## Step 8 — Cloud Managed PostgreSQL

| Platform | Client TLS | Server cert |
|----------|------------|-------------|
| **AWS RDS** | `sslmode=verify-full` + [RDS CA bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) | Amazon-managed |
| **Aurora** | Same RDS CA | Amazon-managed |
| **Cloud SQL** | Download server CA from console | Google-managed |
| **Azure Flexible** | Download Baltimore/DigiCert root | Microsoft-managed |

```bash
# RDS example
wget https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
psql "host=mydb.xxx.rds.amazonaws.com sslmode=verify-full sslrootcert=global-bundle.pem ..."
```

```bash
# Force SSL on RDS parameter group
rds.force_ssl = 1
```

---

## Certificate Rotation

### Zero-downtime rotation

```bash
# 1. Install new cert alongside old (different filenames)
cp new_server.crt /etc/postgresql/ssl/server/server.crt.new
cp new_server.key /etc/postgresql/ssl/server/server.key.new

# 2. Atomic swap
mv server.crt server.crt.old && mv server.crt.new server.crt
mv server.key server.key.old && mv server.key.new server.key

# 3. Restart PostgreSQL (required for cert reload in some configs)
sudo systemctl restart postgresql-18

# 4. Update clients with new CA if CA changed
# 5. Remove .old files after validation period
```

PostgreSQL reloads cert on **SIGHUP** in many versions if same path — test in staging.

---

## Monitoring & Audit

```sql
-- Active SSL connections
SELECT pid, usename, datname, client_addr, ssl, version, cipher, client_dn
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE ssl = true;

-- Non-SSL connections (should be zero for remote)
SELECT pid, usename, client_addr
FROM pg_stat_activity a
LEFT JOIN pg_stat_ssl s USING (pid)
WHERE client_addr IS NOT NULL AND (s.ssl IS NULL OR s.ssl = false);
```

Alert on remote connections without SSL.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `SSL off` / connection refused | `ssl = off` | Enable ssl; restart |
| `certificate verify failed` | Wrong CA or expired cert | Renew; fix sslrootcert path |
| `hostname does not match` | CN/SAN mismatch | Regenerate cert with correct SAN; use verify-full hostname |
| `private key file permissions` | Key world-readable | `chmod 600`; owner postgres |
| `no pg_hba.conf entry` for hostssl | Rule uses `host` not `hostssl` | Add hostssl rule |
| `could not load private key` | Encrypted key without password | Use unencrypted key for server or provide passphrase |
| JDBC `unable to find valid certification path` | Missing CA in truststore | Import ca.crt |

```bash
# Debug TLS handshake
openssl s_client -connect db.example.com:5432 -starttls postgres -showcerts
```

---

## Security Checklist

- [ ] TLS 1.2 minimum (TLS 1.3 preferred)
- [ ] Strong ciphers only; disable weak protocols
- [ ] `hostnossl ... reject` for remote connections
- [ ] Client `sslmode=verify-full` in production
- [ ] Cert SAN includes all hostnames apps use
- [ ] Private keys `chmod 600`, owned by `postgres`
- [ ] CA private key offline / HSM — not on DB server
- [ ] Certificate expiry monitoring (< 30 days alert)
- [ ] Replication connections use SSL
- [ ] pgAudit logs connection metadata

---

## Related

- [Encryption Overview](encryption.md)
- [TDE Implementation](tde-implementation.md)
- [pg_hba.conf](../02-configuration/pg-hba-conf.md)
- [Authentication](authentication.md)
- [PG 18 HA Runbook](../05-replication-ha/postgresql-18-ha-setup-runbook.md)
