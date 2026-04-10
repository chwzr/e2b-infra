terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_network" "cluster" {
  name     = "${var.prefix}cluster"
  ip_range = var.ip_range
}

resource "hcloud_network_subnet" "cluster" {
  network_id   = hcloud_network.cluster.id
  type         = "cloud"
  network_zone = var.network_zone
  ip_range     = var.subnet_range
}

# vSwitch subnet for connecting Hetzner dedicated servers to the Cloud Network.
# Only created when a vSwitch ID is provided.
resource "hcloud_network_subnet" "vswitch" {
  count        = var.vswitch_id != null ? 1 : 0
  network_id   = hcloud_network.cluster.id
  type         = "vswitch"
  network_zone = var.network_zone
  ip_range     = var.vswitch_subnet_range
  vswitch_id   = var.vswitch_id
}
