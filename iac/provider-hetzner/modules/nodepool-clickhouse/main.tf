terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
}

resource "hcloud_volume" "clickhouse" {
  count = var.cluster_size

  name     = "${var.prefix}clickhouse-data-${count.index}"
  size     = var.data_volume_size_gb
  location = var.location
  format   = "xfs"
}

resource "hcloud_server" "clickhouse" {
  count = var.cluster_size

  name        = "${var.prefix}clickhouse-${count.index}"
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys = [var.ssh_key_id]

  firewall_ids = var.firewall_ids

  labels = {
    "role"           = "clickhouse"
    "cluster"        = var.cluster_tag_value
    "node-pool"      = var.node_pool_name
    "job-constraint" = "${var.job_constraint_prefix}-${count.index}"
  }

  user_data = templatefile("${path.module}/scripts/start-clickhouse.sh", {
    NODE_POOL                    = var.node_pool_name
    JOB_CONSTRAINT               = "${var.job_constraint_prefix}-${count.index}"
    VOLUME_ID                    = hcloud_volume.clickhouse[count.index].id
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

resource "hcloud_volume_attachment" "clickhouse" {
  count = var.cluster_size

  volume_id = hcloud_volume.clickhouse[count.index].id
  server_id = hcloud_server.clickhouse[count.index].id
  automount = false
}
