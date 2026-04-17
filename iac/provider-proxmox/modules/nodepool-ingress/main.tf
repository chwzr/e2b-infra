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
  private_mask = split("/", var.private_subnet_cidr)[1]
  private_ip   = cidrhost(var.private_subnet_cidr, var.private_ip_offset)
}

resource "proxmox_vm_qemu" "ingress" {
  name        = "${var.prefix}ingress"
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

  # NIC 0 — public bridge (default gateway, ingress traffic)
  network {
    bridge = var.public_bridge
    model  = "virtio"
  }

  # NIC 1 — private bridge (cluster traffic)
  network {
    bridge = var.private_bridge
    model  = "virtio"
  }

  ipconfig0  = "ip=${var.public_ip}/${var.public_cidr_bit},gw=${var.public_gateway}"
  ipconfig1  = "ip=${local.private_ip}/${local.private_mask}"
  nameserver = join(" ", var.private_dns_servers)
  ciuser     = "root"
  sshkeys    = var.ssh_public_key

  lifecycle {
    ignore_changes = [
      network,
      ciuser,
      sshkeys,
      ipconfig0,
      ipconfig1,
    ]
  }
}

resource "null_resource" "bootstrap" {
  triggers = {
    script_hash = filesha256("${path.module}/scripts/start-ingress.sh")
    vm_id       = proxmox_vm_qemu.ingress.id
  }

  connection {
    type        = "ssh"
    host        = local.private_ip
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"
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

  depends_on = [proxmox_vm_qemu.ingress]
}
