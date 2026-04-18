variable "prefix" {
  type = string
}

variable "cluster_size" {
  type    = number
  default = 3
}

variable "pve_node" {
  type = string
}

variable "pve_storage_pool" {
  type = string
}

variable "base_template" {
  type = string
}

variable "base_template_vm_id" {
  type = number
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "bridge" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "gateway_ip" {
  type = string
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "ip_offset" {
  type        = number
  default     = 11
  description = "First usable IP offset in private subnet for this pool (so IPs become .11, .12, .13)"
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "nomad_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}
