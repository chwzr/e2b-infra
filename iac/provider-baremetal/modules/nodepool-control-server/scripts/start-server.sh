#!/bin/bash
# Bootstrap script for Nomad/Consul control-server nodes (baremetal).
# Configures and starts Consul and Nomad in server mode. Assumes the base VM
# template already has Consul + Nomad binaries installed (see Packer build).

set -e

exec > >(tee /var/log/start-server.log | logger -t start-server -s 2>/dev/console) 2>&1

ulimit -n 65536
export GOMAXPROCS=$(nproc)

PRIVATE_IP="${PRIVATE_IP}"

# ---
# Consul Server
# ---
mkdir -p /opt/consul/config /opt/consul/data

cat > /opt/consul/config/default.json <<EOF
{
  "connect": { "enabled": true },
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "tokens": { "default": "${CONSUL_TOKEN}" }
  },
  "telemetry": { "prometheus_retention_time": "2h", "disable_hostname": true },
  "limits": { "http_max_conns_per_client": 80 },
  "advertise_addr": "$PRIVATE_IP",
  "bind_addr": "$PRIVATE_IP",
  "bootstrap_expect": ${NUM_SERVERS},
  "client_addr": "0.0.0.0",
  "datacenter": "${DATACENTER}",
  "node_name": "$(hostname)",
  "leave_on_terminate": true,
  "skip_leave_on_interrupt": true,
  "retry_join": ${CONSUL_RETRY_JOIN},
  "server": true,
  "encrypt": "${CONSUL_GOSSIP_ENCRYPTION_KEY}",
  "autopilot": {
    "cleanup_dead_servers": true,
    "last_contact_threshold": "200ms",
    "max_trailing_logs": 250,
    "server_stabilization_time": "10s"
  },
  "ui": true
}
EOF

cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=HashiCorp Consul
Requires=network-online.target
After=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/consul agent -config-dir /opt/consul/config -data-dir /opt/consul/data
ExecReload=/usr/local/bin/consul reload
ExecStop=/usr/local/bin/consul leave
KillMode=process
Restart=on-failure
TimeoutSec=300s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable consul.service
systemctl restart consul.service

# Wait for Consul; bootstrap ACL on leader
echo "Waiting for Consul to start..."
for i in $(seq 1 60); do
  consul_leader_addr=$(curl -s http://localhost:8500/v1/status/leader 2>/dev/null || true)
  if [[ "$consul_leader_addr" == "\"$PRIVATE_IP:8300\"" ]]; then
    echo "This node is the Consul leader, bootstrapping ACL..."
    echo "${CONSUL_TOKEN}" > /tmp/consul.token
    consul acl bootstrap /tmp/consul.token 2>/dev/null || echo "ACL already bootstrapped"
    rm -f /tmp/consul.token

    # Create DNS + service-register policies and bind them to the well-known
    # CONSUL_DNS_REQUEST_TOKEN that every client uses as `tokens.default`.
    # Without this the clients' ACL queries return empty DNS results and no
    # service registrations.
    if ! consul acl policy read -name dns-request-policy -token "${CONSUL_TOKEN}" >/dev/null 2>&1; then
      consul acl policy create -name dns-request-policy -token "${CONSUL_TOKEN}" \
        -rules 'node_prefix "" { policy = "read" } service_prefix "" { policy = "read" }' \
        || echo "failed to create dns-request-policy (may already exist)"
    fi
    if ! consul acl policy read -name register-service-policy -token "${CONSUL_TOKEN}" >/dev/null 2>&1; then
      consul acl policy create -name register-service-policy -token "${CONSUL_TOKEN}" \
        -rules 'service_prefix "" { policy = "write" }' \
        || echo "failed to create register-service-policy (may already exist)"
    fi
    # consul acl token create fails with 'Secret ID is not unique' when the
    # token already exists — treat that as success.
    consul acl token create -token "${CONSUL_TOKEN}" \
      -secret "${CONSUL_DNS_REQUEST_TOKEN}" \
      -description "DNS + service-register token (used as tokens.default on all clients)" \
      -policy-name dns-request-policy \
      -policy-name register-service-policy \
      2>&1 | grep -vE 'Secret ID is not unique|already exists' || true
    break
  fi
  if [[ -n "$consul_leader_addr" && "$consul_leader_addr" != "\"\"" ]]; then
    echo "Consul is already bootstrapped by another node"
    break
  fi
  sleep 2
done

# ---
# Nomad Server
# ---
mkdir -p /opt/nomad/config /opt/nomad/data /opt/nomad/log /opt/nomad/plugins

cat > /opt/nomad/config/default.hcl <<EOF
datacenter = "${DATACENTER}"
name       = "$(hostname)"
region     = "${DATACENTER}"
bind_addr  = "0.0.0.0"

advertise {
  http = "$PRIVATE_IP"
  rpc  = "$PRIVATE_IP"
  serf = "$PRIVATE_IP"
}

leave_on_interrupt = true
leave_on_terminate = true

server {
  enabled          = true
  bootstrap_expect = ${NUM_SERVERS}
}

plugin_dir = "/opt/nomad/plugins"

plugin "docker" {
  config {
    volumes {
      enabled = true
    }
  }
}

log_level = "DEBUG"
log_json  = true

telemetry {
  collection_interval        = "5s"
  disable_hostname           = true
  prometheus_metrics         = true
  publish_allocation_metrics = true
  publish_node_metrics       = true
}

acl {
  enabled = true
}

limits {
  http_max_conns_per_client = 80
  rpc_max_conns_per_client  = 80
}

consul {
  address                = "127.0.0.1:8500"
  allow_unauthenticated  = false
  token                  = "${CONSUL_TOKEN}"
}
EOF

cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=HashiCorp Nomad
Wants=consul.service
After=consul.service

[Service]
ExecStart=/usr/local/bin/nomad agent -config /opt/nomad/config -data-dir /opt/nomad/data
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=2
LimitNOFILE=65536
LimitNPROC=infinity
TasksMax=infinity
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nomad.service
systemctl restart nomad.service

# Bootstrap Nomad ACL + create node pools (only the first node that reaches here succeeds)
echo "Waiting for Nomad to start..."
for i in $(seq 1 60); do
  if curl -s http://127.0.0.1:4646/v1/agent/health > /dev/null 2>&1; then
    echo "Nomad server started."

    echo "${NOMAD_TOKEN}" > /tmp/nomad.token
    nomad acl bootstrap /tmp/nomad.token 2>/dev/null || echo "Nomad ACL already bootstrapped"
    rm -f /tmp/nomad.token

    for pool in api ingress build default clickhouse; do
      cat > /tmp/$pool.hcl <<POOL
node_pool "$pool" {
  description = "Nodes for $pool."
}
POOL
      nomad node pool apply -token "${NOMAD_TOKEN}" /tmp/$pool.hcl 2>/dev/null || true
      rm -f /tmp/$pool.hcl
    done

    break
  fi
  sleep 2
done

echo "Control server setup complete."
