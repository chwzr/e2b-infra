terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

module "control_server" {
  source = "../modules/nodepool-control-server"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.control_server_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  nomad_acl_token              = var.nomad_acl_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
}

module "api" {
  source = "../modules/nodepool-api"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.api_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.api_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
  registry_auth                = var.registry_auth

  depends_on = [module.control_server]
}

module "ingress" {
  source = "../modules/nodepool-ingress"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.ingress_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.ingress_node_pool

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
  registry_auth                = var.registry_auth

  depends_on = [module.control_server]
}

module "orchestrator" {
  source = "../modules/nodepool-orchestrator"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.orchestrator_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.orchestrator_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
  registry_auth                = var.registry_auth

  s3_endpoint                 = var.s3_endpoint
  s3_access_key               = var.s3_access_key
  s3_secret_key               = var.s3_secret_key
  s3_region                   = var.s3_region
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name

  depends_on = [module.control_server]
}

module "build" {
  source = "../modules/nodepool-build"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.build_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name = var.build_node_pool_name

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
  registry_auth                = var.registry_auth

  s3_endpoint                 = var.s3_endpoint
  s3_access_key               = var.s3_access_key
  s3_secret_key               = var.s3_secret_key
  s3_region                   = var.s3_region
  fc_env_pipeline_bucket_name = var.fc_env_pipeline_bucket_name
  fc_kernels_bucket_name      = var.fc_kernels_bucket_name
  fc_versions_bucket_name     = var.fc_versions_bucket_name

  depends_on = [module.control_server]
}

module "clickhouse" {
  source = "../modules/nodepool-clickhouse"

  prefix     = var.prefix
  datacenter = var.datacenter

  private_ips = var.clickhouse_ips

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  node_pool_name        = var.clickhouse_node_pool_name
  job_constraint_prefix = var.clickhouse_job_constraint_prefix

  ssh_private_key  = var.ssh_private_key
  ssh_bastion_host = var.ssh_bastion_host
  ssh_bastion_user = var.ssh_bastion_user

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
  registry_auth                = var.registry_auth

  depends_on = [module.control_server]
}
