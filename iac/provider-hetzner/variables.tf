variable "domain_name" {
  type = string
}

variable "prefix" {
  type        = string
  description = "Name prefix for all resources"
}

variable "environment" {
  type = string
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for cluster node access"
}

variable "container_registry_url" {
  type        = string
  description = "URL of the custom container registry"
  default     = ""
}

// ---
// S3-compatible Object Storage
// ---

variable "s3_endpoint" {
  type        = string
  description = "Hetzner Object Storage endpoint (e.g. fsn1.your-objectstorage.com)"
}

variable "s3_access_key" {
  type      = string
  sensitive = true
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "s3_region" {
  type    = string
  default = "fsn1"
}

// ---
// Location / Datacenter
// ---

variable "location" {
  type        = string
  description = "Hetzner Cloud location (fsn1, nbg1, hel1, ash, hil)"
  default     = "fsn1"
}

variable "network_zone" {
  type        = string
  description = "Hetzner Cloud network zone (eu-central, us-east, us-west)"
  default     = "eu-central"
}

variable "datacenter" {
  type        = string
  description = "Consul/Nomad datacenter name"
  default     = "dc1"
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

// ---
// Stubs for future node pools (unused in step 1)
// ---

variable "api_cluster_size" {
  type    = number
  default = 1
}

variable "api_server_type" {
  type    = string
  default = "cx32"
}

variable "client_cluster_size" {
  type    = number
  default = 1
}

variable "client_server_type" {
  type    = string
  default = "cx52"
}

variable "build_cluster_size" {
  type    = number
  default = 1
}

variable "build_server_type" {
  type    = string
  default = "cx42"
}

variable "clickhouse_cluster_size" {
  type    = number
  default = 1
}

variable "clickhouse_server_type" {
  type    = string
  default = "cx32"
}

variable "redis_managed" {
  type    = bool
  default = false
}

variable "ingress_count" {
  type    = number
  default = 1
}

variable "client_proxy_count" {
  type    = number
  default = 1
}

// ---
// Orchestrator (Hetzner Dedicated Servers)
// ---

variable "vswitch_id" {
  type        = number
  default     = null
  description = "Hetzner Robot vSwitch ID for connecting dedicated servers to Cloud Network"
}

variable "vswitch_vlan_id" {
  type        = number
  default     = 4000
  description = "VLAN ID assigned to the vSwitch in Hetzner Robot (4000-4091)"
}

variable "orchestrator_server_ips" {
  type        = list(string)
  default     = []
  description = "Public IPs of dedicated servers for SSH provisioning"
}

variable "orchestrator_ssh_private_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "SSH private key for dedicated server access"
}

variable "consul_retry_join_ips" {
  type        = list(string)
  default     = []
  description = "Private IPs of Consul server nodes for dedicated server retry_join"
}
