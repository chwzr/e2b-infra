terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  setup_dir   = "${path.module}/../../../nomad-cluster-disk-image/setup"
  private_ips = var.private_ips
}

resource "null_resource" "bootstrap" {
  count = length(var.private_ips)

  triggers = {
    setup_hash  = filesha256("${local.setup_dir}/setup-base.sh")
    script_hash = filesha256("${path.module}/scripts/start-build.sh")
    host        = var.private_ips[count.index]
  }

  connection {
    type        = "ssh"
    host        = var.private_ips[count.index]
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
      "CONSUL_VERSION='${var.consul_version}' NOMAD_VERSION='${var.nomad_version}' VAULT_VERSION='${var.vault_version}' /tmp/setup/setup-base.sh build",
    ]
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-build.sh", {
      NODE_POOL                    = var.node_pool_name
      NODE_LABELS                  = join(",", var.node_labels)
      BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
      PRIVATE_IP                   = var.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      REGISTRY_AUTH                = var.registry_auth
      DATACENTER                   = var.datacenter

      S3_ENDPOINT                 = var.s3_endpoint
      S3_ACCESS_KEY               = var.s3_access_key
      S3_SECRET_KEY               = var.s3_secret_key
      S3_REGION                   = var.s3_region
      FC_ENV_PIPELINE_BUCKET_NAME = var.fc_env_pipeline_bucket_name
      FC_KERNELS_BUCKET_NAME      = var.fc_kernels_bucket_name
      FC_VERSIONS_BUCKET_NAME     = var.fc_versions_bucket_name
    })
    destination = "/tmp/start-build.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-build.sh",
      "/tmp/start-build.sh",
    ]
  }
}
