# Core
variable "domain_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "container_registry_url" {
  type = string
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

variable "consul_acl_token" {
  type      = string
  sensitive = true
}

# Node pools
variable "api_node_pool" {
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

# ClickHouse (used for connection string construction)
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
