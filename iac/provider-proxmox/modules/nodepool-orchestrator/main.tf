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

resource "proxmox_vm_qemu" "orchestrator" {
  count = var.cluster_size

  name        = "${var.prefix}orchestrator-${count.index}"
  target_node = var.pve_node
  clone       = var.base_template
  full_clone  = true

  agent   = 1
  os_type = "cloud-init"
  # Nested KVM: cpu = "host" passes the full CPU model through so Firecracker
  # can see KVM inside the VM. The Proxmox host must have nested virt enabled
  # (/sys/module/kvm_intel/parameters/nested = Y or kvm_amd).
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
    script_hash = filesha256("${path.module}/scripts/start-orchestrator.sh")
    vm_id       = proxmox_vm_qemu.orchestrator[count.index].id
  }

  connection {
    type        = "ssh"
    host        = local.private_ips[count.index]
    user        = "root"
    private_key = var.ssh_private_key
    timeout     = "5m"
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

  depends_on = [proxmox_vm_qemu.orchestrator]
}
