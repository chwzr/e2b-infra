variable "prefix" {
  type = string
}

variable "cluster_size" {
  type    = number
  default = 3
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

variable "cluster_tag_value" {
  type = string
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

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

variable "datacenter" {
  type    = string
  default = "dc1"
}
