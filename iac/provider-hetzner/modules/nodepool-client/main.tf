terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_placement_group" "client" {
  name = "${var.prefix}${var.name}"
  type = "spread"
}

resource "hcloud_server" "client" {
  count = var.cluster_size

  name        = "${var.prefix}${var.name}-${count.index}"
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys = [var.ssh_key_id]

  placement_group_id = hcloud_placement_group.client.id
  firewall_ids       = var.firewall_ids

  labels = {
    "role"      = "client"
    "cluster"   = var.cluster_tag_value
    "node-pool" = var.node_pool_name
  }

  user_data = templatefile("${path.module}/scripts/start-client.sh", {
    NODE_POOL                    = var.node_pool_name
    NODE_LABELS                  = join(",", var.node_labels)
    BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
    CLUSTER_TAG_VALUE            = var.cluster_tag_value
    HCLOUD_TOKEN                 = var.hcloud_token
    CONSUL_TOKEN                 = var.consul_acl_token
    CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
    CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
    CONTAINER_REGISTRY_URL       = var.container_registry_url
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
