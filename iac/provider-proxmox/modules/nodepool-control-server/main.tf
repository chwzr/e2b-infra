terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  subnet_mask = split("/", var.subnet_cidr)[1]
  private_ips = [for i in range(var.cluster_size) : cidrhost(var.subnet_cidr, var.ip_offset + i)]
}

resource "proxmox_virtual_environment_vm" "control_server" {
  count = var.cluster_size

  name      = "${var.prefix}server-${count.index}"
  node_name = var.pve_node
  on_boot   = true

  agent {
    enabled = true
  }

  clone {
    vm_id = var.base_template_vm_id
    full  = true
  }

  cpu {
    type    = "host"
    sockets = 1
    cores   = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]

  disk {
    interface    = "scsi0"
    datastore_id = var.pve_storage_pool
    size         = var.disk_size_gb
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
    mtu    = 1500
  }

  initialization {
    datastore_id = var.pve_storage_pool

    user_account {
      username = "root"
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = "${local.private_ips[count.index]}/${local.subnet_mask}"
        gateway = var.gateway_ip
      }
    }

    dns {
      servers = var.dns_servers
    }
  }

  lifecycle {
    ignore_changes = [
      initialization,
      network_device,
    ]
  }
}

resource "null_resource" "bootstrap" {
  count = var.cluster_size

  triggers = {
    script_hash = filesha256("${path.module}/scripts/start-server.sh")
    vm_id       = proxmox_virtual_environment_vm.control_server[count.index].id
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

  depends_on = [proxmox_virtual_environment_vm.control_server]
}
