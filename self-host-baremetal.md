# Self-hosting E2B on bare metal

Deploy E2B onto servers you have **already provisioned** — physical machines or
VMs running a clean Ubuntu 24.04 with your SSH key on `root`. There is **no
Packer image and no VM creation**: Terraform connects to each server's private
IP over SSH and configures everything at `apply` time (an idempotent
`setup-base.sh` installs Docker / Consul / Nomad / Vault / qemu-guest-agent,
then a per-role `start-*.sh` configures and starts the agents).

Object storage and Terraform state use Hetzner Object Storage (or any
S3-compatible service). DNS, firewalling, and any public load balancer in front
of the ingress are **your** responsibility — Terraform manages none of them.

## Prerequisites

**Tools** (on the machine you run Terraform from)

- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) (v1.5.x)
  - We ask for v1.5.x because starting from v1.6 Terraform [switched](https://github.com/hashicorp/terraform/commit/b145fbcaadf0fa7d0e7040eac641d9aef2a26433) their license from Mozilla Public License to Business Source License.
  - The last MPL version is **v1.5.7** — binaries [here](https://developer.hashicorp.com/terraform/install/versions#binary-downloads), or via [tfenv](https://github.com/tfutils/tfenv) (`tfenv install 1.5.7 && tfenv use 1.5.7`).
- [Golang](https://go.dev/doc/install)
- [Docker](https://docs.docker.com/engine/install/) with Buildx
- [NPM](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) — used with `--endpoint-url` for S3-compatible uploads (not only AWS)

> No Packer is required — this provider does not build an image.

**The servers**

- **N machines running a clean Ubuntu 24.04**, each with:
  - your deploy **SSH public key on `root`** (`/root/.ssh/authorized_keys`),
  - a **private IP** that the machine running `terraform apply` can reach,
  - **outbound internet** (to pull Docker, Go, apt packages, and the HashiCorp
    binaries during bootstrap).
- **Orchestrator and build** servers must have **hardware virtualization enabled**
  (`/dev/kvm` present — VT-x/AMD-V on in BIOS). `setup-base.sh` aborts a bootstrap
  on those roles if `/dev/kvm` is missing.
- Assign each server's private IP to exactly one node pool (see the table below).
  A minimal cluster is 3 control servers + 1 each of api / ingress / orchestrator
  / build / clickhouse.

**Accounts & Services**

- An S3-compatible object storage (Hetzner Object Storage or self-hosted MinIO)
  with an **already-provisioned** bucket for Terraform state.
- A domain whose DNS you control — any provider; Terraform does not manage DNS.
- A PostgreSQL database (Supabase's Postgres only supported for now).
- A Docker container registry reachable from inside the private network (Harbor,
  `ghcr.io`, Docker Hub, etc.).

**Optional** — recommended for monitoring and logging: a Grafana Cloud account & stack.

---

## Architecture Overview

Every node pool is just a list of pre-existing servers, addressed by private IP.
The single private IP per server is used for **both** SSH bootstrap and
Consul/Nomad advertise + retry-join.

```
Your network (private, reachable from the Terraform host)
   ├── control_server_ips   Control servers (Nomad/Consul)        e.g. 10.0.0.10-12
   ├── api_ips              API, client-proxy, OTEL, Loki, logs    e.g. 10.0.0.20
   ├── ingress_ips          Traefik ingress (single)              e.g. 10.0.0.30
   ├── orchestrator_ips     Firecracker sandbox runner  (/dev/kvm) e.g. 10.0.0.40
   ├── build_ips            Template-manager           (/dev/kvm)  e.g. 10.0.0.50
   └── clickhouse_ips       Analytics DB                          e.g. 10.0.0.60

Internet ──▶ (your LB / DNAT / public IP) ──▶ ingress server :8080 (Traefik)
```

**Node Pools**

| Pool             | Role                                                              | Needs `/dev/kvm` |
|------------------|------------------------------------------------------------------|------------------|
| `control-server` | Nomad + Consul servers                                            | no   |
| `api`            | API, client-proxy, OTEL, Loki, logs collector                    | no   |
| `ingress`        | Traefik only — terminates all external traffic (listens on :8080) | no  |
| `orchestrator`   | Firecracker sandbox runner                                       | **yes** |
| `build`          | Template-manager (builds sandbox templates with Firecracker)     | **yes** |
| `clickhouse`     | Analytics DB (data dir `/clickhouse/data` on the root filesystem) | no  |

Traffic flow: client → DNS → your public entrypoint (an LB, a DNAT, or the
ingress server's own public IP) → Traefik on the ingress server (`:8080`) →
internal service via Consul Catalog over the private network.

> **External ingress is yours to wire.** Unlike the Proxmox provider (where the
> PVE host DNATs 80/443 to the ingress VM), bare metal has no such host. Point
> public 80/443 at the ingress server's `:8080` yourself — via a load balancer,
> an `iptables`/nginx DNAT, or by giving the ingress server a public IP. See
> Step 6.

---

## Step 1: Prepare the Servers and External Resources

### 1.1 Servers

For each machine that will join the cluster:

1. Install a clean **Ubuntu 24.04**.
2. Put your deploy SSH **public** key on `root` (e.g. cloud-init, or
   `ssh-copy-id`). Confirm `ssh -i <key> root@<private-ip> true` works from the
   Terraform host.
3. Ensure the machine has **outbound internet** and a **private IP** reachable
   from the Terraform host.
4. On **orchestrator** and **build** servers, enable virtualization in BIOS and
   verify `/dev/kvm` exists:
   ```sh
   ssh root@<orchestrator-ip> 'ls -l /dev/kvm && egrep -c "(vmx|svm)" /proc/cpuinfo'
   ```

No other preparation is needed — `setup-base.sh` installs everything else at
deploy time.

### 1.2 S3-compatible object storage

1. Create Object Storage credentials (Access Key + Secret Key) in Hetzner (or your MinIO).
2. Note the endpoint (e.g. `fsn1.your-objectstorage.com`) and region (e.g. `fsn1`).
3. **Pre-create** a bucket for Terraform state (e.g. `e2b-terraform-state`). The
   runtime buckets (kernels, templates, loki, etc.) are created by `make init`.

### 1.3 Domain / DNS

Terraform does **not** manage DNS. Pick any provider. You'll create a single
wildcard A record later (Step 6) pointing at your public ingress entrypoint.

### 1.4 Container registry

A Docker registry to host the service images (self-hosted Harbor/Distribution/Zot,
`ghcr.io`, or Docker Hub). It must be reachable from **inside** the private
network. Log in from your dev machine (`docker login <registry>`) so
`make build-and-upload` can push. Its URL becomes `CONTAINER_REGISTRY_URL`.

### 1.5 SSH key

Reuse (or generate) the key pair whose **public** half is already on `root` of
every server:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/e2b-baremetal -C "e2b-cluster"
```

You'll reference the **private** key via `SSH_PRIVATE_KEY` (a path is preferred).
There is **no** `SSH_PUBLIC_KEY` variable — the public key must already be on the
servers (Step 1.1).

> **Important:** `terraform apply` SSHes to each server's private IP to bootstrap
> it. Run it from somewhere with reachability to the private network — a VPN /
> WireGuard / Tailscale workstation, a jump host (`SSH_BASTION_HOST`), or a
> machine on that network.

---

## Step 2: Configure Environment

Two files drive the deploy: the `.env.<env>` (scalars + secrets) and the
Terraform var-file (the per-pool IP **lists**).

1. Create `.env.prod`, `.env.staging`, or `.env.dev` from
   [`.env.baremetal.template`](.env.baremetal.template):

   ```sh
   PROVIDER=baremetal
   DOMAIN_NAME=<your-domain.com>
   CONTAINER_REGISTRY_URL=<registry.example.com>

   # S3-compatible storage (already-provisioned state bucket + runtime buckets)
   S3_ENDPOINT=<fsn1.your-objectstorage.com>
   S3_ACCESS_KEY=<your-access-key>
   S3_SECRET_KEY=<your-secret-key>
   S3_REGION=<fsn1>
   S3_BUCKET=<e2b-terraform-state>

   # SSH (path to the private key; matching public key already on root@ servers)
   SSH_PRIVATE_KEY=~/.ssh/e2b-baremetal
   # SSH_BASTION_HOST=        # optional jump host if the Terraform host isn't on the private net
   # SSH_BASTION_USER=root

   # App secrets
   POSTGRES_CONNECTION_STRING=<from-supabase-or-other>
   SUPABASE_JWT_SECRETS=<from-supabase>
   ```

   > Get the PostgreSQL connection string from your database provider, e.g.
   > [from Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres#direct-connection).

2. Create the Terraform var-file with your per-pool private IPs. Copy the example
   and fill it in:

   ```sh
   cp iac/provider-baremetal/.terraform.example.tfvars \
      iac/provider-baremetal/.terraform.<env>.tfvars   # <env> = prod | staging | dev
   ```

   ```hcl
   control_server_ips = ["10.0.0.10", "10.0.0.11", "10.0.0.12"]
   api_ips            = ["10.0.0.20"]
   ingress_ips        = ["10.0.0.30"]
   orchestrator_ips   = ["10.0.0.40"]
   build_ips          = ["10.0.0.50"]
   clickhouse_ips     = ["10.0.0.60"]
   ```

   Cluster sizes are derived from the length of each list. The Makefile passes
   this file to every `plan`/`apply`/`init` via `-var-file` automatically; it
   must exist before Step 3.

3. Activate the environment:

   ```sh
   PROVIDER=baremetal make switch-env ENV=prod   # or staging / dev
   ```

---

## Step 3: Initialize Infrastructure

```sh
PROVIDER=baremetal make init
```

This:
- Configures the Terraform S3 backend against your pre-created state bucket.
- Applies the `init` module, which creates the runtime S3 buckets (templates,
  kernels, fc-versions, env-pipeline, build-cache, loki, clickhouse-backups)
  and generates the Consul/Nomad ACL tokens + gossip key (stored in Terraform
  state, exposed as outputs to the rest of the stack).

---

## Step 4: Build and Upload Artifacts

```sh
PROVIDER=baremetal make build-and-upload
```

Builds and pushes every service container image to `CONTAINER_REGISTRY_URL` and
uploads the Firecracker-side binaries (`orchestrator`, `template-manager`,
`envd`, `clean-nfs-cache`, `nomad-nodepool-apm`) to your S3 `fc-env-pipeline`
bucket via `aws s3 cp --endpoint-url`.

```sh
PROVIDER=baremetal make copy-public-builds
```

Copies the public Firecracker kernels and rootfs builds into your `fc-kernels`
and `fc-versions` buckets. On first boot each orchestrator/build server
downloads these from S3 (there is no FUSE mount of GCS as on the GCP provider).

---

## Step 5: Deploy Infrastructure

```sh
PROVIDER=baremetal make plan-without-jobs
PROVIDER=baremetal make apply
```

This bootstraps, in order:
- **Control servers** — Consul + Nomad servers, via SSH (`setup-base.sh` install
  + `start-server.sh`).
- **api, ingress, orchestrator, build, clickhouse** — each runs `setup-base.sh`
  for its role then its `start-*.sh`, joining the Consul cluster using the
  control servers' private IPs (`consul_retry_join`).

> **First-bootstrap Nomad address.** The Nomad Terraform provider defaults to
> `https://nomad.$DOMAIN_NAME`, which is served by Traefik — and Traefik is
> itself a Nomad job that isn't running yet. For the first deploy, open a tunnel
> to a control server and point Terraform at it:
> ```sh
> ssh -L 4646:localhost:4646 root@<control_server_ip>     # leave running
> # in another shell:
> NOMAD_ADDRESS=http://localhost:4646 PROVIDER=baremetal make apply
> ```
> (or set `NOMAD_ADDRESS` in `.env.<env>`). After Traefik is up you can drop it.

Terraform must be able to SSH to each server's private IP (Step 1.5 note).

---

## Step 6: Expose the Ingress + Create the Wildcard DNS Record

After `apply` finishes, Terraform prints the ingress server's private IP:

```
ingress_private_ip = "10.0.0.30"
```

Traefik listens on **`:8080`** on that server. Bare metal has no managed
front-end, so route public HTTPS to it yourself — pick one:

- **Public IP on the ingress server:** add an `iptables` DNAT for 80/443 → `:8080`,
  or run Traefik directly on 80/443.
  ```sh
  # on the ingress server, if it has a public NIC
  iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 8080
  iptables -t nat -A PREROUTING -p tcp --dport 80  -j REDIRECT --to-ports 8080
  ```
- **External load balancer** (cloud LB, HAProxy, nginx) forwarding 80/443 to
  `<ingress-private-ip>:8080`.

Then create a wildcard A record at your DNS provider pointing at that public
entrypoint:

```
*.<your-domain>    A    <public-entrypoint-ip>    300
```

Verify:
```sh
dig +short anything.<your-domain>            # your public entrypoint
curl -vk https://<public-entrypoint-ip>      # should hit Traefik on the ingress server
```

---

## Step 7: Deploy Nomad Jobs

```sh
PROVIDER=baremetal make plan
PROVIDER=baremetal make apply
```

Deploys all Nomad jobs: API, Traefik ingress (pinned to the ingress server),
client-proxy, orchestrator, template-manager, ClickHouse, Loki, OTEL collector,
logs-collector, and Redis (unless you set `REDIS_MANAGED=true`).

Database migrations run automatically via the API's `db-migrator` task the first
time it comes up.

---

## Step 8: Initial Setup

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

## Bare-metal Architecture Details

### Terraform "provider"

There is no cloud/hypervisor provider — each node pool module is a `null_resource`
per supplied IP that connects over SSH (`user = "root"`) and runs a two-phase
bootstrap:

1. Upload the shared `iac/nomad-cluster-disk-image/setup/` directory and run
   `setup-base.sh <role>` — idempotent install of Docker, Go, gruntwork
   bash-commons, Consul/Nomad/Vault (pinned versions), qemu-guest-agent, and
   limits/conntrack tuning. For `orchestrator`/`build` it asserts `/dev/kvm`.
2. Upload and run the role's templated `start-<role>.sh`, which writes the Consul
   + Nomad agent config (advertising the server's private IP) and starts them.

A server is re-bootstrapped on `apply` only when its IP, `setup-base.sh`, or its
`start-*.sh` changes (the `null_resource` triggers). The `init` (S3 + secrets)
and `nomad` (job) modules are shared verbatim with the other providers.

### Networking

- **One private IP per server** (`*_ips` lists) is used for SSH and for
  Consul/Nomad `advertise` + `retry_join`. The Terraform host must reach this
  network (directly, VPN, or `SSH_BASTION_HOST`).
- **Service discovery:** Consul DNS (`.service.consul`). Each server points
  `/etc/systemd/resolved.conf.d/consul.conf` at Consul's local listener on 8600.
- **External ingress:** not managed — you route public 80/443 to the ingress
  server's `:8080` (Step 6).
- **No firewall management:** restrict the cluster ports (Consul
  8300/8301/8500/8600, Nomad 4646–4648) to the private network yourself.

### Storage

- **S3-compatible Object Storage:** templates, kernels, Firecracker versions,
  build cache, Loki logs, ClickHouse backups, and all binary artifacts.
- **ClickHouse data:** a plain directory `/clickhouse/data` on the server's root
  filesystem (there is no dedicated second disk as on Proxmox). If you have a
  separate data volume, mount it at `/clickhouse` before `terraform apply`.
- **tmpfs:** 65 GB snapshot cache + 100 GB swapfile on orchestrator servers
  (created by `start-orchestrator.sh` — ensure the root filesystem has room).

### Server sizing

There are no CPU/RAM/disk variables — each server is whatever hardware you
provisioned. Right-size the machines before adding them to a pool:

| Pool           | Suggested minimum | Notes |
|----------------|-------------------|-------|
| control-server | 2 vCPU / 4 GB     | odd count (3) for Raft quorum |
| api            | 2 vCPU / 4 GB     | add IPs to `api_ips` for HA |
| ingress        | 2 vCPU / 2 GB     | single server |
| orchestrator   | 8+ vCPU / 16+ GB / 100+ GB disk | `/dev/kvm`; sizes cap sandboxes/host |
| build          | 8+ vCPU / 16+ GB / 100+ GB disk | `/dev/kvm` |
| clickhouse     | 4 vCPU / 8 GB     | data on root fs (`/clickhouse/data`) |

To scale a pool, add or remove IPs in `.terraform.<env>.tfvars` and re-run
`make plan` / `apply` — new servers are bootstrapped, removed ones have their
`null_resource` destroyed (the OS itself is not touched).

### Tool versions & upgrades

`CONSUL_VERSION` / `NOMAD_VERSION` / `VAULT_VERSION` (defaults 1.16.2 / 1.6.2 /
1.20.3) are installed at **first** bootstrap. Because `setup-base.sh` guards
installs by `command -v`, bumping a version in `.env` does **not** upgrade an
already-provisioned server — upgrades are a manual operation (or reprovision the
host). Changing the version vars alone won't even re-run the bootstrap (the
triggers key on the scripts + IP, not the versions).

### Secrets

No managed secrets service — secrets are auto-generated by Terraform (Consul/Nomad
ACL tokens, gossip key, ClickHouse password, API secret, admin token, sandbox
access token seed), stored in Terraform state (encrypt at rest at the S3 layer),
and passed to Nomad jobs as env vars and to the bootstrap scripts via the `file`
+ `remote-exec` provisioners. The `module.nomad` uses `provider_name = "hetzner"`
because the shared job modules (S3-compatible storage + custom registry) are
functionally identical for bare metal.

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

`https://nomad.<your-domain>` — Traefik routes it through the ingress server to
the control servers. Use the Nomad ACL token from Terraform state
(`terraform output -raw` on the `init` module) for login.

---

## Troubleshooting

### Terraform can't SSH to a server during `apply`

You need SSH reachability to the private network. Options:
- Run `terraform apply` from a host on that network.
- Connect via WireGuard / Tailscale / OpenVPN.
- Set `SSH_BASTION_HOST` / `SSH_BASTION_USER` to route through a jump host.
- Confirm the key: `ssh -i $SSH_PRIVATE_KEY root@<private-ip> true`.

### `setup-base.sh` aborts with "/dev/kvm missing"

The orchestrator/build server has no usable virtualization. Enable VT-x/AMD-V in
BIOS, then verify `ls -l /dev/kvm` and `egrep -c "(vmx|svm)" /proc/cpuinfo` on
that server. (If these are VMs, the hypervisor must expose nested virtualization.)

### A server comes up but doesn't join Consul

1. SSH in (`ssh -i $SSH_PRIVATE_KEY root@<private-ip>`).
2. `systemctl status consul` and `tail -f /var/log/start-*.log` /
   `/var/log/setup-base.log`.
3. `cat /opt/consul/config/default.json | jq .retry_join` — must list your
   control server private IPs.
4. `nc -vz <control-ip> 8301` to check gossip connectivity.

### Bootstrap fails downloading packages

`setup-base.sh` needs outbound internet (apt, `get.docker.com`, Go, HashiCorp,
GitHub for bash-commons). A transient failure aborts `apply`; re-running is safe
(the script is idempotent). Confirm the server can reach the internet and your
registry: `ssh root@<ip> 'curl -fsI https://get.docker.com >/dev/null && echo ok'`.

### External traffic doesn't reach the ingress

The ingress server only listens on `:8080`. Confirm your public entrypoint
forwards 80/443 there (Step 6), then from the Terraform host:
```sh
curl -vk http://<ingress-private-ip>:8080/ping     # Traefik should answer
```
If that fails, SSH to the ingress server and check the Nomad job: `nomad job status ingress`.

### S3 / Object Storage errors

1. Verify endpoint, access key, secret key in `.env`.
2. `aws s3 ls --endpoint-url https://$S3_ENDPOINT s3://$S3_BUCKET/` should
   succeed from wherever you run `terraform apply`.
3. Ensure the state bucket exists (pre-created, not managed by Terraform).

### Docker image pulls fail on the servers

1. Confirm `CONTAINER_REGISTRY_URL` is reachable from a server:
   `ssh root@<private-ip> curl -I https://<registry-url>/v2/`.
2. Check `/root/docker/config.json` on the server — it should contain an `auths`
   entry for your registry (populated by the bootstrap script). If empty,
   `CONTAINER_REGISTRY_URL` was likely blank in `.env`.

### `make init` fails with "No value for required variable"

The per-pool IP lists live in `iac/provider-baremetal/.terraform.<env>.tfvars`,
which must exist before `make init`/`plan`/`apply` (Step 2.2). Confirm the file
is present and named for the active `ENV`.

---

## Make Commands Cheat Sheet

All commands below should be prefixed with `PROVIDER=baremetal` (or exported once
per shell).

- `make switch-env ENV={prod,staging,dev}` — switch active environment
- `make init` — initialize Terraform backend, create runtime buckets and secrets
- `make build-and-upload` — build and push service images; upload binaries to S3
- `make copy-public-builds` — copy Firecracker kernels and rootfs to your S3 buckets
- `make plan-without-jobs` — plan infrastructure only (no Nomad jobs)
- `make plan` — plan all Terraform changes
- `make plan-only-jobs` — plan Nomad jobs only
- `make apply` — apply Terraform changes (run a `plan` first)
- `make destroy` — tear down (removes the bootstrap null_resources + buckets; does not wipe the servers' OS)
