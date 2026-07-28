# Baremetal IaC Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `iac/provider-baremetal/`, a Terraform provider that deploys the E2B Nomad cluster onto pre-provisioned Ubuntu 24.04 servers (private IPs supplied per nodepool), configuring every host at `apply` time instead of from a Packer base image.

**Architecture:** Copy `iac/provider-proxmox/` to `iac/provider-baremetal/`, then strip every Proxmox/Packer-specific piece. Each nodepool module drops its `proxmox_virtual_environment_vm` resource and keeps only the SSH `null_resource`, now pointed at a supplied IP list. A new idempotent `setup-base.sh` (in the shared `iac/nomad-cluster-disk-image/setup/`) performs everything Packer used to bake and runs as the first bootstrap step on every node, before the role's `start-*.sh`. The `init` (S3 + secrets) and `nomad` (jobs) modules are reused verbatim.

**Tech Stack:** Terraform 1.14.x, HashiCorp Nomad/Consul/Vault, Docker, bash provisioners over SSH, `minio` + `nomad` + `null` + `random` Terraform providers.

**Spec:** `docs/superpowers/specs/2026-06-21-iac-baremetal-provider-design.md`

## Verification model (IaC adaptation of TDD)

This is infrastructure code (Terraform + bash); there is no unit-test harness, and the only true end-to-end test requires real servers (out of scope per task). The per-task verification gate is therefore:

- **Terraform files:** `terraform fmt` (parses HCL; fails on syntax/format errors).
- **Bash scripts:** `bash -n <script>` (syntax check). For templated scripts (`start-*.sh`) that contain `${...}`/`%{...}` Terraform interpolations, `bash -n` is skipped (they are not valid standalone bash) — they are exercised by `terraform fmt`/`validate` of the `templatefile()` call instead.
- **Whole-config semantic check:** `terraform init -backend=false && terraform validate` — runs only in the final task (Task 13), because intermediate states reference a half-migrated tree.

All commands run from `iac/provider-baremetal/` unless stated otherwise. The repo root is `/home/chwzr/code/e2b-infra-bm`.

## Global Constraints

- Tool versions pinned: **Consul 1.16.2, Nomad 1.6.2, Vault 1.20.3** (copied from the proxmox `variables.pkr.hcl` defaults).
- SSH user is always `root`; one private IP per server used for both SSH and Consul/Nomad advertise + retry_join.
- No bastion required (optional `ssh_bastion_*` vars retained, default empty).
- `setup-base.sh` must be idempotent (guard every install with `command -v` / path checks).
- `/dev/kvm` is required on `orchestrator` and `build` hosts only — asserted by `setup-base.sh`.
- Do **not** copy Terraform state/plan artifacts (`.terraform/`, `*.tfstate*`, `.tfplan.*`, `.terraform.lock.hcl`) into the new provider dir.
- Branch is `feat-iac-baremetal` (already created and checked out).

---

### Task 1: Scaffold `provider-baremetal` from `provider-proxmox`

**Files:**
- Create: `iac/provider-baremetal/` (recursive copy of `iac/provider-proxmox/`, source only)
- Delete (in copy): `iac/provider-baremetal/nomad-cluster-disk-image/`, `iac/provider-baremetal/scripts/setup-pve-host.sh`

- [ ] **Step 1: Copy the provider tree, excluding state/plan artifacts**

```bash
cd /home/chwzr/code/e2b-infra-bm
rsync -a \
  --exclude='.terraform/' \
  --exclude='.terraform.lock.hcl' \
  --exclude='.tfplan.*' \
  --exclude='*.tfstate' \
  --exclude='*.tfstate.*' \
  --exclude='.terraform.*.tfvars' \
  iac/provider-proxmox/ iac/provider-baremetal/
```

- [ ] **Step 2: Remove the Packer template dir and the PVE host script**

```bash
cd /home/chwzr/code/e2b-infra-bm
rm -rf iac/provider-baremetal/nomad-cluster-disk-image
rm -f  iac/provider-baremetal/scripts/setup-pve-host.sh
```

- [ ] **Step 3: Verify the expected tree exists (init/, nomad/, nomad-cluster/, modules/, scripts/ empty-or-gone)**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm
find iac/provider-baremetal -maxdepth 2 -type d | sort
ls iac/provider-baremetal/nomad-cluster-disk-image 2>/dev/null && echo "STILL PRESENT (BAD)" || echo "packer dir removed (good)"
```
Expected: directories `init`, `nomad`, `nomad-cluster`, `modules/nodepool-*` present; "packer dir removed (good)".

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal
git commit -m "feat(iac/baremetal): scaffold provider from proxmox (pre-strip)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 2: Add the shared `setup-base.sh`

**Files:**
- Create: `iac/nomad-cluster-disk-image/setup/setup-base.sh`

**Interfaces:**
- Produces: a script invoked over SSH as `[CONSUL_VERSION=… NOMAD_VERSION=… VAULT_VERSION=…] /tmp/setup/setup-base.sh <role>` where `<role>` ∈ `control-server|api|ingress|orchestrator|build|clickhouse`. Reads sibling files `daemon.json`, `limits.conf`, `install-consul.sh`, `install-nomad.sh`, `install-vault.sh` from its own directory. Every nodepool module's bootstrap (Tasks 5–10) calls it.

- [ ] **Step 1: Write the script**

Create `iac/nomad-cluster-disk-image/setup/setup-base.sh`:

```bash
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
```

- [ ] **Step 2: Verify bash syntax**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm
bash -n iac/nomad-cluster-disk-image/setup/setup-base.sh && echo OK
```
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/nomad-cluster-disk-image/setup/setup-base.sh
git commit -m "feat(iac/baremetal): add idempotent setup-base.sh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 3: Rewrite the root module (`variables.tf`, `main.tf`, `outputs.tf`)

**Files:**
- Modify: `iac/provider-baremetal/variables.tf` (full replace)
- Modify: `iac/provider-baremetal/main.tf` (full replace)
- Modify: `iac/provider-baremetal/outputs.tf` (full replace)

**Interfaces:**
- Produces (to Task 4): `module "cluster"` passes per-pool `*_ips` lists, `consul_version`/`nomad_version`/`vault_version`, `ssh_private_key`, `ssh_bastion_*`, the S3 + fc bucket names, and the cluster secrets — into `./nomad-cluster`.

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `iac/provider-baremetal/variables.tf` with:

```hcl
variable "domain_name" {
  type        = string
  description = "Domain name used for Traefik Host routing and service URLs. DNS records are created manually. Point *.<domain_name> at the ingress server (or a load balancer in front of it)."
}

variable "prefix" {
  type        = string
  description = "Name prefix for all resources"
}

variable "environment" {
  type = string
}

variable "datacenter" {
  type        = string
  description = "Consul/Nomad datacenter name"
  default     = "dc1"
}

// ---
// Pre-provisioned servers (private IPs per nodepool)
// ---
// Each server is an existing Ubuntu 24.04 host with the deploy SSH key on root.
// The IP given here is the private address used for BOTH ssh and Consul/Nomad
// advertise + retry_join. The deploy host must be able to reach these IPs.

variable "control_server_ips" {
  type        = list(string)
  description = "Private IPs of the Nomad/Consul control servers."
}

variable "api_ips" {
  type        = list(string)
  description = "Private IPs of the API nodepool servers."
}

variable "ingress_ips" {
  type        = list(string)
  description = "Private IPs of the ingress (Traefik) servers. Element 0 is the primary."
}

variable "orchestrator_ips" {
  type        = list(string)
  description = "Private IPs of the orchestrator servers (require /dev/kvm)."
}

variable "build_ips" {
  type        = list(string)
  description = "Private IPs of the build (template-manager) servers (require /dev/kvm)."
}

variable "clickhouse_ips" {
  type        = list(string)
  description = "Private IPs of the ClickHouse servers."
}

// ---
// Tool versions baked at deploy time by setup-base.sh
// ---

variable "consul_version" {
  type    = string
  default = "1.16.2"
}

variable "nomad_version" {
  type    = string
  default = "1.6.2"
}

variable "vault_version" {
  type    = string
  default = "1.20.3"
}

// ---
// SSH access
// ---

variable "ssh_private_key" {
  type        = string
  sensitive   = true
  description = "SSH private key (PEM content OR a path to a PEM file) Terraform uses to bootstrap servers over SSH as root."
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Optional SSH bastion/jump host. Leave empty to connect directly (deploy host has network access to the private IPs)."
}

variable "ssh_bastion_user" {
  type        = string
  default     = "root"
  description = "SSH user for the bastion host (only used when ssh_bastion_host is set)."
}

variable "nomad_address" {
  type        = string
  default     = ""
  description = "Override for the Nomad Terraform provider address. Leave empty to use the Traefik-routed domain URL. On first bootstrap, set to a direct Nomad listener (e.g. http://localhost:4646 through an SSH tunnel) because Traefik is itself a Nomad job and not yet running."
}

variable "acme_email" {
  type        = string
  default     = ""
  description = "Contact email for Let's Encrypt. Empty disables TLS on the ingress."
}

variable "ingress_image" {
  type        = string
  default     = "traefik:v3.5"
  description = "Docker image for the ingress Traefik task."
}

variable "hcloud_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Hetzner Cloud API token with DNS zone write access. When set, Traefik uses DNS-01 to issue a wildcard cert for *.DOMAIN. When empty, falls back to HTTP-01."
}

variable "hcloud_zone" {
  type        = string
  default     = ""
  description = "Hetzner Cloud DNS zone name (e.g. example.dev)."
}

variable "hcloud_zone_id" {
  type        = string
  default     = ""
  description = "Hetzner Cloud DNS zone id (numeric)."
}

variable "client_proxy_count" {
  type    = number
  default = 1
}

// ---
// Redis
// ---

variable "redis_managed" {
  type    = bool
  default = false
}

// ---
// S3-compatible Object Storage
// ---

variable "s3_endpoint" {
  type        = string
  description = "S3-compatible endpoint (e.g. fsn1.your-objectstorage.com)"
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type    = string
  default = "fsn1"
}

// ---
// Container Registry
// ---

variable "container_registry_url" {
  type        = string
  description = "URL of the Docker registry that hosts service images."
  default     = ""
}

// ---
// Application Secrets
// ---

variable "postgres_connection_string" {
  type      = string
  default   = " "
  sensitive = true
}

variable "supabase_jwt_secrets" {
  type      = string
  default   = " "
  sensitive = true
}

variable "launch_darkly_api_key" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_otlp_url" {
  type    = string
  default = " "
}

variable "grafana_otel_collector_token" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_username" {
  type    = string
  default = " "
}

variable "grafana_logs_user" {
  type    = string
  default = " "
}

variable "grafana_logs_url" {
  type    = string
  default = " "
}

variable "grafana_logs_collector_api_token" {
  type      = string
  default   = " "
  sensitive = true
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `iac/provider-baremetal/main.tf` with:

```hcl
terraform {
  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.1.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.3"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  required_version = ">= 1.0"

  backend "s3" {
    key                         = "terraform/orchestration/state"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "minio" {
  minio_server   = var.s3_endpoint
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_ssl      = true
  minio_region   = var.s3_region
}

provider "nomad" {
  # Defaults to the Traefik-routed domain URL. Traefik is itself a Nomad job,
  # so on first-time bootstrap this address is unreachable — override with
  # NOMAD_ADDR (via `nomad_address` tfvar) pointing at a direct Nomad listener,
  # typically an SSH-tunneled control server (e.g. http://localhost:4646).
  address      = var.nomad_address != "" ? var.nomad_address : "https://nomad.${var.domain_name}"
  secret_id    = module.init.cluster.nomad_acl_token
  consul_token = module.init.cluster.consul_acl_token
}

locals {
  redis_port   = 6379
  ingress_port = 8080
  nomad_port   = 4646

  api_pool_name        = "api"
  ingress_pool_name    = "ingress"
  orchestrator_pool    = "default"
  build_pool_name      = "build"
  clickhouse_pool_name = "clickhouse"

  redis_url         = var.redis_managed ? "" : "redis.service.consul:${local.redis_port}"
  redis_cluster_url = ""

  # ssh_private_key may be supplied as PEM content OR a path to a PEM file.
  # Paths are preferred because Make's -include can't parse multi-line values.
  ssh_private_key = fileexists(var.ssh_private_key) ? file(var.ssh_private_key) : var.ssh_private_key
}

module "init" {
  source = "./init"

  prefix        = var.prefix
  bucket_prefix = "${var.prefix}${var.s3_region}-"

  postgres_connection_string       = var.postgres_connection_string
  supabase_jwt_secrets             = var.supabase_jwt_secrets
  launch_darkly_api_key            = var.launch_darkly_api_key
  grafana_otlp_url                 = var.grafana_otlp_url
  grafana_otel_collector_token     = var.grafana_otel_collector_token
  grafana_username                 = var.grafana_username
  grafana_logs_user                = var.grafana_logs_user
  grafana_logs_url                 = var.grafana_logs_url
  grafana_logs_collector_api_token = var.grafana_logs_collector_api_token
}

module "cluster" {
  source = "./nomad-cluster"

  prefix     = var.prefix
  datacenter = var.datacenter

  control_server_ips = var.control_server_ips
  api_ips            = var.api_ips
  ingress_ips        = var.ingress_ips
  orchestrator_ips   = var.orchestrator_ips
  build_ips          = var.build_ips
  clickhouse_ips     = var.clickhouse_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  ssh_private_key  = local.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  api_node_pool_name          = local.api_pool_name
  ingress_node_pool           = local.ingress_pool_name
  orchestrator_node_pool_name = local.orchestrator_pool
  build_node_pool_name        = local.build_pool_name

  clickhouse_node_pool_name        = local.clickhouse_pool_name
  clickhouse_job_constraint_prefix = local.clickhouse_pool_name

  nomad_acl_token              = module.init.cluster.nomad_acl_token
  consul_acl_token             = module.init.cluster.consul_acl_token
  consul_gossip_encryption_key = module.init.cluster.consul_gossip_encryption_key
  consul_dns_request_token     = module.init.cluster.consul_dns_request_token

  container_registry_url = var.container_registry_url

  s3_endpoint                 = var.s3_endpoint
  s3_access_key               = var.s3_access_key
  s3_secret_key               = var.s3_secret_key
  s3_region                   = var.s3_region
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = module.init.fc_kernels_bucket_name
  fc_versions_bucket_name     = module.init.fc_versions_bucket_name
}

module "nomad" {
  source = "./nomad"

  prefix      = var.prefix
  domain_name = var.domain_name
  environment = var.environment

  container_registry_url = var.container_registry_url
  s3_endpoint            = var.s3_endpoint
  s3_region              = var.s3_region
  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  acme_email             = var.acme_email
  ingress_image          = var.ingress_image
  hcloud_token           = var.hcloud_token
  hcloud_zone            = var.hcloud_zone
  hcloud_zone_id         = var.hcloud_zone_id

  nomad_acl_token  = module.init.cluster.nomad_acl_token
  consul_acl_token = module.init.cluster.consul_acl_token
  nomad_address    = var.nomad_address

  api_node_pool    = local.api_pool_name
  api_cluster_size = length(var.api_ips)

  ingress_node_pool = local.ingress_pool_name
  ingress_port      = local.ingress_port
  ingress_count     = 1

  client_proxy_count = var.client_proxy_count

  redis_managed = var.redis_managed
  redis_port    = local.redis_port
  redis_url     = local.redis_url

  clickhouse_cluster_size        = length(var.clickhouse_ips)
  clickhouse_username            = module.init.clickhouse.username
  clickhouse_password            = module.init.clickhouse.password
  clickhouse_server_secret       = module.init.clickhouse.server_secret
  clickhouse_node_pool           = local.clickhouse_pool_name
  clickhouse_jobs_prefix         = local.clickhouse_pool_name
  clickhouse_backups_bucket_name = module.init.clickhouse_backups_bucket_name

  grafana_otel_collector_token = module.init.grafana.otel_collector_token
  grafana_otlp_url             = module.init.grafana.otlp_url
  grafana_username             = module.init.grafana.username
  grafana_logs_user            = module.init.grafana.logs_user
  grafana_logs_endpoint        = module.init.grafana.logs_url
  grafana_logs_api_key         = module.init.grafana.logs_collector_api_token

  postgres_connection_string     = module.init.postgres_connection_string
  supabase_jwt_secrets           = module.init.supabase_jwt_secrets
  admin_token                    = module.init.admin_token
  sandbox_access_token_hash_seed = module.init.sandbox_access_token_hash_seed
  launch_darkly_api_key          = module.init.launch_darkly_api_key

  loki_bucket_name = module.init.loki_bucket_name

  build_node_pool             = local.build_pool_name
  build_cluster_size          = length(var.build_ips)
  api_secret                  = module.init.api_secret
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  template_bucket_name        = module.init.fc_template_bucket_name
  build_cache_bucket_name     = module.init.fc_template_build_cache_bucket_name

  orchestrator_node_pool = local.orchestrator_pool
}
```

- [ ] **Step 3: Replace `outputs.tf`**

Overwrite `iac/provider-baremetal/outputs.tf` with:

```hcl
output "ingress_private_ip" {
  value       = module.cluster.ingress_private_ip
  description = "Private IP of the Traefik ingress server. Point public 80/443 at this host (or a load balancer in front of it)."
}

output "control_server_private_ips" {
  value       = module.cluster.control_server_private_ips
  description = "Private IPs of the Nomad/Consul control servers (useful for retry_join debugging)."
}

output "domain_name" {
  value = var.domain_name
}
```

- [ ] **Step 4: Format-check the root files**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt main.tf variables.tf outputs.tf
```
Expected: no error (prints any reformatted filenames or nothing).

- [ ] **Step 5: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/main.tf iac/provider-baremetal/variables.tf iac/provider-baremetal/outputs.tf
git commit -m "feat(iac/baremetal): root module wiring (IP lists, no proxmox provider)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 4: Rewrite the `nomad-cluster` module (`variables.tf`, `main.tf`)

**Files:**
- Modify: `iac/provider-baremetal/nomad-cluster/variables.tf` (full replace)
- Modify: `iac/provider-baremetal/nomad-cluster/main.tf` (full replace)
- Keep unchanged: `iac/provider-baremetal/nomad-cluster/outputs.tf`

**Interfaces:**
- Consumes (from Task 3): `*_ips`, `consul_version`/`nomad_version`/`vault_version`, `ssh_private_key`, `ssh_bastion_*`, S3 + fc buckets, cluster secrets, node-pool names.
- Produces (to Tasks 5–10): each nodepool module receives `private_ips`, version vars, ssh vars, consul secrets, and (where relevant) `consul_retry_join_ips = module.control_server.private_ips`, S3 + fc buckets, `node_pool_name`, `job_constraint_prefix`.

- [ ] **Step 1: Replace `nomad-cluster/variables.tf`**

Overwrite with:

```hcl
variable "prefix" {
  type = string
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

// ---
// Pre-provisioned server IPs per nodepool
// ---

variable "control_server_ips" {
  type = list(string)
}

variable "api_ips" {
  type = list(string)
}

variable "ingress_ips" {
  type = list(string)
}

variable "orchestrator_ips" {
  type = list(string)
}

variable "build_ips" {
  type = list(string)
}

variable "clickhouse_ips" {
  type = list(string)
}

// ---
// Tool versions (passed to setup-base.sh)
// ---

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

// ---
// SSH
// ---

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

// ---
// Node pool names
// ---

variable "api_node_pool_name" {
  type = string
}

variable "ingress_node_pool" {
  type = string
}

variable "orchestrator_node_pool_name" {
  type = string
}

variable "build_node_pool_name" {
  type = string
}

variable "clickhouse_node_pool_name" {
  type = string
}

variable "clickhouse_job_constraint_prefix" {
  type = string
}

// ---
// S3 + bucket names for orchestrator/build boot (envd, kernels, firecracker)
// ---

variable "s3_endpoint" {
  type = string
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type = string
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "fc_kernels_bucket_name" {
  type = string
}

variable "fc_versions_bucket_name" {
  type = string
}

// ---
// Cluster secrets
// ---

variable "nomad_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}
```

- [ ] **Step 2: Replace `nomad-cluster/main.tf`**

Overwrite with:

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

module "control_server" {
  source = "../modules/nodepool-control-server"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.control_server_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  nomad_acl_token              = var.nomad_acl_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
}

module "api" {
  source = "../modules/nodepool-api"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.api_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.api_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "ingress" {
  source = "../modules/nodepool-ingress"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.ingress_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.ingress_node_pool

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "orchestrator" {
  source = "../modules/nodepool-orchestrator"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.orchestrator_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.orchestrator_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  s3_endpoint                 = var.s3_endpoint
  s3_access_key               = var.s3_access_key
  s3_secret_key               = var.s3_secret_key
  s3_region                   = var.s3_region
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name

  depends_on = [module.control_server]
}

module "build" {
  source = "../modules/nodepool-build"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.build_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.build_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  s3_endpoint                 = var.s3_endpoint
  s3_access_key               = var.s3_access_key
  s3_secret_key               = var.s3_secret_key
  s3_region                   = var.s3_region
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name

  depends_on = [module.control_server]
}

module "clickhouse" {
  source = "../modules/nodepool-clickhouse"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.clickhouse_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name        = var.clickhouse_node_pool_name
  job_constraint_prefix = var.clickhouse_job_constraint_prefix

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}
```

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt nomad-cluster/main.tf nomad-cluster/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/nomad-cluster/main.tf iac/provider-baremetal/nomad-cluster/variables.tf
git commit -m "feat(iac/baremetal): nomad-cluster module wiring over IP lists

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 5: Rewrite `nodepool-control-server` module

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-control-server/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-control-server/variables.tf` (full replace)
- Keep unchanged: `outputs.tf`, `scripts/start-server.sh`

**Interfaces:**
- Consumes: `private_ips`, version vars, ssh vars, `nomad_acl_token`, consul secrets.
- Produces: `output "private_ips"` (= `var.private_ips`), consumed as `consul_retry_join_ips` by every other pool.

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-control-server/variables.tf` with:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "nomad_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-control-server/main.tf` with:

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir = "${path.module}/../../../nomad-cluster-disk-image/setup"
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-server.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  # 1. Upload + run the shared base setup (idempotent).
  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh control-server",
    ]
  }

  # 2. Upload + run the role start script.
  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-server.sh", {
      NUM_SERVERS                  = length(var.private_ips)
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.private_ips)
      NOMAD_TOKEN                  = var.nomad_acl_token
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-server.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-server.sh",
      "/tmp/start-server.sh",
    ]
  }
}
```

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-control-server/main.tf modules/nodepool-control-server/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-control-server
git commit -m "feat(iac/baremetal): control-server nodepool over supplied IPs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 6: Rewrite `nodepool-api` module

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-api/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-api/variables.tf` (full replace)
- Keep unchanged: `outputs.tf`, `scripts/start-api.sh`

**Interfaces:**
- Consumes: `private_ips`, version vars, ssh vars, `node_pool_name`, `consul_retry_join_ips`, consul secrets, `container_registry_url`.
- Produces: `output "private_ips"`.

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-api/variables.tf` with:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "api"
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-api/main.tf` with:

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir   = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ips = var.private_ips
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-api.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh api",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-api.sh", {
      NODE_POOL                    = var.node_pool_name
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-api.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-api.sh",
      "/tmp/start-api.sh",
    ]
  }
}
```

> Note: `locals.private_ips` is kept so the unchanged `outputs.tf` (`value = local.private_ips`) still resolves.

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-api/main.tf modules/nodepool-api/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-api
git commit -m "feat(iac/baremetal): api nodepool over supplied IPs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 7: Rewrite `nodepool-ingress` module (single node)

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-ingress/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-ingress/variables.tf` (full replace)
- Keep unchanged: `outputs.tf` (`value = local.private_ip`), `scripts/start-ingress.sh`

**Interfaces:**
- Consumes: `private_ips` (uses element 0), version vars, ssh vars, `node_pool_name`, `consul_retry_join_ips`, consul secrets, `container_registry_url`.
- Produces: `output "private_ip"` (= `local.private_ip`, singular).

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-ingress/variables.tf` with the same content as Task 6 Step 1 (`nodepool-api/variables.tf`), except change the `node_pool_name` default:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "ingress"
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-ingress/main.tf` with (single-node — no `count`, uses `var.private_ips[0]`):

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir  = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ip = var.private_ips[0]
}

resource "null_resource" "bootstrap" {
  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-ingress.sh")
    host        = local.private_ip
  }

  connection {
    type        = "ssh"
    host        = local.private_ip
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh ingress",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-ingress.sh", {
      NODE_POOL                    = var.node_pool_name
      PRIVATE_IP                   = local.private_ip
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-ingress.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-ingress.sh",
      "/tmp/start-ingress.sh",
    ]
  }
}
```

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-ingress/main.tf modules/nodepool-ingress/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-ingress
git commit -m "feat(iac/baremetal): ingress nodepool over supplied IP

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 8: Rewrite `nodepool-orchestrator` module

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-orchestrator/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-orchestrator/variables.tf` (full replace)
- Keep unchanged: `outputs.tf`, `scripts/start-orchestrator.sh`

**Interfaces:**
- Consumes: `private_ips`, version vars, ssh vars, `node_pool_name`, `node_labels`, `base_hugepages_percentage`, `consul_retry_join_ips`, consul secrets, `container_registry_url`, S3 + fc buckets.
- Produces: `output "private_ips"`. setup-base role arg = `orchestrator` (asserts `/dev/kvm`).

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-orchestrator/variables.tf` with:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "default"
}

variable "node_labels" {
  type    = list(string)
  default = []
}

variable "base_hugepages_percentage" {
  type    = number
  default = 80
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}

variable "s3_endpoint" {
  type = string
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type = string
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "fc_kernels_bucket_name" {
  type = string
}

variable "fc_versions_bucket_name" {
  type = string
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-orchestrator/main.tf` with:

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir   = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ips = var.private_ips
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-orchestrator.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh orchestrator",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-orchestrator.sh", {
      NODE_POOL                    = var.node_pool_name
      NODE_LABELS                  = join(",", var.node_labels)
      BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter

      S3_ENDPOINT                 = var.s3_endpoint
      S3_ACCESS_KEY               = var.s3_access_key
      S3_SECRET_KEY               = var.s3_secret_key
      S3_REGION                   = var.s3_region
      FC_ENV_PIPELINE_BUCKET_NAME = var.fc_env_pipeline_bucket_name
      FC_KERNELS_BUCKET_NAME      = var.fc_kernels_bucket_name
      FC_VERSIONS_BUCKET_NAME     = var.fc_versions_bucket_name
    })
    destination = "/tmp/start-orchestrator.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-orchestrator.sh",
      "/tmp/start-orchestrator.sh",
    ]
  }
}
```

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-orchestrator/main.tf modules/nodepool-orchestrator/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-orchestrator
git commit -m "feat(iac/baremetal): orchestrator nodepool over supplied IPs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 9: Rewrite `nodepool-build` module

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-build/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-build/variables.tf` (full replace)
- Keep unchanged: `outputs.tf`, `scripts/start-build.sh`

**Interfaces:**
- Same variable surface as orchestrator (Task 8). setup-base role arg = `build` (asserts `/dev/kvm`).

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-build/variables.tf` with the **identical content** from Task 8 Step 1 (`nodepool-orchestrator/variables.tf`) — the variable surface is the same:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "build"
}

variable "node_labels" {
  type    = list(string)
  default = []
}

variable "base_hugepages_percentage" {
  type    = number
  default = 80
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}

variable "s3_endpoint" {
  type = string
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type = string
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "fc_kernels_bucket_name" {
  type = string
}

variable "fc_versions_bucket_name" {
  type = string
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-build/main.tf` with (note: `start-build.sh`, role arg `build`):

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir   = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ips = var.private_ips
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-build.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh build",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-build.sh", {
      NODE_POOL                    = var.node_pool_name
      NODE_LABELS                  = join(",", var.node_labels)
      BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter

      S3_ENDPOINT                 = var.s3_endpoint
      S3_ACCESS_KEY               = var.s3_access_key
      S3_SECRET_KEY               = var.s3_secret_key
      S3_REGION                   = var.s3_region
      FC_ENV_PIPELINE_BUCKET_NAME = var.fc_env_pipeline_bucket_name
      FC_KERNELS_BUCKET_NAME      = var.fc_kernels_bucket_name
      FC_VERSIONS_BUCKET_NAME     = var.fc_versions_bucket_name
    })
    destination = "/tmp/start-build.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-build.sh",
      "/tmp/start-build.sh",
    ]
  }
}
```

- [ ] **Step 3: Format-check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-build/main.tf modules/nodepool-build/variables.tf
```
Expected: no error.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-build
git commit -m "feat(iac/baremetal): build nodepool over supplied IPs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 10: Rewrite `nodepool-clickhouse` module + drop the second-disk mount

**Files:**
- Modify: `iac/provider-baremetal/modules/nodepool-clickhouse/main.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-clickhouse/variables.tf` (full replace)
- Modify: `iac/provider-baremetal/modules/nodepool-clickhouse/scripts/start-clickhouse.sh` (replace the data-volume block)
- Keep unchanged: `outputs.tf`

**Interfaces:**
- Consumes: `private_ips`, version vars, ssh vars, `node_pool_name`, `job_constraint_prefix`, `consul_retry_join_ips`, consul secrets, `container_registry_url`.
- Produces: `output "private_ips"`. setup-base role arg = `clickhouse` (no KVM assertion).
- Behavior change: on baremetal there is no second virtio disk, so ClickHouse data lives in a plain directory `/clickhouse/data` on the root filesystem instead of a formatted/mounted `/dev/sdb`.

- [ ] **Step 1: Replace `variables.tf`**

Overwrite `modules/nodepool-clickhouse/variables.tf` with:

```hcl
variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

variable "node_pool_name" {
  type    = string
  default = "clickhouse"
}

variable "job_constraint_prefix" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}
```

- [ ] **Step 2: Replace `main.tf`**

Overwrite `modules/nodepool-clickhouse/main.tf` with (keeps the `JOB_CONSTRAINT` per-index templatefile param):

```hcl
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir   = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ips = var.private_ips
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-clickhouse.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh clickhouse",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-clickhouse.sh", {
      NODE_POOL = var.node_pool_name
      # Job HCL uses 1-based index for constraint matching (i+1).
      JOB_CONSTRAINT               = "${var.job_constraint_prefix}-${count.index + 1}"
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-clickhouse.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-clickhouse.sh",
      "/tmp/start-clickhouse.sh",
    ]
  }
}
```

- [ ] **Step 3: Replace the data-volume block in `start-clickhouse.sh`**

In `modules/nodepool-clickhouse/scripts/start-clickhouse.sh`, replace the entire block from the comment `# Mount data volume ...` through the `mkdir -p $MOUNT_POINT/data` line (the original lines reproduced below) with the baremetal version.

Find and replace this exact block:

```bash
# ---
# Mount data volume (second virtio-scsi disk => /dev/sdb)
# ---
DATA_DEVICE="/dev/sdb"
MOUNT_POINT="/clickhouse"
mkdir -p $MOUNT_POINT

for i in $(seq 1 60); do
  if [ -e "$DATA_DEVICE" ]; then
    break
  fi
  sleep 2
done

if [ ! -e "$DATA_DEVICE" ]; then
  echo "ERROR: Data disk $DATA_DEVICE not found after 120s"
  exit 1
fi

if ! blkid "$DATA_DEVICE" | grep -q xfs; then
  echo "Formatting $DATA_DEVICE as XFS..."
  mkfs.xfs "$DATA_DEVICE"
fi

mount -o noatime "$DATA_DEVICE" "$MOUNT_POINT"
DEVICE_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
echo "UUID=$DEVICE_UUID $MOUNT_POINT xfs noatime 0 2" >> /etc/fstab

mkdir -p $MOUNT_POINT/data
```

With:

```bash
# ---
# Data directory
# ---
# On baremetal there is no dedicated second disk. ClickHouse data lives in a
# plain directory on the root filesystem. If you have a separate data volume,
# mount it at /clickhouse before running terraform apply.
MOUNT_POINT="/clickhouse"
mkdir -p $MOUNT_POINT/data
```

- [ ] **Step 4: Format-check + sanity-check the script edit**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt modules/nodepool-clickhouse/main.tf modules/nodepool-clickhouse/variables.tf
grep -n "/dev/sdb" modules/nodepool-clickhouse/scripts/start-clickhouse.sh && echo "STILL REFERENCES /dev/sdb (BAD)" || echo "data-disk mount removed (good)"
```
Expected: `terraform fmt` no error; "data-disk mount removed (good)".

- [ ] **Step 5: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/modules/nodepool-clickhouse
git commit -m "feat(iac/baremetal): clickhouse nodepool over supplied IPs (root-fs data dir)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 11: Rewrite the `Makefile` (drop Proxmox/PVE, keep scalar tfvars)

**Files:**
- Modify: `iac/provider-baremetal/Makefile`

**Interfaces:**
- IP **lists** are supplied via `.terraform.<env>.tfvars` (already passed to `plan` via `TF_VAR_FILE_ARG`); scalars stay env-derived `tfvar`s. The `init`/`switch`/`plan`/`apply`/`destroy` targets keep working as in proxmox.

- [ ] **Step 1: Edit the `tf_vars` block — remove Proxmox/PVE/VM lines**

In `iac/provider-baremetal/Makefile`, delete these lines from the `tf_vars := …` block (lines that call `tfvar` for Proxmox/PVE/VM-sizing settings):

```make
	$(call tfvar, PROXMOX_API_URL) \
	$(call tfvar, PROXMOX_API_TOKEN_ID) \
	$(call tfvar, PROXMOX_API_TOKEN_SECRET) \
	$(call tfvar, PROXMOX_TLS_INSECURE) \
	$(call tfvar, PVE_NODE) \
	$(call tfvar, PVE_STORAGE_POOL) \
	$(call tfvar, BASE_TEMPLATE) \
	$(call tfvar, BASE_TEMPLATE_VM_ID) \
	$(call tfvar, BRIDGE) \
	$(call tfvar, SUBNET_CIDR) \
	$(call tfvar, GATEWAY_IP) \
```

Also delete the VM-sizing and cluster-size lines (no longer variables):

```make
	$(call tfvar, CONTROL_SERVER_CLUSTER_SIZE) \
	$(call tfvar, CONTROL_SERVER_CPU_CORES) \
	$(call tfvar, CONTROL_SERVER_MEMORY_MB) \
	$(call tfvar, CONTROL_SERVER_DISK_SIZE_GB) \
	$(call tfvar, API_CLUSTER_SIZE) \
	$(call tfvar, API_CPU_CORES) \
	$(call tfvar, API_MEMORY_MB) \
	$(call tfvar, API_DISK_SIZE_GB) \
	$(call tfvar, INGRESS_CPU_CORES) \
	$(call tfvar, INGRESS_MEMORY_MB) \
	$(call tfvar, INGRESS_DISK_SIZE_GB) \
	$(call tfvar, ORCHESTRATOR_CLUSTER_SIZE) \
	$(call tfvar, ORCHESTRATOR_CPU_CORES) \
	$(call tfvar, ORCHESTRATOR_MEMORY_MB) \
	$(call tfvar, ORCHESTRATOR_DISK_SIZE_GB) \
	$(call tfvar, BUILD_CLUSTER_SIZE) \
	$(call tfvar, BUILD_CPU_CORES) \
	$(call tfvar, BUILD_MEMORY_MB) \
	$(call tfvar, BUILD_DISK_SIZE_GB) \
	$(call tfvar, CLICKHOUSE_CLUSTER_SIZE) \
	$(call tfvar, CLICKHOUSE_CPU_CORES) \
	$(call tfvar, CLICKHOUSE_MEMORY_MB) \
	$(call tfvar, CLICKHOUSE_DISK_SIZE_GB) \
	$(call tfvar, CLICKHOUSE_DATA_VOLUME_SIZE_GB) \
```

- [ ] **Step 2: Add the version tfvars after the `S3_REGION` line**

In the `tf_vars := …` block, immediately after the `$(call tfvar, S3_REGION) \` line, add:

```make
	$(call tfvar, CONSUL_VERSION) \
	$(call tfvar, NOMAD_VERSION) \
	$(call tfvar, VAULT_VERSION) \
```

The remaining tfvars to keep (do not delete): `PREFIX`, `DOMAIN_NAME`, `CONTAINER_REGISTRY_URL`, `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_REGION`, `SSH_PRIVATE_KEY`, `SSH_BASTION_HOST`, `SSH_BASTION_USER`, `NOMAD_ADDRESS`, `ACME_EMAIL`, `INGRESS_IMAGE`, `HCLOUD_TOKEN`, `HCLOUD_ZONE`, `HCLOUD_ZONE_ID`, `REDIS_MANAGED`, `POSTGRES_CONNECTION_STRING`, `SUPABASE_JWT_SECRETS`, `LAUNCH_DARKLY_API_KEY`, `GRAFANA_*`. (Note: `SSH_PUBLIC_KEY` is removed.)

- [ ] **Step 3: Replace the `setup-pve-host` target with the `provider-login` note**

Delete the entire `setup-pve-host` target:

```make
.PHONY: setup-pve-host
setup-pve-host:
	@test -n "$(PROXMOX_API_URL)" || { echo "PROXMOX_API_URL not set (check your .env)"; exit 1; }
	@ host=$$(echo "$(PROXMOX_API_URL)" | sed -E 's|^https?://([^:/]+).*|\1|'); \
	  ssh_target="$${PVE_SSH_USER:-root}@$${PVE_SSH_HOST:-$$host}"; \
	  echo "==> Copying setup-pve-host.sh to $$ssh_target"; \
	  scp scripts/setup-pve-host.sh "$$ssh_target:/tmp/setup-pve-host.sh"; \
	  echo "==> Running setup-pve-host.sh on $$ssh_target"; \
	  ssh "$$ssh_target" "BRIDGE='$(BRIDGE)' SUBNET_CIDR='$(SUBNET_CIDR)' GATEWAY_IP='$(GATEWAY_IP)' bash /tmp/setup-pve-host.sh"
```

And replace the body of the existing `provider-login` target so it reads:

```make
.PHONY: provider-login
provider-login:
	@echo "No provider login required for baremetal (servers pre-provisioned; SSH key auth)."
```

- [ ] **Step 4: Verify the Makefile parses and references no proxmox**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
grep -niE 'proxmox|pve|setup-pve-host|base_template|subnet_cidr|gateway_ip|\bbridge\b' Makefile && echo "RESIDUAL PROXMOX REFS (BAD)" || echo "no proxmox refs (good)"
make -n provider-login
```
Expected: "no proxmox refs (good)"; `make -n provider-login` prints the echo command without error.

- [ ] **Step 5: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/Makefile
git commit -m "feat(iac/baremetal): Makefile without proxmox/pve, version tfvars

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 12: Self-host docs + example tfvars

**Files:**
- Create: `iac/provider-baremetal/self-host-baremetal.md`
- Create: `iac/provider-baremetal/.terraform.example.tfvars`

- [ ] **Step 1: Write the example tfvars**

Create `iac/provider-baremetal/.terraform.example.tfvars`:

```hcl
# Per-nodepool private IPs of your pre-provisioned Ubuntu 24.04 servers.
# Each server must have the deploy SSH public key on root and be reachable
# from the deploy host. orchestrator + build hosts must expose /dev/kvm.
control_server_ips = ["10.0.0.10", "10.0.0.11", "10.0.0.12"]
api_ips            = ["10.0.0.20"]
ingress_ips        = ["10.0.0.30"]
orchestrator_ips   = ["10.0.0.40"]
build_ips          = ["10.0.0.50"]
clickhouse_ips     = ["10.0.0.60"]

# Optional: override pinned tool versions (defaults shown).
# consul_version = "1.16.2"
# nomad_version  = "1.6.2"
# vault_version  = "1.20.3"
```

- [ ] **Step 2: Write the self-host guide**

Create `iac/provider-baremetal/self-host-baremetal.md`:

````markdown
# Self-hosting E2B on baremetal

This provider deploys the E2B Nomad cluster onto servers you have already
provisioned. There is no Packer image and no VM creation — every host is
configured over SSH at `terraform apply` time.

## Prerequisites

- N servers running a clean **Ubuntu 24.04**, each with:
  - the deploy **SSH public key on `root`**,
  - a **private IP** reachable from the host running Terraform,
  - outbound internet (to pull Docker, Go, apt, and HashiCorp binaries).
- **Orchestrator and build** hosts must have hardware virtualization enabled
  (`/dev/kvm` present) — `setup-base.sh` aborts otherwise.
- An S3-compatible object store (endpoint + access/secret keys).
- Terraform >= 1.0, `make`.

## Server-to-role mapping

Assign each server's private IP to exactly one nodepool via the `*_ips` lists.
Recommended minimum: 3 control servers (Consul/Nomad quorum), 1 each of
api/ingress/orchestrator/build/clickhouse. See `.terraform.example.tfvars`.

## Configure

1. Create `.env.<env>` from the repo `.env.template` (S3 creds, domain,
   registry, SSH key path, secrets) and `make switch-env ENV=<env>`.
2. Copy `.terraform.example.tfvars` to `.terraform.<env>.tfvars` and fill in
   your per-pool private IPs.
3. `SSH_PRIVATE_KEY` may be a path to a PEM file (preferred) or inline PEM.

## Deploy

```bash
cd iac/provider-baremetal
make init                 # creates S3 buckets + secrets (module.init)
make plan ENV=<env>
make apply ENV=<env>
```

On first bootstrap Traefik (the ingress) is not yet running, so the Nomad
provider can't reach `https://nomad.<domain>`. Set `NOMAD_ADDRESS` to a direct
listener through an SSH tunnel to a control server, e.g.:

```bash
ssh -L 4646:localhost:4646 root@<control_server_ip>
# then, in another shell:
NOMAD_ADDRESS=http://localhost:4646 make apply ENV=<env>
```

## What runs on each host

`setup-base.sh` (shared, idempotent) installs Docker, Go, gruntwork
bash-commons, Consul/Nomad/Vault (pinned versions), qemu-guest-agent, and
limits/conntrack tuning. Then the per-role `start-<role>.sh` configures and
starts the Consul + Nomad agents (plus hugepages/NBD/firecracker downloads on
orchestrator and build). Re-running `apply` re-bootstraps a host only when its
IP, `setup-base.sh`, or its `start-<role>.sh` changes.

## Networking notes

The single private IP per server is used for both SSH and Consul/Nomad
advertise + retry_join. This provider does not manage firewalls — restrict the
cluster ports (Consul 8300/8301/8500/8600, Nomad 4646-4648) to the private
network yourself. Point public 80/443 at the ingress host (`ingress_private_ip`
output) or a load balancer in front of it.
````

- [ ] **Step 3: Verify files exist**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
ls -1 self-host-baremetal.md .terraform.example.tfvars
```
Expected: both filenames listed.

- [ ] **Step 4: Commit**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add iac/provider-baremetal/self-host-baremetal.md iac/provider-baremetal/.terraform.example.tfvars
git commit -m "docs(iac/baremetal): self-host guide + example tfvars

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1"
```

---

### Task 13: Whole-config validation

**Files:** none (validation + any `fmt` fixups).

- [ ] **Step 1: Initialize providers without the S3 backend**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform init -backend=false -input=false
```
Expected: "Terraform has been successfully initialized!"; provider plugins downloaded are `aminueza/minio`, `hashicorp/nomad`, `hashicorp/null`, `hashicorp/random` — and **no** `bpg/proxmox`.

- [ ] **Step 2: Validate the whole configuration**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform validate
```
Expected: "Success! The configuration is valid."

If validate reports an error, fix the offending file (most likely a missing/renamed variable or a `module.cluster` output name mismatch — cross-check against Task 3/Task 4), re-run, and only proceed when it passes.

- [ ] **Step 3: Recursive format check**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm/iac/provider-baremetal
terraform fmt -recursive -check
```
Expected: exit 0 with no filenames printed. If files are listed, run `terraform fmt -recursive` to fix them.

- [ ] **Step 4: Bash syntax check of non-templated scripts**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm
bash -n iac/nomad-cluster-disk-image/setup/setup-base.sh && echo "setup-base OK"
```
Expected: "setup-base OK". (The `start-*.sh` scripts contain Terraform `templatefile` interpolations and are intentionally not standalone-bash-checkable; they are covered by `terraform validate` of their `templatefile()` calls in Step 2.)

- [ ] **Step 5: Confirm no residual proxmox references in the provider tree**

Run:
```bash
cd /home/chwzr/code/e2b-infra-bm
grep -rniE 'proxmox|bpg/proxmox|pve_node|base_template_vm_id|cidrhost' iac/provider-baremetal --include='*.tf' && echo "RESIDUAL REFS (BAD)" || echo "clean (good)"
```
Expected: "clean (good)".

- [ ] **Step 6: Commit any fmt fixups (if Step 3 changed files); otherwise skip**

```bash
cd /home/chwzr/code/e2b-infra-bm
git add -A iac/provider-baremetal
git commit -m "chore(iac/baremetal): terraform fmt + validate pass" \
  -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" \
  -m "Claude-Session: https://claude.ai/code/session_01YRbzect65BsjaqBiCHwgy1" || echo "nothing to commit"
```

---

## Self-Review

**1. Spec coverage**

| Spec section | Task |
|---|---|
| New `provider-baremetal/` dir; drop Packer + setup-pve-host | Task 1 |
| `setup-base.sh` (Docker/Go/bash-commons/Consul/Nomad/Vault/qemu-guest-agent/limits, idempotent, KVM assertion) | Task 2 |
| Root `main.tf`/`variables.tf`/`outputs.tf` (IP lists, drop proxmox provider, version vars) | Task 3 |
| `nomad-cluster` wiring (retry_join = control IPs, pass versions/S3) | Task 4 |
| Per-nodepool modules drop VM resource, add `private_ips`, two-phase bootstrap | Tasks 5–10 |
| Ingress single-node `private_ip` | Task 7 |
| Orchestrator/build KVM role arg | Tasks 8, 9 |
| ClickHouse data dir on root fs (no second disk) | Task 10 |
| Makefile (drop proxmox/pve, version tfvars, provider-login note) | Task 11 |
| Docs + example tfvars | Task 12 |
| `init`/`nomad` modules reused verbatim | Tasks 1 (copied), untouched thereafter |
| Whole-config validate | Task 13 |

No spec requirement is left without a task.

**2. Placeholder scan:** No "TBD"/"TODO"/"handle edge cases"/"similar to Task N" — every module task carries its complete file content. ✔

**3. Type/name consistency:**
- `module.cluster` outputs used by root `outputs.tf` (`ingress_private_ip`, `control_server_private_ips`) match `nomad-cluster/outputs.tf` (unchanged). ✔
- Each module's `outputs.tf` is unchanged: api/control/build/orchestrator/clickhouse output `local.private_ips` (each `main.tf` defines `locals.private_ips`); ingress outputs `local.private_ip` (defined in Task 7). ✔
- Version vars `consul_version`/`nomad_version`/`vault_version` flow root → nomad-cluster → every module → `setup-base.sh` env. ✔
- `consul_retry_join_ips` consumed by api/ingress/orchestrator/build/clickhouse; supplied by `module.control_server.private_ips`. Control-server itself uses `jsonencode(var.private_ips)`. ✔
- `job_constraint_prefix` (clickhouse) supplied by root local `clickhouse_pool_name`. ✔

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-06-21-iac-baremetal-provider.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
