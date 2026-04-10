terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_placement_group" "control_server" {
  name = "${var.prefix}control-server"
  type = "spread"
}

resource "hcloud_server" "control_server" {
  count = var.cluster_size

  name        = "${var.prefix}server-${count.index}"
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys = [var.ssh_key_id]

  placement_group_id = hcloud_placement_group.control_server.id
  firewall_ids       = var.firewall_ids

  labels = {
    "role"         = "server"
    "cluster"      = var.cluster_tag_value
    "cluster-size" = tostring(var.cluster_size)
  }

  user_data = templatefile("${path.module}/scripts/start-server.sh", {
    NUM_SERVERS                  = var.cluster_size
    CLUSTER_TAG_VALUE            = var.cluster_tag_value
    HCLOUD_TOKEN                 = var.hcloud_token
    NOMAD_TOKEN                  = var.nomad_acl_token
    CONSUL_TOKEN                 = var.consul_acl_token
    CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
    DATACENTER                   = var.datacenter
  })

  network {
    network_id = var.network_id
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}
