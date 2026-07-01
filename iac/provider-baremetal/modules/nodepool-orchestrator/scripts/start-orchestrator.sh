#!/bin/bash
# Bootstrap script for orchestrator nodes (baremetal; KVM + Firecracker).
# Configures hugepages, swap, NBD, Consul client, Nomad client.

set -e

exec > >(tee /var/log/start-orchestrator.log) 2>&1
echo "Starting orchestrator node setup..."

PRIVATE_IP="${PRIVATE_IP}"

# ---
# 1. Directories
# ---
mkdir -p /orchestrator /orchestrator/sandbox /orchestrator/template /orchestrator/build

# ---
# 2. Swap (100GB)
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
# 3. Snapshot cache (tmpfs, 65GB)
# ---
mkdir -p /mnt/snapshot-cache
if ! mountpoint -q /mnt/snapshot-cache; then
  mount -t tmpfs -o size=65G tmpfs /mnt/snapshot-cache
fi

ulimit -n 1048576
export GOMAXPROCS=$(nproc)

# ---
# 4. Sysctl tuning
# ---
cat > /etc/sysctl.d/99-orchestrator.conf <<EOF
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.max_map_count = 1048576
EOF
sysctl --system

# ---
# 5. NBD devices
# ---
echo "[Setting up NBD]"
cat > /etc/udev/rules.d/97-nbd-device.rules <<EOH
ACTION=="add|change", KERNEL=="nbd*", OPTIONS:="nowatch"
EOH
udevadm control --reload-rules
udevadm trigger
# Persist module load across reboots and pin nbds_max so the orchestrator's
# device pool sizing is stable.
echo 'nbd' > /etc/modules-load.d/nbd.conf
echo 'options nbd nbds_max=4096' > /etc/modprobe.d/nbd.conf
modprobe -r nbd 2>/dev/null || true
modprobe nbd

mkdir -p /fc-vm

# ---
# 6. Firecracker binaries + envd + guest kernels (downloaded from S3)
# ---
# The orchestrator needs these on-disk:
#   /fc-envd/envd             — envd binary injected into each sandbox rootfs
#   /fc-kernels/<version>/... — Firecracker guest kernels (vmlinux.bin)
#   /fc-versions/<version>/firecracker — Firecracker VMM binaries (by version)
# On other providers these are FUSE-mounted from GCS. For Hetzner Object
# Storage we download at boot; the VM has enough disk (200 GB) and the
# transfer is <1 GB total.
echo "[Setting up /fc-envd, /fc-kernels, /fc-versions]"
mkdir -p /fc-envd /fc-kernels /fc-versions

# awscli v2 (apt has no package on Ubuntu 24.04)
if ! command -v aws >/dev/null; then
  apt-get install -y unzip >/dev/null
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  ( cd /tmp && unzip -q awscliv2.zip && ./aws/install >/dev/null && rm -rf awscliv2.zip aws )
fi

export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
export AWS_DEFAULT_REGION="${S3_REGION}"
S3_OPTS=(--endpoint-url "https://${S3_ENDPOINT}")

# envd (single file; may be overwritten on re-run to pick up new version)
aws s3 "$${S3_OPTS[@]}" cp "s3://${FC_ENV_PIPELINE_BUCKET_NAME}/envd" /fc-envd/envd
chmod +x /fc-envd/envd

# kernels + firecracker versions (mirror-style, no delete on remote)
aws s3 "$${S3_OPTS[@]}" sync "s3://${FC_KERNELS_BUCKET_NAME}/"  /fc-kernels/
aws s3 "$${S3_OPTS[@]}" sync "s3://${FC_VERSIONS_BUCKET_NAME}/" /fc-versions/

# Firecracker binaries aren't stored with +x; fix permissions.
find /fc-versions -name firecracker -type f -exec chmod +x {} +

# Busybox is read from disk at runtime by the orchestrator
# (HOST_BUSYBOX_DIR/BUSYBOX_VERSION/<arch>/busybox; default /fc-busybox/1.36.1/amd64),
# no longer embedded in the binary (upstream #2326). Fetch from the e2b public bucket.
mkdir -p /fc-busybox/1.36.1/amd64
curl -fsSL "https://storage.googleapis.com/e2b-prod-public-builds/busybox/1.36.1/amd64/busybox" -o /fc-busybox/1.36.1/amd64/busybox
chmod +x /fc-busybox/1.36.1/amd64/busybox

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

# ---
# 7. Docker registry auth
# ---
mkdir -p /root/docker
%{ if CONTAINER_REGISTRY_URL != "" }
cat > /root/docker/config.json <<EOF
{
    "auths": {
        "${CONTAINER_REGISTRY_URL}": { "auth": "${REGISTRY_AUTH}" }
    }
}
EOF
%{ else }
echo '{}' > /root/docker/config.json
%{ endif }

# ---
# 7. Hugepages
# ---
echo "[Setting up huge pages + runtime mounts via systemd oneshot]"
# nr_hugepages and the hugetlbfs/tmpfs mounts do NOT survive a reboot, and this
# bootstrap only runs once (at provision time). Install a systemd oneshot that
# re-applies them on every boot BEFORE Nomad starts, so Firecracker always has
# hugepage-backed guest memory. Otherwise, after any reboot, template builds fail
# with FC "Cannot load kernel ... invalid memory configuration".
cat > /usr/local/bin/e2b-node-runtime.sh <<'RUNTIME'
#!/bin/bash
set -e
# Runtime mounts (idempotent)
mkdir -p /mnt/hugepages /mnt/snapshot-cache
mountpoint -q /mnt/hugepages      || mount -t hugetlbfs none /mnt/hugepages
mountpoint -q /mnt/snapshot-cache || mount -t tmpfs -o size=65G tmpfs /mnt/snapshot-cache
# Hugepage allocation (RAM-dependent; recomputed each boot)
available_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
available_ram=$((available_ram / 1024))
min_normal_ram=$((4 * 1024))
min_normal_percentage_ram=$((available_ram * 16 / 100))
max_normal_ram=$((42 * 1024))
reserved=$(( min_normal_ram > min_normal_percentage_ram ? min_normal_ram : min_normal_percentage_ram ))
reserved=$(( reserved < max_normal_ram ? reserved : max_normal_ram ))
hugepages_ram=$((available_ram - reserved))
if (( hugepages_ram % 2 )); then hugepages_ram=$((hugepages_ram - 1)); fi
hugepages=$((hugepages_ram / 2))
base=$(( hugepages * ${BASE_HUGEPAGES_PERCENTAGE} / 100 ))
over=$(( hugepages * (100 - ${BASE_HUGEPAGES_PERCENTAGE}) / 100 ))
echo "$base" > /proc/sys/vm/nr_hugepages
echo "$over" > /proc/sys/vm/nr_overcommit_hugepages
echo "e2b-node-runtime: nr_hugepages=$(cat /proc/sys/vm/nr_hugepages) nr_overcommit=$over"
RUNTIME
chmod +x /usr/local/bin/e2b-node-runtime.sh

cat > /etc/systemd/system/e2b-node-runtime.service <<'UNIT'
[Unit]
Description=E2B node runtime setup (hugepages + tmpfs/hugetlbfs mounts)
After=local-fs.target
Before=nomad.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/e2b-node-runtime.sh
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now e2b-node-runtime.service

# ---
# 8. Consul DNS via systemd-resolved
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
# 9. Consul Client
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

echo "- Waiting for Consul DNS on port 8600..."
for i in $(seq 1 60); do
  if nc -z 127.0.0.1 8600 2>/dev/null; then
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
    break
  fi
  sleep 1
done
resolvectl flush-caches

# ---
# 10. Nomad Client
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
    allow_privileged = true
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
