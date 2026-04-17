# Proxmox base VM template

Builds the Ubuntu 24.04 VM template that all e2b node pool VMs clone from.

## Prerequisites

- Packer >= 1.8.4 with the `hashicorp/proxmox` plugin
- A Proxmox VE host reachable from the Packer runner
- Ubuntu 24.04 Server ISO uploaded to the PVE ISO storage, e.g.
  `local:iso/ubuntu-24.04.1-live-server-amd64.iso`
- Either a PVE user/password or an API token with VM+ISO+storage privileges

## Build

```sh
packer init .
packer build \
  -var "proxmox_url=https://pve.example.com:8006/api2/json" \
  -var "proxmox_username=root@pam" \
  -var "proxmox_password=..." \
  -var "proxmox_node=pve" \
  -var "iso_file=local:iso/ubuntu-24.04.1-live-server-amd64.iso" \
  -var "template_storage=local-lvm" \
  .
```

The resulting template name is passed into Terraform via `TF_VAR_base_template`
(or the `BASE_TEMPLATE` value in `.env.proxmox`).

## What's on the image

- Docker, Consul, Nomad, Vault binaries
- qemu-guest-agent (cloud-init IP reporting back to Proxmox)
- Shared helpers from `iac/nomad-cluster-disk-image/setup/`
- cloud-init reset so clones can re-initialise with their own config

## Rebuilding

When the shared setup scripts change, rebuild the template and update
`BASE_TEMPLATE` in `.env.proxmox` to the new timestamped VM name — then
`terraform apply` will recreate VMs from the new template.
