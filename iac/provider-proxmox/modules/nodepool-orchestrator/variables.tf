variable "prefix" {
  type = string
}

variable "cluster_size" {
  type    = number
  default = 1
}

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

variable "cpu_cores" {
  type    = number
  default = 8
}

variable "memory_mb" {
  type    = number
  default = 16384
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

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

variable "ip_offset" {
  type        = number
  default     = 51
  description = "Private subnet IP offset for orchestrator pool (so .51, .52, ...)"
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

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Optional SSH bastion/jump host for Terraform remote-exec. Leave empty to connect directly (e.g. when terraform runs on the PVE host or from a VPN-connected workstation)."
}

variable "ssh_bastion_user" {
  type    = string
  default = "root"
}

variable "datacenter" {
  type    = string
  default = "dc1"
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

# S3-compatible bucket setup for downloading envd, kernels, firecracker binaries
# onto the VM at boot. All three are required; without them the orchestrator
# can't create sandboxes (template-manager also needs these on the build pool).
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
  type        = string
  description = "S3 bucket hosting service binaries (envd, orchestrator, template-manager, etc.)"
}

variable "fc_kernels_bucket_name" {
  type        = string
  description = "S3 bucket hosting Firecracker guest kernels (vmlinux-*/vmlinux.bin)."
}

variable "fc_versions_bucket_name" {
  type        = string
  description = "S3 bucket hosting Firecracker VMM binaries (vX.Y.Z_abc/firecracker)."
}
