terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    minio = {
      source = "aminueza/minio"
    }
  }
}

module "network" {
  source = "../modules/network"

  prefix       = var.prefix
  network_zone = var.network_zone
}

resource "hcloud_ssh_key" "cluster" {
  name       = "${var.prefix}cluster"
  public_key = var.ssh_public_key
}
