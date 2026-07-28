terraform {
  required_providers {
    nomad = {
      source  = "hashicorp/nomad"
      version = "2.1.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.3"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  required_version = ">= 1.0"

  backend "s3" {
    key                         = "terraform/orchestration/state"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "minio" {
  minio_server   = var.s3_endpoint
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_ssl      = true
  minio_region   = var.s3_region
}

provider "nomad" {
  # Defaults to the Traefik-routed domain URL. Traefik is itself a Nomad job,
  # so on first-time bootstrap this address is unreachable — override with
  # NOMAD_ADDR (via `nomad_address` tfvar) pointing at a direct Nomad listener,
  # typically an SSH-tunneled control server (e.g. http://localhost:4646).
  address      = var.nomad_address != "" ? var.nomad_address : "https://nomad.${var.domain_name}"
  secret_id    = module.init.cluster.nomad_acl_token
  consul_token = module.init.cluster.consul_acl_token
}

locals {
  redis_port       = 6379
  ingress_port     = 80
  ingress_tls_port = 443
  nomad_port       = 4646

  # base64(username:password) for the private container registry, written into
  # /root/docker/config.json on each node so Nomad's docker driver can pull.
  registry_auth = var.registry_username != "" ? base64encode("${var.registry_username}:${var.registry_password}") : ""

  api_pool_name        = "api"
  ingress_pool_name    = "ingress"
  orchestrator_pool    = "default"
  build_pool_name      = "build"
  clickhouse_pool_name = "clickhouse"

  redis_url         = var.redis_managed ? "" : "redis.service.consul:${local.redis_port}"
  redis_cluster_url = ""

  # ssh_private_key may be supplied as PEM content OR a path to a PEM file.
  # Paths are preferred because Make's -include can't parse multi-line values.
  ssh_private_key = fileexists(var.ssh_private_key) ? file(var.ssh_private_key) : var.ssh_private_key

  # Runtime object storage for the app buckets, decoupled from the TF-state S3.
  # Falls back to the state S3 config when app_s3_* is unset (backward compatible).
  app_s3_endpoint   = var.app_s3_endpoint != "" ? var.app_s3_endpoint : var.s3_endpoint
  app_s3_access_key = var.app_s3_access_key != "" ? var.app_s3_access_key : var.s3_access_key
  app_s3_secret_key = var.app_s3_secret_key != "" ? var.app_s3_secret_key : var.s3_secret_key
  app_s3_region     = var.app_s3_region != "" ? var.app_s3_region : var.s3_region
}

module "init" {
  source = "./init"

  prefix        = var.prefix
  bucket_prefix = "${var.prefix}${var.s3_region}-"

  postgres_connection_string       = var.postgres_connection_string
  supabase_jwt_secrets             = var.supabase_jwt_secrets
  launch_darkly_api_key            = var.launch_darkly_api_key
  grafana_otlp_url                 = var.grafana_otlp_url
  grafana_otel_collector_token     = var.grafana_otel_collector_token
  grafana_username                 = var.grafana_username
  grafana_logs_user                = var.grafana_logs_user
  grafana_logs_url                 = var.grafana_logs_url
  grafana_logs_collector_api_token = var.grafana_logs_collector_api_token
}

module "cluster" {
  source = "./nomad-cluster"

  prefix     = var.prefix
  datacenter = var.datacenter

  control_server_ips = var.control_server_ips
  api_ips            = var.api_ips
  ingress_ips        = var.ingress_ips
  orchestrator_ips   = var.orchestrator_ips
  build_ips          = var.build_ips
  clickhouse_ips     = var.clickhouse_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  ssh_private_key  = local.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  api_node_pool_name          = local.api_pool_name
  ingress_node_pool           = local.ingress_pool_name
  orchestrator_node_pool_name = local.orchestrator_pool
  build_node_pool_name        = local.build_pool_name

  clickhouse_node_pool_name        = local.clickhouse_pool_name
  clickhouse_job_constraint_prefix = local.clickhouse_pool_name

  nomad_acl_token              = module.init.cluster.nomad_acl_token
  consul_acl_token             = module.init.cluster.consul_acl_token
  consul_gossip_encryption_key = module.init.cluster.consul_gossip_encryption_key
  consul_dns_request_token     = module.init.cluster.consul_dns_request_token

  container_registry_url = var.container_registry_url
  registry_auth          = local.registry_auth

  s3_endpoint                 = local.app_s3_endpoint
  s3_access_key               = local.app_s3_access_key
  s3_secret_key               = local.app_s3_secret_key
  s3_region                   = local.app_s3_region
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = module.init.fc_kernels_bucket_name
  fc_versions_bucket_name     = module.init.fc_versions_bucket_name
}

module "nomad" {
  source = "./nomad"

  prefix      = var.prefix
  domain_name = var.domain_name
  environment = var.environment

  container_registry_url = var.container_registry_url
  s3_endpoint            = local.app_s3_endpoint
  s3_region              = local.app_s3_region
  s3_access_key          = local.app_s3_access_key
  s3_secret_key          = local.app_s3_secret_key
  acme_email             = var.acme_email
  ingress_image          = var.ingress_image
  hcloud_token           = var.hcloud_token
  hcloud_zone            = var.hcloud_zone
  hcloud_zone_id         = var.hcloud_zone_id

  nomad_acl_token  = module.init.cluster.nomad_acl_token
  consul_acl_token = module.init.cluster.consul_acl_token
  nomad_address    = var.nomad_address

  api_node_pool    = local.api_pool_name
  api_cluster_size = length(var.api_ips)

  ingress_node_pool = local.ingress_pool_name
  ingress_port      = local.ingress_port
  ingress_tls_port  = local.ingress_tls_port
  ingress_count     = 1

  client_proxy_count = var.client_proxy_count

  redis_managed = var.redis_managed
  redis_port    = local.redis_port
  redis_url     = local.redis_url

  clickhouse_cluster_size        = length(var.clickhouse_ips)
  clickhouse_username            = module.init.clickhouse.username
  clickhouse_password            = module.init.clickhouse.password
  clickhouse_server_secret       = module.init.clickhouse.server_secret
  clickhouse_node_pool           = local.clickhouse_pool_name
  clickhouse_jobs_prefix         = local.clickhouse_pool_name
  clickhouse_backups_bucket_name = module.init.clickhouse_backups_bucket_name

  grafana_otel_collector_token = module.init.grafana.otel_collector_token
  grafana_otlp_url             = module.init.grafana.otlp_url
  grafana_username             = module.init.grafana.username
  grafana_logs_user            = module.init.grafana.logs_user
  grafana_logs_endpoint        = module.init.grafana.logs_url
  grafana_logs_api_key         = module.init.grafana.logs_collector_api_token

  postgres_connection_string     = module.init.postgres_connection_string
  supabase_jwt_secrets           = module.init.supabase_jwt_secrets
  admin_token                    = module.init.admin_token
  sandbox_access_token_hash_seed = module.init.sandbox_access_token_hash_seed
  launch_darkly_api_key          = module.init.launch_darkly_api_key

  loki_bucket_name = module.init.loki_bucket_name

  build_node_pool             = local.build_pool_name
  build_cluster_size          = length(var.build_ips)
  api_secret                  = module.init.api_secret
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  template_bucket_name        = module.init.fc_template_bucket_name
  build_cache_bucket_name     = module.init.fc_template_build_cache_bucket_name

  orchestrator_node_pool = local.orchestrator_pool
}
