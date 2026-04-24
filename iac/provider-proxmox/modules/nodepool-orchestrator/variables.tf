variable "prefix" {
  type = string
}

variable "cluster_size" {
  type    = number
  default = 1
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
  default = 8
}

variable "memory_mb" {
  type    = number
  default = 16384
}

variable "disk_size_gb" {
  type    = number
  default = 100
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
  default     = 51
  description = "Private subnet IP offset for orchestrator pool (so .51, .52, ...)"
}

variable "node_pool_name" {
  type    = string
  default = "default"
}

variable "node_labels" {
  type    = list(string)
  default = []
}

variable "base_hugepages_percentage" {
  type    = number
  default = 80
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Optional SSH bastion/jump host for Terraform remote-exec. Leave empty to connect directly (e.g. when terraform runs on the PVE host or from a VPN-connected workstation)."
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_retry_join_ips" {
  type = list(string)
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

variable "consul_gossip_encryption_key" {
  type      = string
  sensitive = true
}

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}

variable "container_registry_url" {
  type    = string
  default = ""
}
