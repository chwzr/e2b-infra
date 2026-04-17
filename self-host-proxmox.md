# Self-hosting E2B on Proxmox

Deploy E2B on a Proxmox VE host, with VMs provisioned by Terraform and a base
image built by Packer. Object storage and Terraform state use Hetzner Object
Storage (or any S3-compatible service); DNS is managed manually in your provider
of choice. All cluster traffic stays on a private Proxmox bridge except for a
single Traefik ingress VM that has a public IP.

## Prerequisites

**Tools**

- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) (v1.5.x)
  - We ask for v1.5.x because starting from v1.6 Terraform [switched](https://github.com/hashicorp/terraform/commit/b145fbcaadf0fa7d0e7040eac641d9aef2a26433) their license from Mozilla Public License to Business Source License.
  - The last version of Terraform that supports Mozilla Public License is **v1.5.7**
    - Binaries are available [here](https://developer.hashicorp.com/terraform/install/versions#binary-downloads)
    - You can also install it via [tfenv](https://github.com/tfutils/tfenv)
      ```sh
      brew install tfenv
      tfenv install 1.5.7
      tfenv use 1.5.7
      ```

- [Packer](https://developer.hashicorp.com/packer/install) (>= 1.8.4) — for building the base VM template

- [Golang](https://go.dev/doc/install)

- [Docker](https://docs.docker.com/engine/install/) with Buildx

- [NPM](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) — used with `--endpoint-url` for S3-compatible uploads (not only AWS)

**Accounts & Services**

- A Proxmox VE host (7.x or 8.x) with:
  - Nested virtualization enabled on the host CPU (`/sys/module/kvm_intel/parameters/nested = Y`, or `kvm_amd` on AMD)
  - Two pre-configured Linux bridges: one public (e.g. `vmbr0`) and one private (e.g. `vmbr1`) with host-side masquerade/NAT for egress — see [Hetzner's vSwitch + public subnet guide](https://community.hetzner.com/tutorials/install-and-configure-proxmox_ve#23-vswitch-with-a-public-subnet) for one working setup
  - An Ubuntu 24.04 Server ISO uploaded to the PVE ISO storage
  - An API token with VM + storage + ISO privileges
- An S3-compatible object storage (Hetzner Object Storage or self-hosted MinIO) with an **already-provisioned** bucket for Terraform state
- A domain whose DNS you control — any provider, Terraform does not manage DNS
- A PostgreSQL database (Supabase's Postgres only supported for now)
- A Docker container registry reachable from inside the cluster (private Harbor, ghcr.io, Docker Hub, etc.)

**Optional** — recommended for monitoring and logging: Grafana Cloud account & stack.

---

## Architecture Overview

Single Proxmox host; every node pool is a `proxmox_vm_qemu` VM cloned from one
Packer-built Ubuntu 24.04 template. Only the ingress VM has a public IP.

```
Proxmox host
├── vmbr0 (public)   ── Ingress VM public NIC
└── vmbr1 (private, 10.0.0.0/24)
     ├── .11-.13  Control servers (Nomad/Consul)
     ├── .21+     API nodes
     ├── .31+     ClickHouse
     ├── .41      Ingress VM private NIC (Traefik)
     ├── .51+     Orchestrator (Firecracker, nested KVM)
     └── .101+    Build / template-manager (nested KVM)
```

**Node Pools**

| Pool             | Role                                                              | Nested KVM | Public IP |
|------------------|-------------------------------------------------------------------|------------|-----------|
| `control-server` | Nomad + Consul servers                                             | no         | no        |
| `api`            | API, client-proxy, OTEL, Loki, logs collector                      | no         | no        |
| `ingress`        | Traefik only — terminates all external traffic                     | no         | **yes**   |
| `orchestrator`   | Firecracker sandbox runner                                         | **yes**    | no        |
| `build`          | Template-manager (builds sandbox templates with Firecracker)       | **yes**    | no        |
| `clickhouse`     | Analytics DB, second virtio disk mounted at `/clickhouse`          | no         | no        |

Traffic flow: client → DNS → ingress VM's public IP → Traefik (Nomad job on the
`ingress` pool) → internal service via Consul Catalog over the private bridge.

---

## Step 1: Prepare Proxmox and External Resources

### 1.1 Proxmox host

1. Install Proxmox VE 7.x or 8.x on your hardware.
2. **Enable nested virtualization** on the host. On Intel:
   ```sh
   echo "options kvm-intel nested=Y" > /etc/modprobe.d/kvm-intel.conf
   modprobe -r kvm_intel && modprobe kvm_intel
   cat /sys/module/kvm_intel/parameters/nested   # should print Y
   ```
   On AMD: same with `kvm_amd`.
3. Configure two bridges on the host — a public `vmbr0` with your routable
   IPs and a private `vmbr1` (e.g. `10.0.0.0/24` with the host as gateway
   `10.0.0.1`). Masquerade egress from the private subnet on the host, e.g.
   in `/etc/network/interfaces`:
   ```
   auto vmbr1
   iface vmbr1 inet static
       address 10.0.0.1/24
       bridge-ports none
       bridge-stp off
       bridge-fd 0
       post-up   iptables -t nat -A POSTROUTING -s '10.0.0.0/24' -o vmbr0 -j MASQUERADE
       post-down iptables -t nat -D POSTROUTING -s '10.0.0.0/24' -o vmbr0 -j MASQUERADE
   ```
4. Upload the Ubuntu 24.04 Server ISO to the PVE ISO storage (e.g.
   `local:iso/ubuntu-24.04.1-live-server-amd64.iso`).
5. Create an API token: **Datacenter → Permissions → API Tokens → Add**.
   Give it enough privileges to create VMs, use storage, and attach ISOs
   (e.g. `PVEVMAdmin` on `/` plus `Datastore.Allocate` on the storage pool).
   Save the token ID (`user@realm!tokenname`) and secret.

### 1.2 S3-compatible object storage

1. Create Object Storage credentials (Access Key + Secret Key) in Hetzner
   (or your MinIO instance).
2. Note the endpoint (e.g. `fsn1.your-objectstorage.com`) and region
   (e.g. `fsn1`).
3. **Pre-create** a bucket for Terraform state (e.g. `e2b-terraform-state`).
   The runtime buckets (kernels, templates, loki, etc.) are created by
   `make init` later.

### 1.3 Domain / DNS

Terraform does **not** manage DNS on Proxmox. Pick any DNS provider. You'll
create a single wildcard A record later (Step 7) pointing at the ingress VM's
public IP.

### 1.4 Container registry

You need a Docker registry to host the service images. Options:
- Self-hosted registry (Harbor, Distribution, Zot)
- GitHub Container Registry (`ghcr.io`)
- Docker Hub

Requirements:
- The registry must be reachable from **inside** the private subnet (via the
  host's NAT). If it's self-hosted on the same Proxmox, it needs to be on
  a reachable bridge.
- Log in from your dev machine (`docker login <registry>`) so `make build-and-upload`
  can push.

Note the registry URL — it becomes `CONTAINER_REGISTRY_URL`.

### 1.5 SSH key

Generate (or reuse) an SSH key pair that will be baked into VMs via cloud-init
and used by Terraform's `remote-exec` bootstrap:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/e2b-proxmox -C "e2b-cluster"
```

You'll need:
- The **public key** content for `SSH_PUBLIC_KEY`
- The **private key** content for `SSH_PRIVATE_KEY`

> **Important:** `terraform apply` has to SSH to the VMs' private IPs to bootstrap
> them. Run it from somewhere on the private subnet — typically the Proxmox host
> itself, or a workstation connected via VPN / WireGuard.

---

## Step 2: Build the Base VM Template

All node pool VMs clone from one Packer-built Ubuntu 24.04 template that has
Docker, Consul, Nomad, Vault, qemu-guest-agent, and the shared setup scripts
pre-installed.

```sh
cd iac/provider-proxmox/nomad-cluster-disk-image
packer init .
packer build \
  -var "proxmox_url=https://pve.example.com:8006/api2/json" \
  -var "proxmox_username=root@pam" \
  -var "proxmox_password=..." \
  -var "proxmox_node=pve" \
  -var "template_storage=local-lvm" \
  -var "iso_file=local:iso/ubuntu-24.04.1-live-server-amd64.iso" \
  -var "packer_build_bridge=vmbr0" \
  .
```

Packer will create a new VM from the ISO, run Ubuntu autoinstall, install all
tooling, shut down, and convert the VM to a template. The output template name
is printed at the end — copy it into `BASE_TEMPLATE` in the env file.

> If you use an API token instead of user/password, pass `-var "proxmox_username=<token-id>"` and `-var "proxmox_token=<token-secret>"`.

Rebuild this whenever the shared setup scripts under
`iac/nomad-cluster-disk-image/setup/` change.

---

## Step 3: Configure Environment

1. Create `.env.prod`, `.env.staging`, or `.env.dev` from
   [`.env.proxmox.template`](.env.proxmox.template). Fill in all values:

   ```sh
   PROVIDER=proxmox
   DOMAIN_NAME=<your-domain.com>
   CONTAINER_REGISTRY_URL=<registry.example.com>

   # S3-compatible storage (already-provisioned state bucket + runtime buckets)
   S3_ENDPOINT=<fsn1.your-objectstorage.com>
   S3_ACCESS_KEY=<your-access-key>
   S3_SECRET_KEY=<your-secret-key>
   S3_REGION=<fsn1>
   S3_BUCKET=<e2b-terraform-state>

   # Proxmox
   PROXMOX_API_URL=https://pve.example.com:8006/api2/json
   PROXMOX_API_TOKEN_ID=root@pam!terraform
   PROXMOX_API_TOKEN_SECRET=<token-secret>
   PROXMOX_TLS_INSECURE=false
   PVE_NODE=pve
   PVE_STORAGE_POOL=local-lvm
   BASE_TEMPLATE=<name-from-packer-output>

   # Networking (pre-configured on the PVE host)
   PUBLIC_BRIDGE=vmbr0
   PRIVATE_BRIDGE=vmbr1
   PRIVATE_SUBNET_CIDR=10.0.0.0/24
   PRIVATE_GATEWAY_IP=10.0.0.1

   # Ingress VM — the ONE public IP
   INGRESS_PUBLIC_IP=<your-public-ipv4>
   INGRESS_PUBLIC_GATEWAY=<gateway-on-vmbr0>
   INGRESS_PUBLIC_CIDR_BIT=24

   # SSH (paste the full PEM content)
   SSH_PUBLIC_KEY="ssh-ed25519 AAAA... e2b-cluster"
   SSH_PRIVATE_KEY="-----BEGIN OPENSSH PRIVATE KEY-----
   ...
   -----END OPENSSH PRIVATE KEY-----"

   # Cluster sizes (tune per host capacity)
   CONTROL_SERVER_CLUSTER_SIZE=3
   API_CLUSTER_SIZE=1
   ORCHESTRATOR_CLUSTER_SIZE=1
   BUILD_CLUSTER_SIZE=1
   CLICKHOUSE_CLUSTER_SIZE=1

   # App secrets
   POSTGRES_CONNECTION_STRING=<from-supabase-or-other>
   SUPABASE_JWT_SECRETS=<from-supabase>
   ```

   > Get the PostgreSQL connection string from your database provider, e.g.
   > [from Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres#direct-connection).

2. Activate the environment:

   ```sh
   PROVIDER=proxmox make switch-env ENV=prod   # or staging / dev
   ```

---

## Step 4: Initialize Infrastructure

```sh
PROVIDER=proxmox make init
```

This:
- Configures the Terraform S3 backend against your pre-created state bucket.
- Applies the `init` module, which creates the runtime S3 buckets (templates,
  kernels, fc-versions, env-pipeline, build-cache, loki, clickhouse-backups)
  and generates the Consul/Nomad ACL tokens + gossip key (stored in Terraform
  state, exposed as outputs to the rest of the stack).

---

## Step 5: Build and Upload Artifacts

```sh
PROVIDER=proxmox make build-and-upload
```

This builds and pushes every service container image to `CONTAINER_REGISTRY_URL`
and uploads the Firecracker-side binaries (`orchestrator`, `template-manager`,
`envd`, `clean-nfs-cache`, `nomad-nodepool-apm`) to your S3 `fc-env-pipeline`
bucket via `aws s3 cp --endpoint-url`.

```sh
PROVIDER=proxmox make copy-public-builds
```

Copies public Firecracker kernels and rootfs builds into your `fc-kernels` and
`fc-versions` buckets.

---

## Step 6: Deploy Infrastructure

```sh
PROVIDER=proxmox make plan-without-jobs
PROVIDER=proxmox make apply
```

This provisions (in order):
- Control server VMs — Consul + Nomad cluster bootstrapped via cloud-init +
  Terraform `remote-exec`.
- API, ingress, ClickHouse, orchestrator, and build VMs. Each joins the
  existing Consul cluster using the control servers' private IPs.

Terraform must be able to SSH to each VM's private IP (Step 1.5 note).

---

## Step 7: Create the Wildcard DNS Record

After `apply` finishes, Terraform prints:

```
ingress_public_ip = "X.X.X.X"
```

Go to your DNS provider and create a wildcard A record:

```
*.<your-domain>    A    X.X.X.X    300
```

Wait for propagation (`dig +short anything.<your-domain>` should return the IP).

---

## Step 8: Deploy Nomad Jobs

```sh
PROVIDER=proxmox make plan
PROVIDER=proxmox make apply
```

This deploys all Nomad jobs: API, Traefik ingress (pinned to the ingress VM),
client-proxy, orchestrator, template-manager, ClickHouse, Loki, OTEL collector,
logs-collector, and Redis (unless you set `REDIS_MANAGED=true`).

Database migrations run automatically via the API's `db-migrator` task the
first time it comes up.

---

## Step 9: Initial Setup

```sh
cd packages/shared
make prep-cluster
```

Creates an initial user, team, and base template. Optionally:

```sh
cd packages/db
make seed-db
```

---

## Proxmox Architecture Details

### Networking

- **Public bridge** (`vmbr0`): host-attached bridge with routable IPv4. Used
  only by the ingress VM's first NIC.
- **Private bridge** (`vmbr1`): `10.0.0.0/24`. All other VMs, plus the ingress
  VM's second NIC. The PVE host does MASQUERADE for egress (Step 1.1).
- **Service Discovery**: Consul DNS (`.service.consul`) for all inter-service
  lookups. Cluster VMs point `/etc/systemd/resolved.conf.d/consul.conf` at
  Consul's local DNS listener on port 8600.

### Storage

- **S3-compatible Object Storage**: templates, kernels, Firecracker versions,
  build cache, Loki logs, ClickHouse backups, and all binary artifacts
  (`orchestrator`, `template-manager`, `envd`, `nomad-nodepool-apm`).
- **ClickHouse data disk**: second virtio-scsi disk on each ClickHouse VM,
  formatted XFS and mounted at `/clickhouse` by the bootstrap script.
- **tmpfs**: 65 GB snapshot cache on orchestrator / build VMs.

### VM sizing (per pool)

Every pool exposes **count + per-VM CPU, RAM, and disk** as `.env` variables,
all wired through the Makefile's `TF_VAR_*` plumbing. Defaults are small-host /
dev sized — scale up for production. The ingress pool is always a single VM by
design (dual-NIC, the only public IP), so it has no size variable — only
sizing.

**Cluster size (VM count per pool)**

| Variable                      | Default | Notes |
|-------------------------------|---------|-------|
| `CONTROL_SERVER_CLUSTER_SIZE` | `3`     | Odd number for Raft quorum |
| `API_CLUSTER_SIZE`            | `1`     | Scale to 2+ for HA |
| `ORCHESTRATOR_CLUSTER_SIZE`   | `1`     | Scale with sandbox load |
| `BUILD_CLUSTER_SIZE`          | `1`     | Template build concurrency |
| `CLICKHOUSE_CLUSTER_SIZE`     | `1`     | Each gets its own data disk |

**Per-VM sizing**

| Pool           | CPU var                      | Memory var                   | Root disk var                   | Extra |
|----------------|------------------------------|------------------------------|---------------------------------|-------|
| control-server | `CONTROL_SERVER_CPU_CORES` (2)  | `CONTROL_SERVER_MEMORY_MB` (4096)  | `CONTROL_SERVER_DISK_SIZE_GB` (20) | — |
| api            | `API_CPU_CORES` (2)             | `API_MEMORY_MB` (4096)             | `API_DISK_SIZE_GB` (20)            | — |
| ingress        | `INGRESS_CPU_CORES` (2)         | `INGRESS_MEMORY_MB` (2048)         | `INGRESS_DISK_SIZE_GB` (20)        | — |
| orchestrator   | `ORCHESTRATOR_CPU_CORES` (8)    | `ORCHESTRATOR_MEMORY_MB` (16384)   | `ORCHESTRATOR_DISK_SIZE_GB` (100)  | nested KVM (`cpu=host`) |
| build          | `BUILD_CPU_CORES` (8)           | `BUILD_MEMORY_MB` (16384)          | `BUILD_DISK_SIZE_GB` (100)         | nested KVM (`cpu=host`) |
| clickhouse     | `CLICKHOUSE_CPU_CORES` (4)      | `CLICKHOUSE_MEMORY_MB` (8192)      | `CLICKHOUSE_DISK_SIZE_GB` (20)     | `CLICKHOUSE_DATA_VOLUME_SIZE_GB` (100) — second virtio disk mounted at `/clickhouse` |

> `CPU_CORES` is the number of cores presented to the guest (single socket,
> `cpu = "host"`). `MEMORY_MB` is the guest RAM in megabytes. `DISK_SIZE_GB`
> is the root disk on `$PVE_STORAGE_POOL`.

**Example production sizing** (`.env`):

```sh
# Fat orchestrators for many concurrent sandboxes
ORCHESTRATOR_CLUSTER_SIZE=2
ORCHESTRATOR_CPU_CORES=16
ORCHESTRATOR_MEMORY_MB=65536
ORCHESTRATOR_DISK_SIZE_GB=200

# Larger API tier for HA
API_CLUSTER_SIZE=2
API_CPU_CORES=4
API_MEMORY_MB=8192

# ClickHouse with a bigger data volume
CLICKHOUSE_CPU_CORES=8
CLICKHOUSE_MEMORY_MB=16384
CLICKHOUSE_DATA_VOLUME_SIZE_GB=500
```

All size changes propagate via `terraform plan` / `apply`:
- **CPU / memory**: applied in-place by Proxmox (may require a VM reboot depending on whether memory hot-plug is enabled).
- **Root / data disk size**: grown in-place; Proxmox resizes the underlying volume. You may need to run `growpart` + `resize2fs` / `xfs_growfs` inside the guest to expand the filesystem.
- **Cluster size (count)**: new VMs are provisioned and bootstrapped; removed VMs are destroyed.

The VM `lifecycle` block ignores `network`, `ipconfig0`, `ciuser`, and `sshkeys`
to avoid cloud-init drift — so the private IP, SSH key, and NIC model are
effectively set-once at VM creation.

> **Nested KVM requirement:** the Proxmox host must have nested virtualization
> enabled (Step 1.1). The orchestrator and build pool VMs use `cpu = "host"`
> so their Firecracker microVMs can see `/dev/kvm`.

### Secrets

Proxmox has no managed secrets service — secrets are:
- Auto-generated by Terraform (Consul/Nomad ACL tokens, gossip key, ClickHouse
  password, API secret, admin token, sandbox access token seed).
- Stored in Terraform state (encrypt at rest at the S3 layer).
- Passed to Nomad jobs as environment variables, and to the VM bootstrap
  scripts via the `file` + `remote-exec` provisioners.

The Nomad `module.nomad` uses `provider_name = "hetzner"` because Proxmox's
stack (S3-compatible storage + custom Docker registry) is functionally
identical to Hetzner's, and the shared job modules validate `provider_name`
against `["gcp", "aws", "hetzner"]`.

---

## Interacting with the Cluster

### SDK

```js
import { Sandbox } from "e2b";

const sandbox = await Sandbox.create({
  domain: "<your-domain>",
});
```

```python
from e2b import Sandbox

sandbox = Sandbox.create(domain="<your-domain>")
```

### CLI

```sh
E2B_DOMAIN=<your-domain> e2b <command>
```

### Nomad UI

`https://nomad.<your-domain>` — Traefik routes it through the ingress VM to the
control servers. Use the Nomad ACL token from Terraform state
(`terraform output -raw` on the `init` module) for login.

---

## Troubleshooting

### Terraform can't SSH to a VM during `apply`

You need SSH reachability to the private subnet. Options:
- Run `terraform apply` on the Proxmox host itself.
- Run it from a workstation connected to the private subnet via
  WireGuard / Tailscale / OpenVPN.
- Temporarily assign the node a public IP and update the module's `connection
  { host = ... }` to the public address (not recommended).

### VM comes up but doesn't join Consul

1. SSH to the VM (`ssh -i ~/.ssh/e2b-proxmox root@<private-ip>`).
2. Check Consul status: `systemctl status consul` and `tail -f /var/log/start-*.log`.
3. Verify the retry-join targets: `cat /opt/consul/config/default.json | jq .retry_join` —
   they should match your control server private IPs.
4. Check connectivity to a control server: `nc -vz <control-ip> 8301`.

### Nested KVM not available on orchestrator / build VMs

On a VM: `ls -la /dev/kvm` should show the char device, and `kvm-ok` should
report "KVM acceleration can be used". If not:
1. On the Proxmox host: `cat /sys/module/kvm_intel/parameters/nested` must
   print `Y`.
2. The VM config must use `cpu: host` (the Terraform module does this —
   verify in the PVE UI: VM → Hardware → Processors).
3. Power-cycle the VM after enabling nested on the host (a reboot of the
   guest is not enough if the feature was only just toggled).

### Ingress VM can't reach private services

The ingress VM has two NICs — verify that the private NIC came up with the
expected IP:
```sh
ssh root@<INGRESS_PUBLIC_IP> ip -4 addr show
```
Both NICs should have addresses (`ens18` public, `ens19` private). If not,
check the Proxmox cloud-init status in the PVE UI (VM → Cloud-Init) and
re-run the init: `qm set <vmid> --citype nocloud` then regenerate.

### Packer build hangs at "waiting for ssh"

- Check the PVE VM console during autoinstall — subiquity output will show
  why installation is stuck.
- Verify the HTTP user-data file is reachable from the new VM (Packer binds
  `http_directory` on the machine running Packer — it has to be reachable
  from the PVE bridge used during build).
- `ssh_password` must match the password hashed in `http/user-data` (default
  is `packer`).

### S3 / Object Storage errors

1. Verify endpoint, access key, secret key in `.env`.
2. `aws s3 ls --endpoint-url https://$S3_ENDPOINT s3://$S3_BUCKET/` should
   succeed from wherever you run `terraform apply`.
3. Ensure the state bucket exists (it's pre-created, not managed by Terraform).

### Docker image pulls fail on the VMs

1. Confirm `CONTAINER_REGISTRY_URL` is reachable from a VM:
   `ssh root@<private-ip> curl -I https://<registry-url>/v2/`.
2. Check `/root/docker/config.json` on the VM — it should contain an `auths`
   entry for your registry (populated by the bootstrap script). If it's
   empty, `CONTAINER_REGISTRY_URL` was likely blank in `.env`.
3. For private registries, you may need to log the daemon in manually
   (`docker login` baked into the Packer template or passed via an env file).

---

## Make Commands Cheat Sheet

All commands below should be prefixed with `PROVIDER=proxmox` (or exported once
per shell).

- `make init` — initialize Terraform backend, create runtime buckets and secrets
- `make plan` — plan all Terraform changes
- `make apply` — apply Terraform changes (run `make plan` first)
- `make plan-without-jobs` — plan infrastructure only (no Nomad jobs)
- `make plan-only-jobs` — plan Nomad jobs only
- `make destroy` — destroy the cluster (VMs + buckets)
- `make build-and-upload` — build and push service images; upload binaries to S3
- `make copy-public-builds` — copy Firecracker kernels and rootfs to your S3 buckets
- `make switch-env ENV={prod,staging,dev}` — switch active environment
