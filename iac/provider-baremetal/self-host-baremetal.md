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
