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
  type      = string
  default   = ""
  sensitive = true
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
  description = "Numeric PVE VM ID to assign to the resulting template. The bpg/proxmox Terraform provider clones by VM ID, so this MUST match BASE_TEMPLATE_VM_ID in the Terraform .env. Pick any unused ID (e.g. 9000)."
}

variable "template_storage" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for template disk"
}

variable "disk_format" {
  type        = string
  default     = "raw"
  description = "Disk format for the template disk. Use 'raw' for block-backed storage (local-lvm, local-zfs, ceph-rbd). Use 'qcow2' only for file-based storage (dir, nfs, cifs)."
}

variable "packer_build_bridge" {
  type        = string
  default     = "vmbr0"
  description = "Bridge used during build — must reach the Packer HTTP server + internet"
}

variable "iso_file" {
  type        = string
  description = "Ubuntu 24.04 Server ISO on PVE ISO storage, e.g. local:iso/ubuntu-24.04.1-live-server-amd64.iso"
}

variable "iso_checksum" {
  type        = string
  default     = "none"
  description = "ISO checksum (e.g. sha256:abc...) or 'none' to skip"
}

variable "build_ssh_password" {
  type        = string
  default     = "packer"
  sensitive   = true
  description = "Temporary password used by Packer to SSH during build (matches autoinstall user-data)"
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
