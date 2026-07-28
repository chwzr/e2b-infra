terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.56"
    }

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
  }

  required_version = ">= 1.0"

  backend "s3" {
    key                         = "terraform/orchestration/state"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

provider "hcloud" {}

provider "minio" {
  minio_server   = var.s3_endpoint
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_ssl      = true
  minio_region   = var.s3_region
}

provider "nomad" {
  address      = "https://nomad.${var.domain_name}"
  secret_id    = module.init.cluster.nomad_acl_token
  consul_token = module.init.cluster.consul_acl_token
}

locals {
  redis_port   = 6379
  ingress_port = 8080
  nomad_port   = 4646

  api_pool_name        = "api"
  client_pool_name     = "default"
  build_pool_name      = "build"
  clickhouse_pool_name = "clickhouse"

  redis_url         = var.redis_managed ? "" : "redis.service.consul:${local.redis_port}"
  redis_cluster_url = ""
}

module "init" {
  source = "./init"

  prefix         = var.prefix
  bucket_prefix  = "${var.prefix}${var.s3_region}-"
  ssh_public_key = var.ssh_public_key
  network_zone   = var.network_zone
  vswitch_id     = var.vswitch_id

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
  location   = var.location
  datacenter = var.datacenter

  network_id   = module.init.network_id
  ssh_key_id   = module.init.ssh_key_id
  firewall_ids = [hcloud_firewall.cluster.id]

  hcloud_token = var.hcloud_token

  control_server_cluster_size = var.control_server_cluster_size
  control_server_type         = var.control_server_type

  nomad_acl_token              = module.init.cluster.nomad_acl_token
  consul_acl_token             = module.init.cluster.consul_acl_token
  consul_gossip_encryption_key = module.init.cluster.consul_gossip_encryption_key
  consul_dns_request_token     = module.init.cluster.consul_dns_request_token

  api_cluster_size       = var.api_cluster_size
  api_server_type        = var.api_server_type
  api_node_pool_name     = local.api_pool_name
  container_registry_url = var.container_registry_url

  build_server_ips      = var.build_server_ips
  build_ssh_private_key = var.build_ssh_private_key != "" ? var.build_ssh_private_key : var.orchestrator_ssh_private_key
  build_node_pool_name  = local.build_pool_name

  clickhouse_cluster_size          = var.clickhouse_cluster_size
  clickhouse_server_type           = var.clickhouse_server_type
  clickhouse_node_pool_name        = local.clickhouse_pool_name
  clickhouse_job_constraint_prefix = local.clickhouse_pool_name

  orchestrator_server_ips      = var.orchestrator_server_ips
  orchestrator_ssh_private_key = var.orchestrator_ssh_private_key
  orchestrator_vswitch_vlan_id = var.vswitch_vlan_id
  orchestrator_node_pool_name  = local.client_pool_name
  consul_retry_join_ips        = var.consul_retry_join_ips
}

module "nomad" {
  source = "./nomad"

  domain_name = var.domain_name
  environment = var.environment

  container_registry_url = var.container_registry_url
  s3_endpoint            = var.s3_endpoint
  s3_region              = var.s3_region

  nomad_acl_token  = module.init.cluster.nomad_acl_token
  consul_acl_token = module.init.cluster.consul_acl_token

  api_node_pool    = local.api_pool_name
  api_cluster_size = var.api_cluster_size

  ingress_port  = local.ingress_port
  ingress_count = var.ingress_count

  client_proxy_count = var.client_proxy_count

  redis_managed = var.redis_managed
  redis_port    = local.redis_port
  redis_url     = local.redis_url

  clickhouse_cluster_size        = var.clickhouse_cluster_size
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
  build_cluster_size          = length(var.build_server_ips)
  api_secret                  = module.init.api_secret
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  template_bucket_name        = module.init.fc_template_bucket_name
  build_cache_bucket_name     = module.init.fc_template_build_cache_bucket_name

  orchestrator_node_pool = local.client_pool_name
}
