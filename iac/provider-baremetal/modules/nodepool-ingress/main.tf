terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir  = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ip = var.private_ips[0]
}

resource "null_resource" "bootstrap" {
  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-ingress.sh")
    host        = local.private_ip
  }

  connection {
    type        = "ssh"
    host        = local.private_ip
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    source      = local.setup_dir
    destination = "/tmp"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup/setup-base.sh /tmp/setup/install-consul.sh /tmp/setup/install-nomad.sh /tmp/setup/install-vault.sh",
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh ingress",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-ingress.sh", {
      NODE_POOL                    = var.node_pool_name
      PRIVATE_IP                   = local.private_ip
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-ingress.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-ingress.sh",
      "/tmp/start-ingress.sh",
    ]
  }
}
