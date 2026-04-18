variable "prefix" {
  type = string
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

// ---
// Proxmox target
// ---

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

// ---
// Networking
// ---

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

// ---
// SSH
// ---

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

// ---
// Control Server
// ---

variable "control_server_cluster_size" {
  type = number
}

variable "control_server_cpu_cores" {
  type = number
}

variable "control_server_memory_mb" {
  type = number
}

variable "control_server_disk_size_gb" {
  type = number
}

// ---
// API
// ---

variable "api_cluster_size" {
  type = number
}

variable "api_cpu_cores" {
  type = number
}

variable "api_memory_mb" {
  type = number
}

variable "api_disk_size_gb" {
  type = number
}

variable "api_node_pool_name" {
  type = string
}

// ---
// Ingress
// ---

variable "ingress_cpu_cores" {
  type = number
}

variable "ingress_memory_mb" {
  type = number
}

variable "ingress_disk_size_gb" {
  type = number
}

variable "ingress_node_pool" {
  type = string
}

// ---
// Orchestrator
// ---

variable "orchestrator_cluster_size" {
  type = number
}

variable "orchestrator_cpu_cores" {
  type = number
}

variable "orchestrator_memory_mb" {
  type = number
}

variable "orchestrator_disk_size_gb" {
  type = number
}

variable "orchestrator_node_pool_name" {
  type = string
}

// ---
// Build
// ---

variable "build_cluster_size" {
  type = number
}

variable "build_cpu_cores" {
  type = number
}

variable "build_memory_mb" {
  type = number
}

variable "build_disk_size_gb" {
  type = number
}

variable "build_node_pool_name" {
  type = string
}

// ---
// ClickHouse
// ---

variable "clickhouse_cluster_size" {
  type = number
}

variable "clickhouse_cpu_cores" {
  type = number
}

variable "clickhouse_memory_mb" {
  type = number
}

variable "clickhouse_disk_size_gb" {
  type = number
}

variable "clickhouse_data_volume_size_gb" {
  type = number
}

variable "clickhouse_node_pool_name" {
  type = string
}

variable "clickhouse_job_constraint_prefix" {
  type = string
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

variable "container_registry_url" {
  type    = string
  default = ""
}
