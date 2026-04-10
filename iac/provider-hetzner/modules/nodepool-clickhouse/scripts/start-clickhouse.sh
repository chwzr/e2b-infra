#!/bin/bash
# Cloud-init script for ClickHouse nodes on Hetzner Cloud.
# Mounts persistent volume, configures Consul client + Nomad client with job constraint.

set -e

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

ulimit -n 1048576
export GOMAXPROCS=$(nproc)

# ---
# Sysctl tuning
# ---
cat >> /etc/sysctl.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
EOF
sysctl -p

# ---
# Mount persistent volume for ClickHouse data
# ---
VOLUME_DEVICE="/dev/disk/by-id/scsi-0HC_Volume_${VOLUME_ID}"
MOUNT_POINT="/clickhouse"

mkdir -p $MOUNT_POINT

echo "Waiting for volume device $VOLUME_DEVICE..."
for i in $(seq 1 120); do
  if [ -e "$VOLUME_DEVICE" ]; then
    echo "Volume device found (attempt $i/120)"
    break
  fi
  if [ $i -eq 120 ]; then
    echo "ERROR: Volume device not found after 120 seconds"
    exit 1
  fi
  sleep 2
done

# Format if needed (check for existing XFS filesystem)
if ! blkid "$VOLUME_DEVICE" | grep -q xfs; then
  echo "Formatting volume as XFS..."
  mkfs.xfs "$VOLUME_DEVICE"
fi

mount -o noatime "$VOLUME_DEVICE" "$MOUNT_POINT"
echo "$VOLUME_DEVICE $MOUNT_POINT xfs noatime 0 2" >> /etc/fstab

mkdir -p $MOUNT_POINT/data

# ---
# Get private IP
# ---
PRIVATE_IP=$(ip -4 addr show ens10 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || hostname -I | awk '{print $1}')

# ---
# Docker config
# ---
mkdir -p /root/docker
%{ if CONTAINER_REGISTRY_URL != "" }
cat > /root/docker/config.json <<EOF
{
    "auths": {
        "${CONTAINER_REGISTRY_URL}": {}
    }
}
EOF
%{ else }
echo '{}' > /root/docker/config.json
%{ endif }

# ---
# Consul DNS via systemd-resolved
# ---
mkdir -p /etc/systemd/resolved.conf.d/
cat > /etc/systemd/resolved.conf.d/consul.conf <<EOF
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
Domains=~consul
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF
systemctl restart systemd-resolved

# ---
# Consul Client
# ---
mkdir -p /opt/consul/config /opt/consul/data

cat > /opt/consul/config/default.json <<EOF
{
  "connect": { "enabled": true },
  "acl": {
    "enabled": true,
    "default_policy": "deny",
    "enable_token_persistence": true,
    "tokens": { "default": "${CONSUL_DNS_REQUEST_TOKEN}" }
  },
  "telemetry": { "prometheus_retention_time": "2h", "disable_hostname": true },
  "limits": { "http_max_conns_per_client": 80 },
  "advertise_addr": "$PRIVATE_IP",
  "bind_addr": "$PRIVATE_IP",
  "client_addr": "0.0.0.0",
  "datacenter": "${DATACENTER}",
  "node_name": "$(hostname)",
  "leave_on_terminate": true,
  "retry_join": ["provider=hcloud tag_name=cluster tag_value=${CLUSTER_TAG_VALUE} token=${HCLOUD_TOKEN}"],
  "server": false,
  "encrypt": "${CONSUL_GOSSIP_ENCRYPTION_KEY}",
  "ui": false
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
systemctl start consul.service

# ---
# Nomad Client with job constraint metadata
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

client {
  enabled   = true
  node_pool = "${NODE_POOL}"
  meta {
    "node_pool"      = "${NODE_POOL}"
    "job_constraint"  = "${JOB_CONSTRAINT}"
  }
  max_kill_timeout = "24h"
}

plugin_dir = "/opt/nomad/plugins"

plugin "raw_exec" {
  config {
    enabled    = true
    no_cgroups = true
  }
}

plugin "docker" {
  config {
    volumes {
      enabled = true
    }
    auth {
      config = "/root/docker/config.json"
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
systemctl start nomad.service

echo "ClickHouse node setup complete."
