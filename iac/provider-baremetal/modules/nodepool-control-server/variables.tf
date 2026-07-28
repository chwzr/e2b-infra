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
