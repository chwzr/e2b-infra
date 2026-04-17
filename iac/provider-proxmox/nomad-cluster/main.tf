terraform {
  required_providers {
    proxmox = {
      source = "Terraform-for-Proxmox/proxmox"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

module "control_server" {
  source = "../modules/nodepool-control-server"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cluster_size = var.control_server_cluster_size
  cpu_cores    = var.control_server_cpu_cores
  memory_mb    = var.control_server_memory_mb
  disk_size_gb = var.control_server_disk_size_gb

  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  nomad_acl_token              = var.nomad_acl_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
}

module "api" {
  source = "../modules/nodepool-api"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cluster_size = var.api_cluster_size
  cpu_cores    = var.api_cpu_cores
  memory_mb    = var.api_memory_mb
  disk_size_gb = var.api_disk_size_gb

  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  node_pool_name = var.api_node_pool_name

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "ingress" {
  source = "../modules/nodepool-ingress"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cpu_cores    = var.ingress_cpu_cores
  memory_mb    = var.ingress_memory_mb
  disk_size_gb = var.ingress_disk_size_gb

  public_bridge       = var.public_bridge
  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  public_ip       = var.ingress_public_ip
  public_gateway  = var.ingress_public_gateway
  public_cidr_bit = var.ingress_public_cidr_bit

  node_pool_name = var.ingress_node_pool

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "orchestrator" {
  source = "../modules/nodepool-orchestrator"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cluster_size = var.orchestrator_cluster_size
  cpu_cores    = var.orchestrator_cpu_cores
  memory_mb    = var.orchestrator_memory_mb
  disk_size_gb = var.orchestrator_disk_size_gb

  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  node_pool_name = var.orchestrator_node_pool_name

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "build" {
  source = "../modules/nodepool-build"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cluster_size = var.build_cluster_size
  cpu_cores    = var.build_cpu_cores
  memory_mb    = var.build_memory_mb
  disk_size_gb = var.build_disk_size_gb

  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  node_pool_name = var.build_node_pool_name

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}

module "clickhouse" {
  source = "../modules/nodepool-clickhouse"

  prefix           = var.prefix
  datacenter       = var.datacenter
  pve_node         = var.pve_node
  pve_storage_pool = var.pve_storage_pool
  base_template    = var.base_template

  cluster_size        = var.clickhouse_cluster_size
  cpu_cores           = var.clickhouse_cpu_cores
  memory_mb           = var.clickhouse_memory_mb
  disk_size_gb        = var.clickhouse_disk_size_gb
  data_volume_size_gb = var.clickhouse_data_volume_size_gb

  private_bridge      = var.private_bridge
  private_subnet_cidr = var.private_subnet_cidr
  private_gateway_ip  = var.private_gateway_ip
  private_dns_servers = var.private_dns_servers

  node_pool_name        = var.clickhouse_node_pool_name
  job_constraint_prefix = var.clickhouse_job_constraint_prefix

  ssh_public_key  = var.ssh_public_key
  ssh_private_key = var.ssh_private_key

  consul_retry_join_ips        = module.control_server.private_ips
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url

  depends_on = [module.control_server]
}
