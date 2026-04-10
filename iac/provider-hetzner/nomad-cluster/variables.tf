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
