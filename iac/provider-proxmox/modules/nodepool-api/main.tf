terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  subnet_mask = split("/", var.private_subnet_cidr)[1]
  private_ips = [for i in range(var.cluster_size) : cidrhost(var.private_subnet_cidr, var.ip_offset + i)]
}

resource "proxmox_vm_qemu" "api" {
  count = var.cluster_size

  name        = "${var.prefix}api-${count.index}"
  target_node = var.pve_node
  clone       = var.base_template
  full_clone  = true

  agent    = 1
  os_type  = "cloud-init"
  cpu      = "host"
  cores    = var.cpu_cores
  sockets  = 1
  memory   = var.memory_mb
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  onboot   = true

  disk {
    slot     = 0
    type     = "scsi"
    storage  = var.pve_storage_pool
    size     = "${var.disk_size_gb}G"
    iothread = 1
  }

  network {
    bridge = var.private_bridge
    model  = "virtio"
  }

  ipconfig0  = "ip=${local.private_ips[count.index]}/${local.subnet_mask},gw=${var.private_gateway_ip}"
  nameserver = join(" ", var.private_dns_servers)
  ciuser     = "root"
  sshkeys    = var.ssh_public_key

  lifecycle {
    ignore_changes = [
      network,
      ciuser,
      sshkeys,
      ipconfig0,
    ]
  }
}

resource "null_resource" "bootstrap" {
  count = var.cluster_size

  triggers = {
    script_hash = filesha256("${path.module}/scripts/start-api.sh")
    vm_id       = proxmox_vm_qemu.api[count.index].id
  }

  connection {
    type        = "ssh"
    host        = local.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-api.sh", {
      NODE_POOL                    = var.node_pool_name
      PRIVATE_IP                   = local.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(var.consul_retry_join_ips)
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      CONSUL_DNS_REQUEST_TOKEN     = var.consul_dns_request_token
      CONTAINER_REGISTRY_URL       = var.container_registry_url
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-api.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-api.sh",
      "/tmp/start-api.sh",
    ]
  }

  depends_on = [proxmox_vm_qemu.api]
}
