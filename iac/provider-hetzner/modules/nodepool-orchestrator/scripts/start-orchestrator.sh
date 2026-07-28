#!/bin/bash
# Provisioning script for Hetzner dedicated servers (orchestrator nodes).
# Configures vSwitch VLAN interface, hugepages, swap, NBD, Consul client, Nomad client.
# Runs via Terraform remote-exec on pre-installed Ubuntu dedicated servers.

set -e

exec > >(tee /var/log/start-orchestrator.log) 2>&1
echo "Starting orchestrator node setup..."

# ---
# 1. Configure vSwitch VLAN network interface
# ---
echo "[Configuring vSwitch VLAN interface]"

# Detect primary physical NIC (first non-lo, non-virtual interface)
PRIMARY_NIC=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v docker | grep -v veth | grep -v br- | head -1)
echo "- Primary NIC: $PRIMARY_NIC"

VLAN_IF="$PRIMARY_NIC.${VLAN_ID}"
PRIVATE_IP="${PRIVATE_IP}"

# Create VLAN interface if it doesn't exist
if ! ip link show "$VLAN_IF" &>/dev/null; then
  ip link add link "$PRIMARY_NIC" name "$VLAN_IF" type vlan id ${VLAN_ID}
fi

ip link set "$VLAN_IF" mtu 1400
ip addr flush dev "$VLAN_IF" 2>/dev/null || true
ip addr add "$PRIVATE_IP/${PRIVATE_SUBNET_CIDR}" dev "$VLAN_IF"
ip link set "$VLAN_IF" up

# Add route to Cloud Network via VLAN interface
ip route replace ${CLOUD_NETWORK_RANGE} dev "$VLAN_IF"

echo "- VLAN interface $VLAN_IF configured with IP $PRIVATE_IP"

# Make persistent via netplan
mkdir -p /etc/netplan
cat > /etc/netplan/60-vswitch.yaml <<EOF
network:
  version: 2
  vlans:
    $VLAN_IF:
      id: ${VLAN_ID}
      link: $PRIMARY_NIC
      mtu: 1400
      addresses:
        - $PRIVATE_IP/${PRIVATE_SUBNET_CIDR}
      routes:
        - to: ${CLOUD_NETWORK_RANGE}
          scope: link
EOF

echo "- Netplan config written to /etc/netplan/60-vswitch.yaml"

# ---
# 2. Create orchestrator directories
# ---
mkdir -p /orchestrator /orchestrator/sandbox /orchestrator/template /orchestrator/build

# ---
# 3. Swap (100GB)
# ---
if [ ! -f /swapfile ]; then
  echo "[Setting up swap]"
  fallocate -l 100G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
  sysctl vm.swappiness=10
  sysctl vm.vfs_cache_pressure=50
fi

# ---
# 4. Snapshot cache (tmpfs, 65GB)
# ---
mkdir -p /mnt/snapshot-cache
if ! mountpoint -q /mnt/snapshot-cache; then
  mount -t tmpfs -o size=65G tmpfs /mnt/snapshot-cache
fi

ulimit -n 1048576
export GOMAXPROCS=$(nproc)

# ---
# 5. Sysctl tuning
# ---
cat > /etc/sysctl.d/99-orchestrator.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.max_map_count = 1048576
EOF
sysctl --system

# ---
# 6. NBD devices
# ---
echo "[Setting up NBD]"
cat > /etc/udev/rules.d/97-nbd-device.rules <<EOH
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOH
udevadm control --reload-rules
udevadm trigger
modprobe nbd nbds_max=4096

mkdir -p /fc-vm

# ---
# 7. Docker config
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
# 8. Hugepages setup
# ---
echo "[Setting up huge pages]"
mkdir -p /mnt/hugepages
mountpoint -q /mnt/hugepages || mount -t hugetlbfs none /mnt/hugepages

available_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
available_ram=$(($available_ram / 1024))
echo "- Total memory: $available_ram MiB"

min_normal_ram=$((4 * 1024))
min_normal_percentage_ram=$(($available_ram * 16 / 100))
max_normal_ram=$((42 * 1024))

max() { if (($1 > $2)); then echo "$1"; else echo "$2"; fi; }
min() { if (($1 < $2)); then echo "$1"; else echo "$2"; fi; }
ensure_even() { if (($1 % 2 == 0)); then echo "$1"; else echo $(($1 - 1)); fi; }
remove_decimal() { echo "$1" | sed 's/\..*//'; }

reserved_normal_ram=$(max $min_normal_ram $min_normal_percentage_ram)
reserved_normal_ram=$(min $reserved_normal_ram $max_normal_ram)

hugepages_ram=$(($available_ram - $reserved_normal_ram))
hugepages_ram=$(remove_decimal $hugepages_ram)
hugepages_ram=$(ensure_even $hugepages_ram)

hugepage_size_in_mib=2
hugepages=$(($hugepages_ram / $hugepage_size_in_mib))

base_hugepages_percentage=${BASE_HUGEPAGES_PERCENTAGE}
base_hugepages=$(($hugepages * $base_hugepages_percentage / 100))
base_hugepages=$(remove_decimal $base_hugepages)
echo "- Allocating $base_hugepages huge pages ($base_hugepages_percentage%) for base usage"
echo $base_hugepages > /proc/sys/vm/nr_hugepages

overcommitment_hugepages_percentage=$((100 - $base_hugepages_percentage))
overcommitment_hugepages=$(($hugepages * $overcommitment_hugepages_percentage / 100))
overcommitment_hugepages=$(remove_decimal $overcommitment_hugepages)
echo "- Allocating $overcommitment_hugepages huge pages ($overcommitment_hugepages_percentage%) for overcommitment"
echo $overcommitment_hugepages > /proc/sys/vm/nr_overcommit_hugepages

# ---
# 9. Consul DNS via systemd-resolved
# ---
mkdir -p /etc/systemd/resolved.conf.d/
cat > /etc/systemd/resolved.conf.d/consul.conf <<EOF
[Resolve]
DNS=127.0.0.1:8600
DNSSEC=false
DNSStubListener=yes
DNSStubListenerExtra=172.17.0.1
EOF

# ---
# 10. Consul Client
# ---
echo "[Starting Consul client]"
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
  "retry_join": ${CONSUL_RETRY_JOIN},
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
systemctl restart consul.service

# Wait for Consul DNS
echo "- Waiting for Consul DNS on port 8600..."
for i in $(seq 1 60); do
  if nc -z 127.0.0.1 8600 2>/dev/null; then
    echo "- Consul DNS is ready (attempt $i/60)"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "- ERROR: Consul DNS not responding after 60 seconds"
    exit 1
  fi
  sleep 1
done

systemctl restart systemd-resolved
for i in $(seq 1 60); do
  if host google.com 2>/dev/null; then
    echo "- DNS resolving is ready"
    break
  fi
  sleep 1
done
resolvectl flush-caches

# ---
# 11. Nomad Client
# ---
echo "[Starting Nomad client]"
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
    "node_pool"   = "${NODE_POOL}"
    "node_labels" = "${NODE_LABELS}"
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
systemctl restart nomad.service

echo "Orchestrator node setup complete."
