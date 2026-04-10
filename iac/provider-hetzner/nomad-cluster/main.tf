terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

locals {
  cluster_tag_value = "${var.prefix}nomad-cluster"
}

module "control_server" {
  source = "../modules/nodepool-control-server"

  prefix     = var.prefix
  location   = var.location
  datacenter = var.datacenter

  cluster_size = var.control_server_cluster_size
  server_type  = var.control_server_type
  image        = var.server_image

  network_id   = var.network_id
  ssh_key_id   = var.ssh_key_id
  firewall_ids = var.firewall_ids

  cluster_tag_value            = local.cluster_tag_value
  hcloud_token                 = var.hcloud_token
  nomad_acl_token              = var.nomad_acl_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
}

module "api" {
  source = "../modules/nodepool-api"

  prefix     = var.prefix
  location   = var.location
  datacenter = var.datacenter

  cluster_size   = var.api_cluster_size
  server_type    = var.api_server_type
  node_pool_name = var.api_node_pool_name

  network_id   = var.network_id
  ssh_key_id   = var.ssh_key_id
  firewall_ids = var.firewall_ids

  cluster_tag_value            = local.cluster_tag_value
  hcloud_token                 = var.hcloud_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
}

module "build" {
  source = "../modules/nodepool-client"

  name       = "orch-build"
  prefix     = var.prefix
  location   = var.location
  datacenter = var.datacenter

  cluster_size   = var.build_cluster_size
  server_type    = var.build_server_type
  node_pool_name = var.build_node_pool_name
  node_labels    = var.build_node_labels

  base_hugepages_percentage = 60

  network_id   = var.network_id
  ssh_key_id   = var.ssh_key_id
  firewall_ids = var.firewall_ids

  cluster_tag_value            = local.cluster_tag_value
  hcloud_token                 = var.hcloud_token
  consul_acl_token             = var.consul_acl_token
  consul_gossip_encryption_key = var.consul_gossip_encryption_key
  consul_dns_request_token     = var.consul_dns_request_token
  container_registry_url       = var.container_registry_url
}
