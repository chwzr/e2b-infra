terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.82"
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

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure
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
  redis_port   = 6379
  ingress_port = 8080
  nomad_port   = 4646

  api_pool_name        = "api"
  ingress_pool_name    = "ingress"
  orchestrator_pool    = "default"
  build_pool_name      = "build"
  clickhouse_pool_name = "clickhouse"

  redis_url         = var.redis_managed ? "" : "redis.service.consul:${local.redis_port}"
  redis_cluster_url = ""

  # ssh_private_key may be supplied as a PEM-content string OR a path to a PEM
  # file. Paths are preferred because Make's -include can't parse multi-line
  # values in the env file. If the value is a readable file path, inline it.
  ssh_private_key = fileexists(var.ssh_private_key) ? file(var.ssh_private_key) : var.ssh_private_key
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

  pve_node            = var.pve_node
  pve_storage_pool    = var.pve_storage_pool
  base_template       = var.base_template
  base_template_vm_id = var.base_template_vm_id

  bridge      = var.bridge
  subnet_cidr = var.subnet_cidr
  gateway_ip  = var.gateway_ip
  dns_servers = var.dns_servers

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = local.ssh_private_key

  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  control_server_cluster_size = var.control_server_cluster_size
  control_server_cpu_cores    = var.control_server_cpu_cores
  control_server_memory_mb    = var.control_server_memory_mb
  control_server_disk_size_gb = var.control_server_disk_size_gb

  api_cluster_size   = var.api_cluster_size
  api_cpu_cores      = var.api_cpu_cores
  api_memory_mb      = var.api_memory_mb
  api_disk_size_gb   = var.api_disk_size_gb
  api_node_pool_name = local.api_pool_name

  ingress_cpu_cores    = var.ingress_cpu_cores
  ingress_memory_mb    = var.ingress_memory_mb
  ingress_disk_size_gb = var.ingress_disk_size_gb
  ingress_node_pool    = local.ingress_pool_name

  orchestrator_cluster_size   = var.orchestrator_cluster_size
  orchestrator_cpu_cores      = var.orchestrator_cpu_cores
  orchestrator_memory_mb      = var.orchestrator_memory_mb
  orchestrator_disk_size_gb   = var.orchestrator_disk_size_gb
  orchestrator_node_pool_name = local.orchestrator_pool

  build_cluster_size   = var.build_cluster_size
  build_cpu_cores      = var.build_cpu_cores
  build_memory_mb      = var.build_memory_mb
  build_disk_size_gb   = var.build_disk_size_gb
  build_node_pool_name = local.build_pool_name

  clickhouse_cluster_size          = var.clickhouse_cluster_size
  clickhouse_cpu_cores             = var.clickhouse_cpu_cores
  clickhouse_memory_mb             = var.clickhouse_memory_mb
  clickhouse_disk_size_gb          = var.clickhouse_disk_size_gb
  clickhouse_data_volume_size_gb   = var.clickhouse_data_volume_size_gb
  clickhouse_node_pool_name        = local.clickhouse_pool_name
  clickhouse_job_constraint_prefix = local.clickhouse_pool_name

  nomad_acl_token              = module.init.cluster.nomad_acl_token
  consul_acl_token             = module.init.cluster.consul_acl_token
  consul_gossip_encryption_key = module.init.cluster.consul_gossip_encryption_key
  consul_dns_request_token     = module.init.cluster.consul_dns_request_token

  container_registry_url = var.container_registry_url
}

module "nomad" {
  source = "./nomad"

  prefix      = var.prefix
  domain_name = var.domain_name
  environment = var.environment

  container_registry_url = var.container_registry_url
  s3_endpoint            = var.s3_endpoint
  s3_region              = var.s3_region
  s3_access_key          = var.s3_access_key
  s3_secret_key          = var.s3_secret_key
  acme_email             = var.acme_email

  nomad_acl_token  = module.init.cluster.nomad_acl_token
  consul_acl_token = module.init.cluster.consul_acl_token
  nomad_address    = var.nomad_address

  api_node_pool    = local.api_pool_name
  api_cluster_size = var.api_cluster_size

  ingress_node_pool = local.ingress_pool_name
  ingress_port      = local.ingress_port
  ingress_count     = 1

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
  build_cluster_size          = var.build_cluster_size
  api_secret                  = module.init.api_secret
  fc_env_pipeline_bucket_name = module.init.fc_env_pipeline_bucket_name
  template_bucket_name        = module.init.fc_template_bucket_name
  build_cache_bucket_name     = module.init.fc_template_build_cache_bucket_name

  orchestrator_node_pool = local.orchestrator_pool
}
