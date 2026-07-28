variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve.example.com:8006/api2/json"
}

variable "proxmox_username" {
  type    = string
  default = ""
}

variable "proxmox_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "proxmox_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Proxmox API token (use either user/password OR token)"
}

variable "proxmox_tls_insecure" {
  type    = bool
  default = false
}

variable "proxmox_node" {
  type        = string
  description = "PVE node where the template is built"
}

variable "template_name" {
  type        = string
  default     = "e2b-nomad-cluster"
  description = "Name of the resulting VM template — referenced as var.base_template in Terraform"
}

variable "vm_id" {
  type        = number
  description = "Numeric PVE VM ID for the resulting template. MUST match BASE_TEMPLATE_VM_ID in the Terraform .env. Pick any unused ID (e.g. 9000)."
}

variable "cloudimg_base_vm_id" {
  type        = number
  description = "Numeric PVE VM ID of the Ubuntu 24.04 cloud-image BASE template (created once via prepare-base-template.sh). Packer clones from this ID. Typically 9001."
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the SSH private key file Packer uses to connect to the build VM. The matching public key must be baked into the base template via `qm set --sshkeys` (see prepare-base-template.sh)."
}

variable "template_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool used for the cloud-init CD and any cloned disks. Usually the same pool the base template lives on."
}

variable "packer_build_bridge" {
  type        = string
  default     = "vmbr1"
  description = "Bridge used by the temporary clone during build. It must reach the internet (for Docker / Go / apt) — so use whichever bridge on your PVE host has outbound NAT (typically the cluster bridge, since the PVE host masquerades egress)."
}

# The cluster bridge has no DHCP (all node-pool VMs get static IPs via Terraform),
# so the Packer builder also needs a static IP to be reachable. Pick any unused
# address in your subnet outside the per-pool offset ranges (e.g. .99).
variable "build_ip" {
  type        = string
  description = "Static IPv4 (CIDR notation) assigned to the temporary Packer build VM, e.g. 10.0.0.99/24. Must be in the same subnet as the build bridge and not conflict with any node-pool IP."
}

variable "build_gateway" {
  type        = string
  description = "IPv4 gateway for the build VM (typically the PVE host on the cluster bridge, e.g. 10.0.0.1)."
}

variable "build_nameserver" {
  type        = string
  default     = "1.1.1.1"
  description = "DNS server the build VM uses (before any cluster-level Consul DNS exists)."
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Bastion / jump host for SSH to the build VM. Set this to the PVE host's reachable address (e.g. pve.example.com) when running Packer from outside the cluster subnet. Leave empty when running Packer on the PVE host itself or from a VPN-connected workstation."
}

variable "ssh_bastion_port" {
  type    = number
  default = 22
}

variable "ssh_bastion_username" {
  type    = string
  default = "root"
}

variable "ssh_bastion_private_key_file" {
  type        = string
  default     = ""
  description = "Path to the private key for SSH bastion auth. If empty, falls back to ssh_private_key_file."
}

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
