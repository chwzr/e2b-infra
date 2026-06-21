#!/bin/bash
# Base-image-equivalent setup for baremetal E2B nodes.
# Installs everything the proxmox Packer build used to bake: base packages,
# Docker, Go, gruntwork bash-commons, Consul/Nomad/Vault, qemu-guest-agent,
# and limits/conntrack tuning.
#
# Idempotent: every install is guarded so re-runs on `terraform apply` are cheap.
#
# Usage: [CONSUL_VERSION=x NOMAD_VERSION=y VAULT_VERSION=z] setup-base.sh <role>
#   <role> one of: control-server api ingress orchestrator build clickhouse
# For orchestrator/build, asserts /dev/kvm exists (hardware virt required).

set -euo pipefail

ROLE="${1:-}"
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONSUL_VERSION="${CONSUL_VERSION:-1.16.2}"
NOMAD_VERSION="${NOMAD_VERSION:-1.6.2}"
VAULT_VERSION="${VAULT_VERSION:-1.20.3}"

exec > >(tee /var/log/setup-base.log) 2>&1
echo "[setup-base] role=${ROLE} consul=${CONSUL_VERSION} nomad=${NOMAD_VERSION} vault=${VAULT_VERSION}"

# --- 0. KVM assertion for virtualization roles ---
case "${ROLE}" in
  orchestrator|build)
    if [ ! -e /dev/kvm ]; then
      echo "[setup-base] ERROR: /dev/kvm missing on a ${ROLE} host. Enable VT-x/AMD-V in BIOS." >&2
      exit 1
    fi
    ;;
esac

# --- 1. Let any in-flight cloud-init / unattended-upgrades settle ---
if command -v cloud-init >/dev/null 2>&1; then
  cloud-init status --wait || [ $? -eq 2 ]
fi

export DEBIAN_FRONTEND=noninteractive

# --- 2. Base packages ---
apt-get update
apt-get install -y \
  curl git ca-certificates \
  nvme-cli unzip jq net-tools qemu-utils make build-essential \
  openssh-client openssh-server nfs-common qemu-guest-agent \
  dnsutils netcat-openbsd cloud-init

# qemu-guest-agent installed + enabled (requested even on baremetal).
systemctl enable --now qemu-guest-agent || true

# --- 3. Docker ---
if ! command -v docker >/dev/null 2>&1; then
  mkdir -p /etc/docker
  cp "${SETUP_DIR}/daemon.json" /etc/docker/daemon.json
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
fi
systemctl enable docker

# --- 4. Go ---
if ! command -v go >/dev/null 2>&1; then
  snap install go --classic || apt-get install -y golang-go
fi

# --- 5. gruntwork bash-commons (required by install-*.sh) ---
if [ ! -d /opt/gruntwork/bash-commons ]; then
  mkdir -p /opt/gruntwork
  rm -rf /tmp/bash-commons
  git clone --branch v0.1.3 https://github.com/gruntwork-io/bash-commons.git /tmp/bash-commons
  cp -r /tmp/bash-commons/modules/bash-commons/src /opt/gruntwork/bash-commons
  rm -rf /tmp/bash-commons
fi

# --- 6. Consul / Nomad / Vault (guarded by binary presence) ---
command -v consul >/dev/null 2>&1 || "${SETUP_DIR}/install-consul.sh" --version "${CONSUL_VERSION}"
command -v nomad  >/dev/null 2>&1 || "${SETUP_DIR}/install-nomad.sh"  --version "${NOMAD_VERSION}"
command -v vault  >/dev/null 2>&1 || "${SETUP_DIR}/install-vault.sh"  --version "${VAULT_VERSION}"

mkdir -p /opt/nomad/plugins

# --- 7. Limits + conntrack tuning ---
cp "${SETUP_DIR}/limits.conf" /etc/security/limits.conf
grep -q 'net.netfilter.nf_conntrack_max' /etc/sysctl.conf \
  || echo 'net.netfilter.nf_conntrack_max = 2097152' >> /etc/sysctl.conf

echo "[setup-base] done."
