variable "domain_name" {
  type        = string
  description = "Domain name used for Traefik Host routing and service URLs. DNS records are created manually (not by Terraform). Point *.<domain_name> at the PVE host's public IP (the host DNATs 80/443 to the ingress VM)."
}

variable "prefix" {
  type        = string
  description = "Name prefix for all resources"
}

variable "environment" {
  type = string
}

variable "datacenter" {
  type        = string
  description = "Consul/Nomad datacenter name"
  default     = "dc1"
}

// ---
// Proxmox provider
// ---

variable "proxmox_api_url" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve.example.com:8006/api2/json"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "Proxmox API token ID (format: user@realm!token_name)"
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_tls_insecure" {
  type        = bool
  default     = false
  description = "Skip TLS verification when talking to the Proxmox API"
}

variable "pve_node" {
  type        = string
  description = "Target PVE node name (single-host deployment)"
}

variable "pve_storage_pool" {
  type        = string
  description = "Proxmox storage pool where VM disks are created, e.g. local-lvm, local-zfs, ceph"
  default     = "local-lvm"
}

variable "base_template" {
  type        = string
  description = "Name of the Packer-built Ubuntu 24.04 VM template used as the clone source for all node pools"
  default     = "e2b-nomad-cluster"
}

variable "base_template_vm_id" {
  type        = number
  description = "Numeric PVE VM ID of the Packer-built base template. Must match the `vm_id` passed to `packer build`. The bpg/proxmox provider clones by VM ID, not name."
}

// ---
// Networking
// ---
// Single private bridge. All VMs (including the ingress VM) live on this
// bridge with private IPs. External traffic reaches the ingress VM via a
// DNAT rule on the PVE host (see self-host-proxmox.md step 7).

variable "bridge" {
  type        = string
  description = "Proxmox bridge for cluster VMs. Pre-configured on the PVE host; host handles egress (e.g. masquerade)."
  default     = "vmbr1"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR for all cluster VMs, e.g. 10.0.0.0/24"
  default     = "10.0.0.0/24"
}

variable "gateway_ip" {
  type        = string
  description = "Subnet gateway IP (usually the Proxmox host on the cluster bridge), e.g. 10.0.0.1"
  default     = "10.0.0.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers used by cluster VMs (before Consul DNS takes over)"
  default     = ["1.1.1.1", "8.8.8.8"]
}

// ---
// SSH access
// ---

variable "ssh_public_key" {
  type        = string
  description = "SSH public key baked into VMs via cloud-init"
}

variable "ssh_private_key" {
  type        = string
  sensitive   = true
  description = "SSH private key Terraform uses to bootstrap VMs via remote-exec"
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Optional SSH bastion/jump host for Terraform remote-exec. Leave empty to connect directly (e.g. when terraform runs on the PVE host or a workstation with VPN into the cluster subnet)."
}

variable "ssh_bastion_user" {
  type        = string
  default     = "root"
  description = "SSH user for the bastion host (only used when ssh_bastion_host is set)."
}

variable "nomad_address" {
  type        = string
  default     = ""
  description = "Override for the Nomad Terraform provider address. Leave empty to use the Traefik-routed domain URL. On first bootstrap, set to a direct Nomad listener (e.g. http://localhost:4646 through an SSH tunnel) because Traefik is itself a Nomad job and not yet running."
}

// ---
// Control Server
// ---

variable "control_server_cluster_size" {
  type    = number
  default = 3
}

variable "control_server_cpu_cores" {
  type    = number
  default = 2
}

variable "control_server_memory_mb" {
  type    = number
  default = 4096
}

variable "control_server_disk_size_gb" {
  type    = number
  default = 20
}

// ---
// API
// ---

variable "api_cluster_size" {
  type    = number
  default = 1
}

variable "api_cpu_cores" {
  type    = number
  default = 2
}

variable "api_memory_mb" {
  type    = number
  default = 4096
}

variable "api_disk_size_gb" {
  type    = number
  default = 20
}

// ---
// Ingress (Traefik)
// ---

variable "ingress_cpu_cores" {
  type    = number
  default = 2
}

variable "ingress_memory_mb" {
  type    = number
  default = 2048
}

variable "ingress_disk_size_gb" {
  type    = number
  default = 20
}

variable "client_proxy_count" {
  type    = number
  default = 1
}

// ---
// Orchestrator (KVM nested virt)
// ---

variable "orchestrator_cluster_size" {
  type    = number
  default = 1
}

variable "orchestrator_cpu_cores" {
  type    = number
  default = 8
}

variable "orchestrator_memory_mb" {
  type    = number
  default = 16384
}

variable "orchestrator_disk_size_gb" {
  type    = number
  default = 100
}

// ---
// Build pool (KVM nested virt)
// ---

variable "build_cluster_size" {
  type    = number
  default = 1
}

variable "build_cpu_cores" {
  type    = number
  default = 8
}

variable "build_memory_mb" {
  type    = number
  default = 16384
}

variable "build_disk_size_gb" {
  type    = number
  default = 100
}

// ---
// ClickHouse
// ---

variable "clickhouse_cluster_size" {
  type    = number
  default = 1
}

variable "clickhouse_cpu_cores" {
  type    = number
  default = 4
}

variable "clickhouse_memory_mb" {
  type    = number
  default = 8192
}

variable "clickhouse_disk_size_gb" {
  type    = number
  default = 20
}

variable "clickhouse_data_volume_size_gb" {
  type    = number
  default = 100
}

// ---
// Redis
// ---

variable "redis_managed" {
  type    = bool
  default = false
}

// ---
// S3-compatible Object Storage
// ---

variable "s3_endpoint" {
  type        = string
  description = "S3-compatible endpoint (e.g. fsn1.your-objectstorage.com)"
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
// Container Registry
// ---

variable "container_registry_url" {
  type        = string
  description = "URL of the Docker registry that hosts service images (api, orchestrator, client-proxy, etc.)"
  default     = ""
}

// ---
// Application Secrets
// ---

variable "postgres_connection_string" {
  type      = string
  default   = " "
  sensitive = true
}

variable "supabase_jwt_secrets" {
  type      = string
  default   = " "
  sensitive = true
}

variable "launch_darkly_api_key" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_otlp_url" {
  type    = string
  default = " "
}

variable "grafana_otel_collector_token" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_username" {
  type    = string
  default = " "
}

variable "grafana_logs_user" {
  type    = string
  default = " "
}

variable "grafana_logs_url" {
  type    = string
  default = " "
}

variable "grafana_logs_collector_api_token" {
  type      = string
  default   = " "
  sensitive = true
}
