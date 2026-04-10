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
}

module "init" {
  source = "./init"

  prefix         = var.prefix
  ssh_public_key = var.ssh_public_key
  network_zone   = var.network_zone
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
}

# TODO: module "nomad" will be added in a later step when jobs are configured
