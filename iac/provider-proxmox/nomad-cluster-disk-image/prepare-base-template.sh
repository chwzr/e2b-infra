#!/usr/bin/env bash
#
# One-time setup: import the Ubuntu 24.04 cloud image and turn it into a base
# VM template that Packer then clones from. Run this ONCE on the Proxmox host.
#
# Env vars (override as needed):
#   BASE_VM_ID    PVE VM ID for the base template                    (default 9001)
#   STORAGE       Proxmox storage pool for the disk + cloud-init CD  (default local-lvm)
#   BRIDGE        Bridge the temporary builder uses                   (default vmbr1)
#   SSH_PUBKEY    Path to the SSH public key to bake in               (default /root/.ssh/e2b-proxmox.pub)
#   IMG_URL       URL to the cloud image                              (default Ubuntu noble stable)
#
# The same SSH key whose public half goes in via --sshkeys below is what
# Packer uses (ssh_private_key_file) to connect during the build.

set -euo pipefail

BASE_VM_ID="${BASE_VM_ID:-9001}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr1}"
SSH_PUBKEY="${SSH_PUBKEY:-/root/.ssh/e2b-proxmox.pub}"
IMG_URL="${IMG_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"

IMG_PATH="/tmp/noble-cloudimg-$$.img"

if ! command -v qm >/dev/null; then
  echo "ERROR: this script must run on a Proxmox VE host (qm CLI not found)." >&2
  exit 1
fi

if [[ ! -f "$SSH_PUBKEY" ]]; then
  echo "ERROR: SSH public key not found at $SSH_PUBKEY" >&2
  echo "Set SSH_PUBKEY=/path/to/your/key.pub and try again." >&2
  exit 1
fi

if qm status "$BASE_VM_ID" >/dev/null 2>&1; then
  echo "ERROR: VM $BASE_VM_ID already exists. Destroy it first (qm destroy $BASE_VM_ID) or pick a different BASE_VM_ID." >&2
  exit 1
fi

echo "==> Downloading cloud image → $IMG_PATH"
curl -fsSL --retry 3 -o "$IMG_PATH" "$IMG_URL"
trap 'rm -f "$IMG_PATH"' EXIT

echo "==> Creating VM $BASE_VM_ID"
qm create "$BASE_VM_ID" \
  --name ubuntu-24.04-cloudimg-base \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --net0 "virtio,bridge=$BRIDGE" \
  --scsihw virtio-scsi-pci \
  --ostype l26 \
  --agent enabled=1

echo "==> Importing disk into $STORAGE"
qm importdisk "$BASE_VM_ID" "$IMG_PATH" "$STORAGE"

# importdisk attaches the new disk as an unused slot; the name it picks depends
# on storage type (vm-<id>-disk-0 for ZFS/LVM, <id>/vm-<id>-disk-0.* for dir).
# Re-attach from the unused slot, agnostic to disk naming:
DISK_REF=$(qm config "$BASE_VM_ID" | awk '/^unused0:/ {print $2}')
if [[ -z "$DISK_REF" ]]; then
  echo "ERROR: could not find imported disk on $BASE_VM_ID" >&2
  exit 1
fi

echo "==> Attaching $DISK_REF as scsi0"
qm set "$BASE_VM_ID" --scsi0 "$DISK_REF,iothread=1"
qm set "$BASE_VM_ID" --boot c --bootdisk scsi0

echo "==> Adding cloud-init drive"
qm set "$BASE_VM_ID" --ide2 "$STORAGE:cloudinit"

echo "==> Serial console (cloud images expect this)"
qm set "$BASE_VM_ID" --serial0 socket --vga serial0

echo "==> Baking in SSH key + default user (cloud-init)"
qm set "$BASE_VM_ID" --ciuser ubuntu --sshkeys "$SSH_PUBKEY"

echo "==> Resizing root disk to 20G"
qm resize "$BASE_VM_ID" scsi0 20G

echo "==> Converting to template"
qm template "$BASE_VM_ID"

cat <<EOF

DONE.

Base template VM ID: $BASE_VM_ID
  → pass this as -var "cloudimg_base_vm_id=$BASE_VM_ID" to \`packer build\`

Packer SSHes in as 'ubuntu' with the private key matching:
  $SSH_PUBKEY
  → pass this as -var "ssh_private_key_file=\$HOME/.ssh/<matching-private-key>"
EOF
