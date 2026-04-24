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

resource "proxmox_virtual_environment_vm" "orchestrator" {
  count = var.cluster_size

  name      = "${var.prefix}orchestrator-${count.index}"
  node_name = var.pve_node
  on_boot   = true

  agent {
    enabled = true
  }

  clone {
    vm_id = var.base_template_vm_id
    full  = true
  }

  # Nested KVM: cpu.type = "host" passes the full CPU model through so Firecracker
  # can see KVM inside the VM. The Proxmox host must have nested virt enabled
  # (/sys/module/kvm_intel/parameters/nested = Y or kvm_amd).
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
    script_hash = filesha256("${path.module}/scripts/start-orchestrator.sh")
    vm_id       = proxmox_virtual_environment_vm.orchestrator[count.index].id
  }

  connection {
    type        = "ssh"
    host        = local.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"

    bastion_host        = var.ssh_bastion_host != "" ? var.ssh_bastion_host : null
    bastion_user        = var.ssh_bastion_host != "" ? var.ssh_bastion_user : null
    bastion_private_key = var.ssh_bastion_host != "" ? var.ssh_private_key : null
  }

  provisioner "file" {
    content = templatefile("${path.module}/scripts/start-orchestrator.sh", {
      NODE_POOL                    = var.node_pool_name
      NODE_LABELS                  = join(",", var.node_labels)
      BASE_HUGEPAGES_PERCENTAGE    = var.base_hugepages_percentage
      PRIVATE_IP                   = local.private_ips[count.index]
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
      "/tmp/start-orchestrator.sh",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.orchestrator]
}
