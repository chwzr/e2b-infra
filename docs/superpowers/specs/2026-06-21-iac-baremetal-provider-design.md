# Design: `iac/provider-baremetal`

**Date:** 2026-06-21
**Branch:** `feat-iac-baremetal` (based on `feat-iac-proxmox`)
**Status:** Approved design — ready for implementation plan

## Goal

Add a new Terraform IaC provider, `iac/provider-baremetal/`, that deploys the E2B
Nomad cluster onto **already-provisioned servers**. The operator supplies the
private IPs of existing Ubuntu 24.04 machines (each with the deploy SSH key on
`root`); there is **no Packer base image and no VM creation**. All host
configuration — everything the proxmox provider's Packer build used to bake plus
the per-role runtime setup — runs over SSH at `terraform apply` time.

## Background — how `provider-proxmox` works today

1. **Packer** (`nomad-cluster-disk-image/main.pkr.hcl`) clones an Ubuntu 24.04
   cloud image and bakes in Docker, Consul, Nomad, Vault, Go, `qemu-guest-agent`,
   gruntwork `bash-commons`, the shared `setup/` scripts, and limits/conntrack
   tuning, producing a Proxmox template.
2. **Terraform** (`main.tf` → `nomad-cluster/main.tf` → `modules/nodepool-*`)
   clones that template into VMs per nodepool, assigns static private IPs via
   cloud-init, then runs a `null_resource.bootstrap` that SSHes in (`root`) and
   executes the per-role `start-*.sh` script.
3. The `start-*.sh` scripts only *configure & start* the pre-baked software, plus
   runtime bits (hugepages, swap, NBD, S3 download of firecracker/envd/kernels,
   Consul/Nomad agent config).
4. The `init` module (S3 buckets + secrets via the `minio` provider) and the
   `nomad` module (Nomad jobs) are already provider-agnostic.

## Approach (chosen: "Terraform, `null_resource`-only")

Copy `provider-proxmox/` to `provider-baremetal/`, then strip every
Proxmox/Packer-specific piece. Each nodepool module loses its VM resource and
keeps only the SSH `null_resource`, now pointed at the supplied IP list. A new
**idempotent `setup-base.sh`** performs everything Packer used to bake and runs
as the first bootstrap step on every node, before the role's `start-*.sh`. The
`init` and `nomad` modules are reused verbatim.

### Decisions locked in during brainstorming

| Question | Decision |
|---|---|
| Role → server mapping | **IP list per nodepool** (`control_server_ips`, `api_ips`, `ingress_ips`, `orchestrator_ips`, `build_ips`, `clickhouse_ips`). |
| Network model | **One private IP per server**, used for both SSH and Consul/Nomad advertise+retry_join. Deploy host has direct network access — **no bastion required** (optional `ssh_bastion_*` retained, default empty). |
| SSH user | **root directly** (hardcoded; scripts already assume root). |
| Provider location | **New `iac/provider-baremetal/` directory** (matches per-provider repo convention). |
| `setup-base.sh` location | **Shared `iac/nomad-cluster-disk-image/setup/`** (additive; reuses existing `install-*.sh`). |
| IP lists input | Via the existing **`.terraform.<env>.tfvars`** file (`TF_VAR_FILE` mechanism). |
| `qemu-guest-agent` | **Installed + enabled** in `setup-base.sh` (operator requested). |

## Components & changes

### 1. New directory `iac/provider-baremetal/`

Created from a copy of `provider-proxmox/`. **Not** carried over:
`nomad-cluster-disk-image/` (Packer), `scripts/setup-pve-host.sh`. The repo-level
shared `iac/nomad-cluster-disk-image/setup/` stays and is reused.

### 2. `setup-base.sh` (new, shared `iac/nomad-cluster-disk-image/setup/`)

The "what Packer baked" step, made **idempotent** (every install guarded by
`command -v` / path existence so re-runs on `apply` are cheap). Replicates the
proxmox Packer `build` block:

- Wait for any in-flight cloud-init/apt to settle, then apt base packages:
  `nvme-cli unzip jq net-tools qemu-utils make build-essential openssh-client
  openssh-server nfs-common qemu-guest-agent dnsutils netcat-openbsd cloud-init`.
- **Docker** via `get.docker.com` (+ `/etc/docker/daemon.json` from `setup/`),
  `systemctl enable docker`.
- **Go** (`snap install go --classic` with apt fallback).
- **gruntwork `bash-commons`** (v0.1.3) into `/opt/gruntwork/bash-commons`.
- **Consul / Nomad / Vault** via the existing `install-consul.sh`,
  `install-nomad.sh`, `install-vault.sh`, pinned to `consul_version` (1.16.2),
  `nomad_version` (1.6.2), `vault_version` (1.20.3) — defaults copied from the
  proxmox `variables.pkr.hcl`, exposed as Terraform variables.
- `mkdir -p /opt/nomad/plugins`.
- `limits.conf` from `setup/`, conntrack/sysctl tuning
  (`net.netfilter.nf_conntrack_max = 2097152`).
- **`qemu-guest-agent`** installed and `systemctl enable`d (operator requested).
- For **orchestrator + build** roles: assert `/dev/kvm` exists; fail with a clear
  message if hardware virtualization is disabled in BIOS. (Role passed in as an
  arg/template var so the base script knows whether to enforce KVM.)

Reset/cloud-init-clean steps from Packer are dropped (these are persistent
servers, not a template being sealed).

### 3. Nodepool modules (×6: control-server, api, ingress, orchestrator, build, clickhouse)

Each module:
- **Removes** `proxmox_virtual_environment_vm` and its vars: `pve_node`,
  `pve_storage_pool`, `base_template`, `base_template_vm_id`, `bridge`,
  `subnet_cidr`, `gateway_ip`, `dns_servers`, `cpu_cores`, `memory_mb`,
  `disk_size_gb`, `ip_offset`, `ssh_public_key`; clickhouse also drops
  `data_volume_size_gb`.
- **Adds** `private_ips = list(string)`. `count = length(var.private_ips)`;
  `locals.private_ips = var.private_ips` (no CIDR math, no `subnet_mask`).
- Keeps `null_resource.bootstrap` (`count = length(var.private_ips)`):
  - `connection`: `host = var.private_ips[count.index]`, `user = "root"`,
    `private_key = var.ssh_private_key`, optional `bastion_*`.
  - `triggers`: `filesha256(start-<role>.sh)` + `filesha256(setup-base.sh)` +
    the IP (no `vm_id`).
  - **Step 1 (new):** upload the shared `setup/` dir + run `setup-base.sh <role>`.
  - **Step 2:** upload + run the role's `start-<role>.sh` (templated, unchanged
    logic — hugepages/NBD/S3/agent config stay as-is).
- The `start-<role>.sh` scripts are copied as-is from proxmox; runtime behavior
  unchanged. (`PRIVATE_IP` = the node's supplied IP; `CONSUL_RETRY_JOIN` =
  control server IP list.)

### 4. `nomad-cluster/main.tf`

Passes `private_ips` per module instead of size/cpu/mem/disk/pve/bridge/dns vars.
`consul_retry_join_ips = module.control_server.private_ips` (= `control_server_ips`).
Each control server's own `CONSUL_RETRY_JOIN` is the full `control_server_ips`.

### 5. Top-level `main.tf` / `variables.tf` / `outputs.tf`

- `main.tf`: drop the `proxmox` provider block and `required_providers.proxmox`;
  `module "cluster"` passes `*_ips` lists. Keep the `ssh_private_key`
  path-or-content helper local. `init` and `nomad` module blocks unchanged.
- `variables.tf`: **remove** `proxmox_*`, `pve_*`, `base_template*`, `bridge`,
  `subnet_cidr`, `gateway_ip`, `dns_servers`, `ssh_public_key`, all
  `*_cluster_size` / `*_cpu_cores` / `*_memory_mb` / `*_disk_size_gb` /
  `clickhouse_data_volume_size_gb`. **Add** `control_server_ips`, `api_ips`,
  `ingress_ips`, `orchestrator_ips`, `build_ips`, `clickhouse_ips` (all
  `list(string)`), and `consul_version` / `nomad_version` / `vault_version`.
  **Keep** `domain_name`, `prefix`, `environment`, `datacenter`,
  `ssh_private_key`, `ssh_bastion_*`, `nomad_address`, `acme_email`,
  `ingress_image`, `hcloud_*`, `redis_managed`, `client_proxy_count`, `s3_*`,
  `container_registry_url`, and all app/grafana secrets.
- `outputs.tf`: `ingress_private_ip` → `var.ingress_ips[0]`;
  `control_server_private_ips` → `var.control_server_ips`; keep `domain_name`.

### 6. Makefile / config

- Drop the `setup-pve-host` target and the `PROXMOX_*`, `PVE_*`, `BRIDGE`,
  `SUBNET_CIDR`, `GATEWAY_IP`, `BASE_TEMPLATE*` `tfvar` lines.
- Scalars stay env-derived `tfvars`; **IP lists live in `.terraform.<env>.tfvars`**
  (already passed to `plan` via `TF_VAR_FILE_ARG`).
- `provider-login` prints "No provider login required for baremetal."

### 7. Docs

`self-host-baremetal.md`: prerequisites (N Ubuntu 24.04 servers, deploy SSH key
on `root`, shared private network reachable from the deploy host, `/dev/kvm` on
orchestrator + build hosts) and a `.terraform.<env>.tfvars` example showing the
per-pool IP lists.

## Idempotency & re-runs

`apply` re-runs the bootstrap on a node when its IP, `setup-base.sh`, or its
`start-*.sh` changes (trigger hashes). `setup-base.sh` is guarded so re-runs skip
already-installed software; `start-*.sh` is already written to be re-runnable.

## Non-goals (YAGNI)

- Firewall/port hardening (trusted private network assumed).
- Provisioning the OS / base SSH key (servers pre-exist by definition).
- Multi-NIC or public-vs-private IP split (single private IP per node).
- Co-locating multiple roles on one server.
- Managing DNS / load-balancer in front of the ingress.

## Open risks

- Base install over SSH is slower than a baked image and depends on outbound
  internet from each server (Docker/Go/apt/Hashicorp downloads).
- `/dev/kvm` must be available on orchestrator + build hosts (asserted, not
  fixed, by the bootstrap).
