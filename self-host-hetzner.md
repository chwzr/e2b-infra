# Self-hosting E2B on Hetzner

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

- [Golang](https://go.dev/doc/install)

- [Docker](https://docs.docker.com/engine/install/)

- [NPM](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)

- [gsutil](https://cloud.google.com/storage/docs/gsutil_install) (for copying public Firecracker builds)

**Accounts & Services**

- Hetzner Cloud account with API token
- Hetzner Robot account (for dedicated servers)
- Domain managed via Hetzner DNS
- PostgreSQL database (Supabase's DB only supported for now)
- S3-compatible object storage (Hetzner Object Storage or self-hosted MinIO)
- Docker container registry (self-hosted or Docker Hub)

**Optional**

Recommended for monitoring and logging:
- Grafana Account & Stack

---

## Architecture Overview

The Hetzner deployment uses a hybrid approach:

- **Hetzner Cloud VMs** for control servers, API nodes, and ClickHouse
- **Hetzner Robot Dedicated Servers** for Firecracker orchestrator **and build (template-manager)** nodes (Cloud VMs don't support KVM nested virtualization)
- **Hetzner Cloud Network + vSwitch** to connect Cloud VMs and dedicated servers on a private network
- **Hetzner Object Storage** (S3-compatible) for templates, kernels, logs, and backups
- **Hetzner DNS** for domain management

```
Cloud Network (10.0.0.0/8)
├── Subnet 10.0.0.0/24 (cloud)   ── Control Servers, API, ClickHouse
└── Subnet 10.0.1.0/24 (vswitch) ── Dedicated Servers
                                      ├── .2+    Orchestrator (Firecracker)
                                      └── .100+  Build (template-manager)
```

**Node Pools:**
- **Control Server** - Nomad/Consul servers (default: 3x `cx32`)
- **API** - API server, ingress, client proxy, otel, loki, logs collector (default: `cx32`)
- **Build** - Template manager for building sandbox templates on dedicated servers (manually provisioned, requires KVM)
- **ClickHouse** - Analytics database with persistent volumes (default: `cx32`)
- **Orchestrator** - Firecracker VM orchestrator on dedicated servers (manually provisioned)

---

## Step 1: Prepare Hetzner Resources

Before running Terraform, you need to set up a few things manually in Hetzner:

### 1.1 Hetzner Cloud API Token

1. Go to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Create a new project (or use an existing one)
3. Go to **Security** > **API Tokens** > **Generate API Token** (Read & Write)
4. Save the token — you'll need it for `HCLOUD_TOKEN`

### 1.2 Hetzner Object Storage

1. Go to [Hetzner Cloud Console](https://console.hetzner.cloud/) > **Object Storage**
2. Create Object Storage credentials (Access Key + Secret Key)
3. Note the endpoint (e.g. `fsn1.your-objectstorage.com`) and region (e.g. `fsn1`)
4. Create a bucket for Terraform state (e.g. `e2b-terraform-state`)

### 1.3 Hetzner DNS

1. Go to [Hetzner DNS Console](https://dns.hetzner.com/)
2. Add your domain (or ensure it's already managed there)
3. Point your domain's nameservers to Hetzner DNS if not already

### 1.4 Dedicated Servers (for Orchestrator and Build)

Firecracker requires bare-metal KVM access, which Hetzner Cloud VMs don't provide. You need dedicated servers from [Hetzner Robot](https://robot.hetzner.com/) for **both** the orchestrator pool (running sandboxes) and the build pool (template-manager — builds sandbox templates using Firecracker).

1. Order dedicated servers via [Hetzner Robot](https://robot.hetzner.com/server/order)
   - **Orchestrator** servers: high RAM, fast NVMe (sandbox workloads)
   - **Build** servers: moderate RAM, fast I/O (template build workloads) — at least one
   - Install **Ubuntu 24.04** as the operating system
2. Ensure SSH root access works with your SSH key
3. Note the **public IPs** of each server — they'll go into `ORCHESTRATOR_SERVER_IPS` and `BUILD_SERVER_IPS` (disjoint lists)

### 1.5 vSwitch (connects dedicated servers to Cloud Network)

1. In [Hetzner Robot](https://robot.hetzner.com/) > **vSwitches** > **Create vSwitch**
2. Select VLAN ID (default: `4000`)
3. Attach **all** dedicated servers (orchestrator + build) to the same vSwitch — they share the VLAN and `10.0.1.0/24` subnet, with orchestrator IPs starting at `.2` and build IPs at `.100` to avoid collision
4. Note the **vSwitch ID** — Terraform will create a Cloud Network subnet linked to it

### 1.6 Container Registry

You need a Docker registry to store container images. Options:
- Self-hosted registry (e.g. Harbor, Docker Registry)
- Docker Hub
- GitHub Container Registry (ghcr.io)

Note the registry URL (e.g. `registry.example.com`).

### 1.7 SSH Key

Generate an SSH key pair for cluster node access (or use an existing one):
```sh
ssh-keygen -t ed25519 -f ~/.ssh/e2b-hetzner -C "e2b-cluster"
```

You'll need:
- The **public key** content for `SSH_PUBLIC_KEY` (for Cloud VMs)
- The **private key** content for `ORCHESTRATOR_SSH_PRIVATE_KEY` (for dedicated server provisioning)

---

## Step 2: Configure Environment

1. Create `.env.prod`, `.env.staging`, or `.env.dev` from [`.env.hetzner.template`](.env.hetzner.template). Fill in all values:

   ```sh
   # Required
   HCLOUD_TOKEN=<your-hcloud-api-token>
   DOMAIN_NAME=<your-domain.com>
   CONTAINER_REGISTRY=<registry.example.com>

   # S3-compatible storage
   S3_ENDPOINT=<fsn1.your-objectstorage.com>
   S3_ACCESS_KEY=<your-access-key>
   S3_SECRET_KEY=<your-secret-key>
   S3_REGION=<fsn1>
   S3_BUCKET=<e2b-terraform-state>

   # Dedicated servers
   VSWITCH_ID=<vswitch-id-from-robot>
   VSWITCH_VLAN_ID=4000
   ORCHESTRATOR_SERVER_IPS=<1.2.3.4,5.6.7.8>
   ORCHESTRATOR_SSH_PRIVATE_KEY=<path-or-content>
   ```

   > Get the PostgreSQL connection string from your database provider, e.g. [from Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres#direct-connection)

2. Run `make set-env ENV={prod,staging,dev}` to activate your environment

---

## Step 3: Initialize Infrastructure

```sh
make init
```

This creates:
- Hetzner Cloud Network with cloud subnet and vSwitch subnet
- SSH key for cluster nodes
- S3-compatible buckets (templates, kernels, builds, backups, etc.)
- Secrets (Consul/Nomad ACL tokens, gossip encryption key, ClickHouse credentials)

---

## Step 4: Configure Secrets

Hetzner has no managed secrets service — secrets are stored in Terraform state and passed as variables. Create a `.tfvars` file from the provided template:

```sh
cp iac/provider-hetzner/.terraform.tfvars.template iac/provider-hetzner/.terraform.{env}.tfvars
```

Edit `.terraform.{env}.tfvars` (where `{env}` is `prod`, `staging`, or `dev`) and fill in the values:

**Required:**
| Variable | Description | Where to get it |
|---|---|---|
| `ssh_public_key` | SSH public key for Cloud VM access | Your SSH key (e.g. `cat ~/.ssh/e2b-hetzner.pub`) |
| `postgres_connection_string` | PostgreSQL connection string | Your database provider, e.g. [Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres#direct-connection) |
| `supabase_jwt_secrets` | Supabase JWT secret | [Supabase Dashboard](https://supabase.com/dashboard) > Project Settings > Data API > JWT Settings |

**Required for orchestrator (dedicated servers):**
| Variable | Description | Where to get it |
|---|---|---|
| `orchestrator_ssh_private_key` | SSH private key for dedicated servers | Your SSH key (e.g. content of `~/.ssh/e2b-hetzner`) |
| `orchestrator_server_ips` | Public IPs of dedicated servers | [Hetzner Robot](https://robot.hetzner.com/) > Servers |
| `vswitch_id` | vSwitch ID | [Hetzner Robot](https://robot.hetzner.com/) > vSwitches |
| `consul_retry_join_ips` | Private IPs of control server nodes | After first `make apply`, check Hetzner Cloud Console > Servers > private IPs |

> **Note:** `consul_retry_join_ips` creates a chicken-and-egg situation — you need to deploy control servers first (`make plan-without-jobs && make apply`), then get their private IPs, add them to the tfvars, and deploy again with the dedicated servers.

**Optional (monitoring):**
| Variable | Description |
|---|---|
| `grafana_otlp_url` | Grafana Cloud OTLP endpoint |
| `grafana_otel_collector_token` | Grafana Cloud OTEL token |
| `grafana_username` | Grafana Cloud username |
| `grafana_logs_user` | Grafana Logs username |
| `grafana_logs_url` | Grafana Logs endpoint |
| `grafana_logs_collector_api_token` | Grafana Logs API key |
| `launch_darkly_api_key` | LaunchDarkly SDK key |

**Auto-generated by Terraform** (no action needed):
- Consul ACL token, Nomad ACL token, gossip encryption key
- ClickHouse username/password and server secret
- API secret, admin token, sandbox access token hash seed

---

## Step 5: Build and Upload

```sh
make build-and-upload
```

This builds and pushes container images to your registry and uploads binaries to S3-compatible storage.

```sh
make copy-public-builds
```

This copies Firecracker kernel and rootfs builds to your S3 buckets.

---

## Step 6: Deploy Infrastructure

```sh
make plan-without-jobs
make apply
```

This provisions:
- Control server nodes (Nomad/Consul cluster)
- API nodes
- ClickHouse nodes with persistent volumes
- Load balancer with DNS records
- Firewall rules
- Orchestrator bootstrap on dedicated servers (VLAN interface, Consul, Nomad)
- Build (template-manager) bootstrap on dedicated servers (VLAN interface, Consul, Nomad)

---

## Step 7: Deploy Nomad Jobs

```sh
make plan
make apply
```

This deploys all Nomad jobs:
- API, ingress (Traefik), client proxy
- Orchestrator (on dedicated servers)
- Template manager (on dedicated build servers)
- ClickHouse, Loki, OTEL collector, logs collector
- Redis (in-cluster, unless managed Redis is configured)

> Note: This will work after DNS records propagate and the cluster is healthy. Database migrations run automatically via the API's db-migrator task.

---

## Step 8: Initial Setup

```sh
cd packages/shared
make prep-cluster
```

This creates an initial user, team, and builds a base template. You can also seed additional data:

```sh
cd packages/db
make seed-db
```

---

## Hetzner Architecture Details

### Networking

- **Cloud Network** (`10.0.0.0/8`): Private network connecting all Hetzner Cloud VMs
- **Cloud Subnet** (`10.0.0.0/24`): For Cloud VMs (control, API, ClickHouse)
- **vSwitch Subnet** (`10.0.1.0/24`): Bridges Cloud Network to dedicated servers (orchestrator at `.2+`, build at `.100+`) via Hetzner Robot vSwitch
- **VLAN Interface**: Dedicated servers get a VLAN sub-interface (e.g. `eno1.4000`) with MTU 1400
- **Service Discovery**: Consul DNS (`.consul` domain) for all inter-service communication

### Storage

- **Hetzner Object Storage** (S3-compatible): Templates, kernels, Firecracker versions, build cache, Loki logs, ClickHouse backups
- **Hetzner Volumes**: Persistent block storage for ClickHouse data (XFS, mounted at `/clickhouse`)
- **tmpfs**: 65GB snapshot cache on orchestrator/build nodes

### Machine Sizing

All Cloud VM server types can be customized via `.env` variables or `.tfvars`. Defaults are set for small/dev deployments — scale up for production.

**Node pool sizing variables:**

| Variable | Default | Description | Notes |
|---|---|---|---|
| `CONTROL_SERVER_CLUSTER_SIZE` | `3` | Number of Nomad/Consul server nodes | Use odd numbers (3 or 5) for Raft consensus |
| `CONTROL_SERVER_TYPE` | `cx32` | Server type for control nodes | Shared vCPU is fine for control plane |
| `API_CLUSTER_SIZE` | `1` | Number of API nodes | Scale up for HA (2+) |
| `API_SERVER_TYPE` | `cx32` | Server type for API nodes | |
| `BUILD_SERVER_IPS` | _(empty)_ | Comma-separated public IPs of dedicated build servers | Required — template-manager needs KVM (Cloud VMs unsupported) |
| `BUILD_SSH_PRIVATE_KEY` | _(empty)_ | SSH private key for build server access | Optional — falls back to `ORCHESTRATOR_SSH_PRIVATE_KEY` |
| `CLICKHOUSE_CLUSTER_SIZE` | `1` | Number of ClickHouse nodes | Each gets a persistent volume |
| `CLICKHOUSE_SERVER_TYPE` | `cx32` | Server type for ClickHouse nodes | Scale CPU/RAM for analytics workload |

**Hetzner Cloud server type reference:**

| Type | vCPU | RAM | Disk | Category |
|---|---|---|---|---|
| `cx22` | 2 | 4 GB | 40 GB | Shared vCPU (Intel) |
| `cx32` | 4 | 8 GB | 80 GB | Shared vCPU (Intel) |
| `cx42` | 8 | 16 GB | 160 GB | Shared vCPU (Intel) |
| `cx52` | 16 | 32 GB | 320 GB | Shared vCPU (Intel) |
| `ccx13` | 2 | 8 GB | 80 GB | Dedicated vCPU (AMD) |
| `ccx23` | 4 | 16 GB | 160 GB | Dedicated vCPU (AMD) |
| `ccx33` | 8 | 32 GB | 240 GB | Dedicated vCPU (AMD) |
| `ccx43` | 16 | 64 GB | 360 GB | Dedicated vCPU (AMD) |
| `ccx53` | 32 | 128 GB | 600 GB | Dedicated vCPU (AMD) |
| `ccx63` | 48 | 192 GB | 960 GB | Dedicated vCPU (AMD) |

> **Important:** Template building requires nested virtualization (KVM), which Hetzner Cloud VMs do not support. The build pool must therefore run on **dedicated servers** (set via `BUILD_SERVER_IPS`), same as the orchestrator pool. Control, API, and ClickHouse nodes can use shared vCPU (`cx*`) Cloud VMs.

> Full and up-to-date list: [Hetzner Cloud Pricing](https://www.hetzner.com/cloud/)

**Example production sizing** (set in `.env` or `.tfvars`):
```sh
CONTROL_SERVER_CLUSTER_SIZE=3
CONTROL_SERVER_TYPE=cx32
API_CLUSTER_SIZE=2
API_SERVER_TYPE=cx42
# Build (template-manager) runs on dedicated servers — list their public IPs:
BUILD_SERVER_IPS=9.10.11.12,13.14.15.16
CLICKHOUSE_CLUSTER_SIZE=1
CLICKHOUSE_SERVER_TYPE=cx42
```

### Secrets

Unlike GCP (Secret Manager) or AWS (Secrets Manager), Hetzner has no managed secrets service. Secrets are:
- Auto-generated by Terraform (random tokens, passwords)
- Stored in Terraform state (encrypted at rest if using S3 backend with encryption)
- Passed to Nomad jobs as environment variables

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

Access the Nomad web UI at `https://nomad.<your-domain>`. Use the Nomad ACL token from your Terraform state for authentication.

---

## Troubleshooting

### Dedicated server not joining the cluster

1. Verify the vSwitch VLAN interface is up:
   ```sh
   ssh root@<dedicated-server-ip> ip addr show | grep 4000
   ```
2. Check routing to the Cloud Network:
   ```sh
   ssh root@<dedicated-server-ip> ip route | grep 10.0
   ```
3. Verify Consul is running and joined:
   ```sh
   ssh root@<dedicated-server-ip> consul members -token=<consul-token>
   ```

### Cloud VMs can't reach dedicated servers

1. Ensure the vSwitch subnet is created in the Cloud Network (check Hetzner Cloud Console > Networks)
2. Verify the vSwitch is attached to the dedicated servers in Robot
3. Check that the VLAN ID matches between Robot vSwitch config and Terraform

### S3/Object Storage errors

1. Verify your S3 endpoint, access key, and secret key in the `.env` file
2. Ensure the Terraform state bucket exists (created manually before `make init`)
3. Check that the MinIO provider can reach the endpoint

### DNS not resolving

1. Ensure your domain's nameservers point to Hetzner DNS
2. Check the Hetzner DNS Console for the wildcard record
3. DNS propagation can take up to an hour

---

## Make Commands Cheat Sheet

- `make init` - initialize Terraform backend and apply init module (network, buckets, secrets)
- `make plan` - plan all Terraform changes
- `make apply` - apply Terraform changes (run `make plan` first)
- `make plan-without-jobs` - plan infrastructure only (no Nomad jobs)
- `make plan-only-jobs` - plan Nomad jobs only
- `make destroy` - destroy the cluster
- `make build-and-upload` - build and push container images and binaries
- `make copy-public-builds` - copy Firecracker kernels and rootfs to your S3 buckets
- `make switch-env ENV={prod,staging,dev}` - switch active environment
