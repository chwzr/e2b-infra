# Core
variable "prefix" {
  type        = string
  description = "Resource name prefix (matches PREFIX in .env). Used to construct docker image paths that match the Makefile's REGISTRY_PREFIX."
}

variable "domain_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "container_registry_url" {
  type = string
}

variable "s3_access_key" {
  type        = string
  sensitive   = true
  description = "S3 access key passed to Nomad artifact sources (go-getter query params)."
}

variable "s3_secret_key" {
  type        = string
  sensitive   = true
  description = "S3 secret key passed to Nomad artifact sources (go-getter query params)."
}

variable "s3_endpoint" {
  type = string
}

variable "s3_region" {
  type    = string
  default = "fsn1"
}

# Auth
variable "nomad_acl_token" {
  type      = string
  sensitive = true
}

variable "nomad_address" {
  type        = string
  default     = ""
  description = "Override for the Nomad API address used by data.external. Leave empty to use https://nomad.$DOMAIN (Traefik-routed). Set to a direct URL (e.g. http://localhost:4646) for bootstrap when Traefik is not yet running."
}

variable "acme_email" {
  type        = string
  default     = ""
  description = "Contact email for Let's Encrypt. When set, Traefik requests HTTP-01 certs on-demand for any Host it serves on the websecure (TLS) entrypoint. Empty disables TLS."
}

variable "ingress_image" {
  type        = string
  default     = "traefik:v3.5"
  description = "Docker image for the ingress task. Use the custom image with bash+curl+jq when wiring up hcloud DNS-01."
}

variable "hcloud_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "hcloud_zone" {
  type    = string
  default = ""
}

variable "hcloud_zone_id" {
  type    = string
  default = ""
}

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

# Node pools
variable "api_node_pool" {
  type = string
}

variable "ingress_node_pool" {
  type = string
}

# Cluster sizes
variable "api_cluster_size" {
  type = number
}

# Ingress
variable "ingress_port" {
  type = number
}

variable "ingress_tls_port" {
  type = number
}

variable "ingress_count" {
  type = number
}

variable "traefik_config_files" {
  type    = map(string)
  default = {}
}

# Client Proxy
variable "client_proxy_count" {
  type    = number
  default = 1
}

# Redis
variable "redis_managed" {
  type = bool
}

variable "redis_port" {
  type = number
}

variable "redis_url" {
  type    = string
  default = ""
}

variable "redis_cluster_url" {
  type      = string
  default   = ""
  sensitive = true
}

variable "redis_tls_ca_base64" {
  type      = string
  default   = ""
  sensitive = true
}

# ClickHouse
variable "clickhouse_cluster_size" {
  type    = number
  default = 0
}

variable "clickhouse_username" {
  type    = string
  default = "e2b"
}

variable "clickhouse_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "clickhouse_port" {
  type    = number
  default = 9000
}

variable "clickhouse_database" {
  type    = string
  default = "default"
}

variable "clickhouse_node_pool" {
  type    = string
  default = "clickhouse"
}

variable "clickhouse_jobs_prefix" {
  type    = string
  default = "clickhouse"
}

variable "clickhouse_server_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "clickhouse_cpu_count" {
  type    = number
  default = 4
}

variable "clickhouse_memory_mb" {
  type    = number
  default = 8192
}

variable "clickhouse_metrics_port" {
  type    = number
  default = 9363
}

variable "clickhouse_backups_bucket_name" {
  type    = string
  default = ""
}

# Grafana / Observability
variable "grafana_otel_collector_token" {
  type      = string
  sensitive = true
}

variable "grafana_otlp_url" {
  type      = string
  sensitive = true
}

variable "grafana_username" {
  type      = string
  sensitive = true
}

variable "grafana_logs_user" {
  type    = string
  default = ""
}

variable "grafana_logs_endpoint" {
  type    = string
  default = ""
}

variable "grafana_logs_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

# API
variable "api_port" {
  type    = number
  default = 80
}

variable "api_memory_mb" {
  type    = number
  default = 512
}

variable "api_cpu_count" {
  type    = number
  default = 1
}

variable "postgres_connection_string" {
  type      = string
  sensitive = true
}

variable "supabase_jwt_secrets" {
  type      = string
  sensitive = true
}

variable "admin_token" {
  type      = string
  sensitive = true
}

variable "sandbox_access_token_hash_seed" {
  type      = string
  sensitive = true
}

# Orchestrator
variable "orchestrator_node_pool" {
  type    = string
  default = "default"
}

variable "orchestrator_port" {
  type    = number
  default = 5008
}

variable "orchestrator_proxy_port" {
  type    = number
  default = 5007
}

variable "allow_sandbox_internet" {
  type    = bool
  default = true
}

variable "envd_timeout" {
  type    = string
  default = "40s"
}

# Loki
variable "loki_bucket_name" {
  type = string
}

variable "loki_port" {
  type    = number
  default = 3100
}

variable "logs_health_proxy_port" {
  type    = number
  default = 44313
}

# Telemetry
variable "otel_collector_grpc_port" {
  type    = number
  default = 4317
}

variable "logs_proxy_port" {
  type    = number
  default = 30006
}

# Feature flags
variable "launch_darkly_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

# Template Manager / Build
variable "build_node_pool" {
  type = string
}

variable "build_cluster_size" {
  type    = number
  default = 1
}

variable "template_manager_port" {
  type    = number
  default = 5008
}

variable "api_secret" {
  type      = string
  sensitive = true
}

variable "fc_env_pipeline_bucket_name" {
  type = string
}

variable "template_bucket_name" {
  type = string
}

variable "build_cache_bucket_name" {
  type    = string
  default = ""
}

# DB connection pool
variable "db_max_open_connections" {
  type    = number
  default = 40
}

variable "db_min_idle_connections" {
  type    = number
  default = 5
}

variable "auth_db_max_open_connections" {
  type    = number
  default = 20
}

variable "auth_db_min_idle_connections" {
  type    = number
  default = 5
}
