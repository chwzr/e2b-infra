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
  default = "ingress"
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
