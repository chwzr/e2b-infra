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
