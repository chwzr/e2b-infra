variable "prefix" {
  type = string
}

variable "cluster_size" {
  type    = number
  default = 1
}

variable "server_type" {
  type    = string
  default = "cx32"
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "location" {
  type    = string
  default = "fsn1"
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

variable "node_pool_name" {
  type    = string
  default = "api"
}

variable "cluster_tag_value" {
  type = string
}

variable "hcloud_token" {
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

variable "datacenter" {
  type    = string
  default = "dc1"
}
