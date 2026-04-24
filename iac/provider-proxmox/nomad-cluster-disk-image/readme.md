# Proxmox base VM template

Builds the Ubuntu 24.04 VM template that all e2b node-pool VMs clone from.
This flow mirrors the AWS and GCP providers: boot an official cloud image,
run provisioners to install Docker / Consul / Nomad / Vault, snapshot as a
template.

## Prerequisites

- Packer >= 1.8.4 with the `hashicorp/proxmox` plugin
- A Proxmox VE host reachable from the Packer runner
- Either a PVE user/password or an API token with VM + storage privileges
- An SSH keypair — the public key must be baked into the base template
  (see Step 1), and Packer uses the matching private key

## Step 1 — One-time: prepare the cloud-image base template

Run `prepare-base-template.sh` **on the Proxmox host** once. It downloads the
official Ubuntu 24.04 cloud image, creates a VM around it, bakes in your SSH
public key via cloud-init, and converts it to a template.

```sh
# On the PVE host:
scp prepare-base-template.sh root@pve:/tmp/
ssh root@pve

# Defaults: BASE_VM_ID=9001, STORAGE=local-lvm, BRIDGE=vmbr1
# Override any of these before running:
BASE_VM_ID=9001 \
STORAGE=local-zfs \
BRIDGE=vmbr1 \
SSH_PUBKEY=/root/.ssh/e2b-proxmox.pub \
  bash /tmp/prepare-base-template.sh
```

The script prints the base template's VM ID — you'll pass that to Packer.

## Step 2 — Build the e2b template

```sh
packer init .
packer build \
  -var "proxmox_url=https://pve.example.com:8006/api2/json" \
  -var "proxmox_username=root@pam" \
  -var "proxmox_password=..." \
  -var "proxmox_node=pve" \
  -var "template_storage=local-zfs" \
  -var "packer_build_bridge=vmbr1" \
  -var "cloudimg_base_vm_id=9001" \
  -var "vm_id=9000" \
  -var "ssh_private_key_file=$HOME/.ssh/e2b-proxmox" \
  -var "build_ip=10.0.0.99/24" \
  -var "build_gateway=10.0.0.1" \
  .
```

`build_ip` must be an unused address in your cluster subnet; `.99` is safe
with the Terraform defaults (pools use `.11–.13`, `.21+`, `.31+`, `.41`,
`.51+`, `.101+`).

The resulting template's VM ID (here `9000`) goes into `BASE_TEMPLATE_VM_ID`
in your `.env.proxmox.<env>`. The template name (`template_name`, default
`e2b-nomad-cluster`) goes into `BASE_TEMPLATE`.

## What's on the image

- Docker, Consul, Nomad, Vault binaries
- qemu-guest-agent (cloud-init IP reporting back to Proxmox)
- Shared helpers from `iac/nomad-cluster-disk-image/setup/`
- cloud-init reset so clones re-initialise with their own IP / SSH key

## Rebuilding

When the shared setup scripts change, rerun `packer build` — it clones the
base template (Step 1 artifact) again, so you don't need to re-prepare that
unless the cloud image itself needs refreshing.

If you want a different Ubuntu release, re-run `prepare-base-template.sh`
with a different `IMG_URL` and a new `BASE_VM_ID`.
