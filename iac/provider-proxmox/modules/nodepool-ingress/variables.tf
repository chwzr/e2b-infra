variable "prefix" {
  type = string
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

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "public_bridge" {
  type = string
}

variable "private_bridge" {
  type = string
}

variable "private_subnet_cidr" {
  type = string
}

variable "private_gateway_ip" {
  type = string
}

variable "private_dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "private_ip_offset" {
  type        = number
  default     = 41
  description = "Private IP offset for the ingress VM (single VM)"
}

variable "public_ip" {
  type        = string
  description = "Public IPv4 for the ingress VM's public NIC"
}

variable "public_gateway" {
  type        = string
  description = "Default gateway on the public bridge"
}

variable "public_cidr_bit" {
  type        = number
  default     = 24
  description = "CIDR mask length for the public IP"
}

variable "node_pool_name" {
  type    = string
  default = "ingress"
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
