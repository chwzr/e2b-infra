variable "prefix" {
  type = string
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

// ---
// Pre-provisioned server IPs per nodepool
// ---

variable "control_server_ips" {
  type = list(string)
}

variable "api_ips" {
  type = list(string)
}

variable "ingress_ips" {
  type = list(string)
}

variable "orchestrator_ips" {
  type = list(string)
}

variable "build_ips" {
  type = list(string)
}

variable "clickhouse_ips" {
  type = list(string)
}

// ---
// Tool versions (passed to setup-base.sh)
// ---

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
}

// ---
// SSH
// ---

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type    = string
  default = ""
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

// ---
// Node pool names
// ---

variable "api_node_pool_name" {
  type = string
}

variable "ingress_node_pool" {
  type = string
}

variable "orchestrator_node_pool_name" {
  type = string
}

variable "build_node_pool_name" {
  type = string
}

variable "clickhouse_node_pool_name" {
  type = string
}

variable "clickhouse_job_constraint_prefix" {
  type = string
}

// ---
// S3 + bucket names for orchestrator/build boot (envd, kernels, firecracker)
// ---

variable "s3_endpoint" {
  type = string
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
  type = string
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "fc_kernels_bucket_name" {
  type = string
}

variable "fc_versions_bucket_name" {
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

variable "registry_auth" {
  type        = string
  default     = ""
  description = "base64(username:password) for the container registry; written into /root/docker/config.json"
}
