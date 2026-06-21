variable "domain_name" {
  type        = string
  description = "Domain name used for Traefik Host routing and service URLs. DNS records are created manually. Point *.<domain_name> at the ingress server (or a load balancer in front of it)."
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
// Pre-provisioned servers (private IPs per nodepool)
// ---
// Each server is an existing Ubuntu 24.04 host with the deploy SSH key on root.
// The IP given here is the private address used for BOTH ssh and Consul/Nomad
// advertise + retry_join. The deploy host must be able to reach these IPs.

variable "control_server_ips" {
  type        = list(string)
  description = "Private IPs of the Nomad/Consul control servers."
}

variable "api_ips" {
  type        = list(string)
  description = "Private IPs of the API nodepool servers."
}

variable "ingress_ips" {
  type        = list(string)
  description = "Private IPs of the ingress (Traefik) servers. Element 0 is the primary."
}

variable "orchestrator_ips" {
  type        = list(string)
  description = "Private IPs of the orchestrator servers (require /dev/kvm)."
}

variable "build_ips" {
  type        = list(string)
  description = "Private IPs of the build (template-manager) servers (require /dev/kvm)."
}

variable "clickhouse_ips" {
  type        = list(string)
  description = "Private IPs of the ClickHouse servers."
}

// ---
// Tool versions baked at deploy time by setup-base.sh
// ---

variable "consul_version" {
  type    = string
  default = "1.16.2"
}

variable "nomad_version" {
  type    = string
  default = "1.6.2"
}

variable "vault_version" {
  type    = string
  default = "1.20.3"
}

// ---
// SSH access
// ---

variable "ssh_private_key" {
  type        = string
  sensitive   = true
  description = "SSH private key (PEM content OR a path to a PEM file) Terraform uses to bootstrap servers over SSH as root."
}

variable "ssh_bastion_host" {
  type        = string
  default     = ""
  description = "Optional SSH bastion/jump host. Leave empty to connect directly (deploy host has network access to the private IPs)."
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

variable "acme_email" {
  type        = string
  default     = ""
  description = "Contact email for Let's Encrypt. Empty disables TLS on the ingress."
}

variable "ingress_image" {
  type        = string
  default     = "traefik:v3.5"
  description = "Docker image for the ingress Traefik task."
}

variable "hcloud_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Hetzner Cloud API token with DNS zone write access. When set, Traefik uses DNS-01 to issue a wildcard cert for *.DOMAIN. When empty, falls back to HTTP-01."
}

variable "hcloud_zone" {
  type        = string
  default     = ""
  description = "Hetzner Cloud DNS zone name (e.g. example.dev)."
}

variable "hcloud_zone_id" {
  type        = string
  default     = ""
  description = "Hetzner Cloud DNS zone id (numeric)."
}

variable "client_proxy_count" {
  type    = number
  default = 1
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
  description = "URL of the Docker registry that hosts service images."
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
