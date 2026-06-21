variable "prefix" {
  type = string
}

variable "private_ips" {
  type = list(string)
}

variable "datacenter" {
  type    = string
  default = "dc1"
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

variable "vault_version" {
  type = string
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
