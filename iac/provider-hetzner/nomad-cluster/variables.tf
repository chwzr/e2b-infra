variable "prefix" {
  type = string
}

variable "location" {
  type    = string
  default = "fsn1"
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "network_id" {
  type = number
}

variable "ssh_key_id" {
  type = number
}

variable "firewall_ids" {
  type    = list(number)
  default = []
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

// ---
// Control Server
// ---

variable "control_server_cluster_size" {
  type    = number
  default = 3
}

variable "control_server_type" {
  type    = string
  default = "cx32"
}

variable "server_image" {
  type    = string
  default = "ubuntu-24.04"
}

// ---
// API Node Pool
// ---

variable "api_cluster_size" {
  type    = number
  default = 1
}

variable "api_server_type" {
  type    = string
  default = "cx32"
}

variable "api_node_pool_name" {
  type    = string
  default = "api"
}

variable "container_registry_url" {
  type    = string
  default = ""
}

// ---
// Build Node Pool
// ---

variable "build_cluster_size" {
  type    = number
  default = 1
}

variable "build_server_type" {
  type    = string
  default = "ccx33"
}

variable "build_node_pool_name" {
  type    = string
  default = "build"
}

variable "build_node_labels" {
  type    = list(string)
  default = []
}

// ---
// ClickHouse Node Pool
// ---

variable "clickhouse_cluster_size" {
  type    = number
  default = 1
}

variable "clickhouse_server_type" {
  type    = string
  default = "cx32"
}

variable "clickhouse_node_pool_name" {
  type    = string
  default = "clickhouse"
}

variable "clickhouse_job_constraint_prefix" {
  type    = string
  default = "clickhouse"
}

// ---
// Cluster secrets
// ---

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

variable "consul_dns_request_token" {
  type      = string
  sensitive = true
}
