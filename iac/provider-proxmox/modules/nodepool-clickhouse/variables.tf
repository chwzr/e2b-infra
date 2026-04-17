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

variable "cpu_cores" {
  type    = number
  default = 4
}

variable "memory_mb" {
  type    = number
  default = 8192
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "data_volume_size_gb" {
  type    = number
  default = 100
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

variable "ip_offset" {
  type        = number
  default     = 31
  description = "Private subnet IP offset for ClickHouse pool (so .31, .32, ...)"
}

variable "node_pool_name" {
  type    = string
  default = "clickhouse"
}

variable "job_constraint_prefix" {
  type    = string
  default = "clickhouse"
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
