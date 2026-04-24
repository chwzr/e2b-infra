resource "random_password" "volume_token_key" {
  length  = 32
  special = false

  lifecycle {
    ignore_changes = [length, special]
  }
}

locals {
  # Proxmox setup is functionally identical to Hetzner for the shared Nomad
  # job modules (S3-compatible storage, custom Docker registry), so we pass
  # provider_name = "hetzner" to reuse those config branches.
  provider_name = "hetzner"

  clickhouse_connection_string = var.clickhouse_cluster_size > 0 ? "clickhouse://${var.clickhouse_username}:${var.clickhouse_password}@clickhouse.service.consul:${var.clickhouse_port}/${var.clickhouse_database}" : ""
}

# ---
# OpenTelemetry
# ---
module "otel_collector" {
  source = "../../modules/job-otel-collector"

  provider_name = local.provider_name

  otel_collector_grpc_port = var.otel_collector_grpc_port

  grafana_otel_collector_token = var.grafana_otel_collector_token
  grafana_otlp_url             = var.grafana_otlp_url
  grafana_username             = var.grafana_username
  consul_token                 = var.consul_acl_token

  clickhouse_username = var.clickhouse_username
  clickhouse_password = var.clickhouse_password
  clickhouse_port     = var.clickhouse_port
  clickhouse_database = var.clickhouse_database
}

module "otel_collector_nomad_server" {
  source = "../../modules/job-otel-collector-nomad-server"

  provider_name = local.provider_name
  node_pool     = var.api_node_pool

  grafana_otel_collector_token = var.grafana_otel_collector_token
  grafana_otlp_url             = var.grafana_otlp_url
  grafana_username             = var.grafana_username
}

# ---
# Redis (in-cluster)
# ---
module "redis" {
  source = "../../modules/job-redis"
  count  = var.redis_managed ? 0 : 1

  node_pool   = var.api_node_pool
  port_number = var.redis_port
  port_name   = "redis"
}

# ---
# Ingress (Traefik) — runs on the dedicated ingress node pool
# ---
module "ingress" {
  source = "../../modules/job-ingress"

  ingress_count        = var.ingress_count
  ingress_proxy_port   = var.ingress_port
  traefik_config_files = var.traefik_config_files

  node_pool     = var.ingress_node_pool
  update_stanza = false

  nomad_token  = var.nomad_acl_token
  consul_token = var.consul_acl_token

  otel_collector_grpc_endpoint = "localhost:${var.otel_collector_grpc_port}"
}

# ---
# Client Proxy
# ---
module "client_proxy" {
  source = "../../modules/job-client-proxy"

  update_stanza      = var.api_cluster_size > 1
  client_proxy_count = var.client_proxy_count

  node_pool   = var.api_node_pool
  environment = var.environment

  redis_url           = var.redis_url
  redis_cluster_url   = var.redis_cluster_url
  redis_tls_ca_base64 = var.redis_tls_ca_base64
  image               = "${var.container_registry_url}/${var.prefix}core/client-proxy:latest"

  otel_collector_grpc_endpoint = "localhost:${var.otel_collector_grpc_port}"
  logs_collector_address       = "http://localhost:${var.logs_proxy_port}"
  launch_darkly_api_key        = var.launch_darkly_api_key
}

# ---
# API
# ---
module "api" {
  source = "../../modules/job-api"

  update_stanza      = var.api_cluster_size > 1
  node_pool          = var.api_node_pool
  prevent_colocation = var.api_cluster_size > 2
  count_instances    = var.api_cluster_size

  memory_mb = var.api_memory_mb
  cpu_count = var.api_cpu_count

  domain_name                    = var.domain_name
  orchestrator_port              = var.orchestrator_port
  otel_collector_grpc_endpoint   = "localhost:${var.otel_collector_grpc_port}"
  logs_collector_address         = "http://localhost:${var.logs_proxy_port}"
  port_name                      = "api"
  port_number                    = var.api_port
  environment                    = var.environment
  api_docker_image               = "${var.container_registry_url}/${var.prefix}core/api:latest"
  postgres_connection_string     = var.postgres_connection_string
  supabase_jwt_secrets           = var.supabase_jwt_secrets
  nomad_acl_token                = var.nomad_acl_token
  admin_token                    = var.admin_token
  redis_url                      = var.redis_url
  redis_cluster_url              = var.redis_cluster_url
  redis_tls_ca_base64            = var.redis_tls_ca_base64
  clickhouse_connection_string   = local.clickhouse_connection_string
  sandbox_access_token_hash_seed = var.sandbox_access_token_hash_seed
  db_migrator_docker_image       = "${var.container_registry_url}/${var.prefix}core/db-migrator:latest"
  loki_url                       = "http://loki.service.consul:${var.loki_port}"
  launch_darkly_api_key          = var.launch_darkly_api_key
  db_max_open_connections        = var.db_max_open_connections
  db_min_idle_connections        = var.db_min_idle_connections
  auth_db_max_open_connections   = var.auth_db_max_open_connections
  auth_db_min_idle_connections   = var.auth_db_min_idle_connections

  job_env_vars = {
    VOLUME_TOKEN_ISSUER           = var.domain_name
    VOLUME_TOKEN_SIGNING_KEY      = "HMAC:${base64encode(random_password.volume_token_key.result)}"
    VOLUME_TOKEN_SIGNING_KEY_NAME = "e2b-volume-token-key"
    VOLUME_TOKEN_DURATION         = "1h"
    VOLUME_TOKEN_SIGNING_METHOD   = "HS256"
  }
}

# ---
# Loki
# ---
module "loki" {
  source = "../../modules/job-loki"

  provider_name = local.provider_name
  aws_region    = var.s3_region
  s3_endpoint   = "https://${var.s3_endpoint}"

  node_pool          = var.api_node_pool
  prevent_colocation = var.api_cluster_size > 2
  bucket_name        = var.loki_bucket_name
  loki_port          = var.loki_port
}

# ---
# Logs Collector
# ---
module "logs_collector" {
  source = "../../modules/job-logs-collector"

  loki_endpoint = "http://loki.service.consul:${var.loki_port}"

  vector_health_port = var.logs_health_proxy_port
  vector_api_port    = var.logs_proxy_port

  grafana_logs_user     = var.grafana_logs_user
  grafana_logs_endpoint = var.grafana_logs_endpoint
  grafana_api_key       = var.grafana_logs_api_key
}

# ---
# Template Manager
# ---
module "template_manager" {
  source = "../../modules/job-template-manager"

  provider_name = local.provider_name
  provider_hetzner_config = {
    s3_endpoint            = "https://${var.s3_endpoint}"
    s3_region              = var.s3_region
    docker_registry_url    = var.container_registry_url
    docker_repository_name = "core/custom-environments"
  }

  update_stanza = var.build_cluster_size > 1
  node_pool     = var.build_node_pool

  port             = var.template_manager_port
  environment      = var.environment
  consul_acl_token = var.consul_acl_token
  domain_name      = var.domain_name

  api_secret                   = var.api_secret
  artifact_source              = "s3::https://${var.s3_endpoint}/${var.fc_env_pipeline_bucket_name}/template-manager?aws_access_key_id=${var.s3_access_key}&aws_access_key_secret=${var.s3_secret_key}&region=${var.s3_region}"
  template_bucket_name         = var.template_bucket_name
  build_cache_bucket_name      = var.build_cache_bucket_name
  otel_collector_grpc_endpoint = "localhost:${var.otel_collector_grpc_port}"
  logs_collector_address       = "http://localhost:${var.logs_proxy_port}"
  clickhouse_connection_string = local.clickhouse_connection_string
  launch_darkly_api_key        = var.launch_darkly_api_key

  nomad_addr  = var.nomad_address != "" ? var.nomad_address : "https://nomad.${var.domain_name}"
  nomad_token = var.nomad_acl_token
}

# ---
# Template Manager Autoscaler (only when build_cluster_size > 1)
# ---
module "template_manager_autoscaler" {
  source = "../../modules/job-template-manager-autoscaler"
  count  = var.build_cluster_size > 1 ? 1 : 0

  node_pool                  = var.api_node_pool
  nomad_token                = var.nomad_acl_token
  apm_plugin_artifact_source = "s3::https://${var.s3_endpoint}/${var.fc_env_pipeline_bucket_name}/nomad-nodepool-apm?aws_access_key_id=${var.s3_access_key}&aws_access_key_secret=${var.s3_secret_key}&region=${var.s3_region}"
}

# ---
# ClickHouse
# ---
module "clickhouse" {
  source = "../../modules/job-clickhouse"

  provider_name = local.provider_name

  node_pool             = var.clickhouse_node_pool
  job_constraint_prefix = var.clickhouse_jobs_prefix
  server_count          = var.clickhouse_cluster_size

  server_secret = var.clickhouse_server_secret

  cpu_count = var.clickhouse_cpu_count
  memory_mb = var.clickhouse_memory_mb

  clickhouse_database     = var.clickhouse_database
  clickhouse_username     = var.clickhouse_username
  clickhouse_password     = var.clickhouse_password
  clickhouse_port         = var.clickhouse_port
  clickhouse_metrics_port = var.clickhouse_metrics_port

  otel_exporter_endpoint = "http://localhost:${var.otel_collector_grpc_port}"

  aws_region    = var.s3_region
  s3_endpoint   = "https://${var.s3_endpoint}"
  backup_bucket = var.clickhouse_backups_bucket_name

  clickhouse_migrator_image = "${var.container_registry_url}/${var.prefix}core/clickhouse-migrator:latest"
}

# ---
# Orchestrator
# ---
module "orchestrator" {
  source = "../../modules/job-orchestrator"

  provider_name = local.provider_name
  provider_hetzner_config = {
    s3_endpoint            = "https://${var.s3_endpoint}"
    s3_region              = var.s3_region
    docker_registry_url    = var.container_registry_url
    docker_repository_name = "core/custom-environments"
  }

  node_pool  = var.orchestrator_node_pool
  port       = var.orchestrator_port
  proxy_port = var.orchestrator_proxy_port

  environment           = var.environment
  artifact_source       = "s3::https://${var.s3_endpoint}/${var.fc_env_pipeline_bucket_name}/orchestrator?aws_access_key_id=${var.s3_access_key}&aws_access_key_secret=${var.s3_secret_key}&region=${var.s3_region}"
  orchestrator_checksum = "hetzner-s3"

  logs_collector_address       = "http://localhost:${var.logs_proxy_port}"
  otel_collector_grpc_endpoint = "localhost:${var.otel_collector_grpc_port}"
  envd_timeout                 = var.envd_timeout
  template_bucket_name         = var.template_bucket_name
  allow_sandbox_internet       = var.allow_sandbox_internet
  clickhouse_connection_string = local.clickhouse_connection_string
  redis_url                    = var.redis_url
  redis_cluster_url            = var.redis_cluster_url
  redis_tls_ca_base64          = var.redis_tls_ca_base64

  consul_token            = var.consul_acl_token
  domain_name             = var.domain_name
  build_cache_bucket_name = var.build_cache_bucket_name
  launch_darkly_api_key   = var.launch_darkly_api_key
}
