resource "null_resource" "orchestrator" {
  for_each = { for idx, ip in var.server_ips : idx => ip }

  triggers = {
    script_hash = filesha256("${path.module}/scripts/start-orchestrator.sh")
    server_ip   = each.value
  }

  connection {
    type        = "ssh"
    host        = each.value
    user        = "root"
    private_key = var.ssh_private_key
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-orchestrator.sh", {
      NODE_POOL                    = var.node_pool_name
      NODE_LABELS                  = join(",", var.node_labels)
      BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
      VLAN_ID                      = var.vswitch_vlan_id
      PRIVATE_IP                   = cidrhost(var.private_subnet_range, each.key + 2)
      PRIVATE_SUBNET_CIDR          = split("/", var.private_subnet_range)[1]
      CLOUD_NETWORK_RANGE          = var.private_network_range
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-orchestrator.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-orchestrator.sh",
      "/tmp/start-orchestrator.sh"
    ]
  }
}
