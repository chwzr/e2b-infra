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

resource "proxmox_vm_qemu" "control_server" {
  count = var.cluster_size

  name        = "${var.prefix}server-${count.index}"
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
    script_hash = filesha256("${path.module}/scripts/start-server.sh")
    vm_id       = proxmox_vm_qemu.control_server[count.index].id
  }

  connection {
    type        = "ssh"
    host        = local.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-server.sh", {
      NUM_SERVERS                  = var.cluster_size
      PRIVATE_IP                   = local.private_ips[count.index]
      CONSUL_RETRY_JOIN            = jsonencode(local.private_ips)
      NOMAD_TOKEN                  = var.nomad_acl_token
      CONSUL_TOKEN                 = var.consul_acl_token
      CONSUL_GOSSIP_ENCRYPTION_KEY = var.consul_gossip_encryption_key
      DATACENTER                   = var.datacenter
    })
    destination = "/tmp/start-server.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/start-server.sh",
      "/tmp/start-server.sh",
    ]
  }

  depends_on = [proxmox_vm_qemu.control_server]
}
