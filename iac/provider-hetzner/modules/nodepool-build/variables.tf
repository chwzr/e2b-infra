variable "server_ips" {
  type        = list(string)
  description = "Public IPs of dedicated servers for SSH provisioning"
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "vswitch_vlan_id" {
  type        = number
  default     = 4000
  description = "VLAN ID assigned to the vSwitch in Hetzner Robot (4000-4091)"
}

variable "private_network_range" {
  type        = string
  default     = "10.0.0.0/8"
  description = "Cloud Network IP range (for routing from dedicated servers)"
}

variable "private_subnet_range" {
  type        = string
  default     = "10.0.1.0/24"
  description = "vSwitch subnet range — IPs auto-assigned from this range"
}

variable "ip_offset" {
  type        = number
  default     = 100
  description = "Offset into private_subnet_range for IP allocation — keeps build IPs disjoint from orchestrator IPs on the shared vSwitch VLAN"
}

variable "consul_retry_join_ips" {
  type        = list(string)
  description = "Private IPs of Consul server nodes for retry_join"
}

variable "node_pool_name" {
  type    = string
  default = "build"
}

variable "node_labels" {
  type    = list(string)
  default = []
}

variable "base_hugepages_percentage" {
  type    = number
  default = 70
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
