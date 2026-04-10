#!/bin/bash
# This script is meant to be run as cloud-init user_data on Hetzner Cloud servers.
# It configures and starts Consul and Nomad in server mode.
# Assumes the server image has Consul and Nomad pre-installed.

set -e

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

ulimit -n 65536
export GOMAXPROCS=$(nproc)

# ---
# Consul Server Configuration
# ---

PRIVATE_IP=$(ip -4 addr show ens10 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I | awk '{print $1}')

mkdir -p /opt/consul/config /opt/consul/data

cat > /opt/consul/config/default.json <<EOF
{
  "connect": {
    "enabled": true
  },
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "tokens": {
      "default": "${CONSUL_TOKEN}"
    }
  },
  "telemetry": {
    "prometheus_retention_time": "2h",
    "disable_hostname": true
  },
  "limits": {
    "http_max_conns_per_client": 80
  },
  "advertise_addr": "$PRIVATE_IP",
  "bind_addr": "$PRIVATE_IP",
  "bootstrap_expect": ${NUM_SERVERS},
  "client_addr": "0.0.0.0",
  "datacenter": "${DATACENTER}",
  "node_name": "$(hostname)",
  "leave_on_terminate": true,
  "skip_leave_on_interrupt": true,
  "retry_join": ["provider=hcloud tag_name=cluster tag_value=${CLUSTER_TAG_VALUE} token=${HCLOUD_TOKEN}"],
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

# Create systemd service for Consul
cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description=HashiCorp Consul
Documentation=https://www.consul.io/
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
systemctl start consul.service

# Wait for Consul to be ready and bootstrap ACL if this is the leader
echo "Waiting for Consul to start..."
for i in $(seq 1 60); do
  consul_leader_addr=$(curl -s http://localhost:8500/v1/status/leader 2>/dev/null || true)
  if [[ "$consul_leader_addr" == "\"$PRIVATE_IP:8300\"" ]]; then
    echo "This node is the Consul leader, bootstrapping ACL..."
    echo "${CONSUL_TOKEN}" > /tmp/consul.token
    consul acl bootstrap /tmp/consul.token 2>/dev/null || echo "ACL already bootstrapped"
    rm -f /tmp/consul.token
    break
  fi
  if [[ -n "$consul_leader_addr" && "$consul_leader_addr" != "\"\"" ]]; then
    echo "Consul is already bootstrapped by another node"
    break
  fi
  sleep 2
done

# ---
# Nomad Server Configuration
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

# Create systemd service for Nomad
cat > /etc/systemd/system/nomad.service <<EOF
[Unit]
Description=HashiCorp Nomad
Documentation=https://www.nomadproject.io/
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
systemctl start nomad.service

# Wait for Nomad to be ready and bootstrap ACL
echo "Waiting for Nomad to start..."
for i in $(seq 1 60); do
  if curl -s http://127.0.0.1:4646/v1/agent/health > /dev/null 2>&1; then
    echo "Nomad server started."

    # Bootstrap Nomad ACL (only succeeds on the first server)
    echo "${NOMAD_TOKEN}" > /tmp/nomad.token
    nomad acl bootstrap /tmp/nomad.token 2>/dev/null || echo "Nomad ACL already bootstrapped"
    rm -f /tmp/nomad.token

    # Create node pools
    cat > /tmp/api_node_pool.hcl <<POOL
node_pool "api" {
  description = "Nodes for api."
}
POOL
    nomad node pool apply -token "${NOMAD_TOKEN}" /tmp/api_node_pool.hcl 2>/dev/null || true

    cat > /tmp/build_node_pool.hcl <<POOL
node_pool "build" {
  description = "Nodes for template builds."
}
POOL
    nomad node pool apply -token "${NOMAD_TOKEN}" /tmp/build_node_pool.hcl 2>/dev/null || true
    rm -f /tmp/api_node_pool.hcl /tmp/build_node_pool.hcl

    break
  fi
  sleep 2
done

echo "Server setup complete."
