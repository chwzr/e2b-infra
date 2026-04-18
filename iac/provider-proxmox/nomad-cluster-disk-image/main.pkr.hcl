packer {
  required_version = ">=1.8.4"

  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

source "proxmox-iso" "ubuntu" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_tls_insecure

  node                 = var.proxmox_node
  vm_id                = var.vm_id
  vm_name              = "${var.template_name}-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
  template_name        = var.template_name
  template_description = "E2B Nomad cluster base image (Ubuntu 24.04) built by Packer"

  cpu_type = "host"
  cores    = 2
  memory   = 4096
  os       = "l26"

  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "20G"
    storage_pool = var.template_storage
    type         = "scsi"
    format       = var.disk_format
    io_thread    = true
  }

  network_adapters {
    bridge = var.packer_build_bridge
    model  = "virtio"
  }

  # Ubuntu 24.04 Server ISO — download it into the PVE ISO storage ahead of time,
  # or set iso_url to have Packer fetch it.
  boot_iso {
    type         = "scsi"
    iso_file     = var.iso_file
    unmount      = true
    iso_checksum = var.iso_checksum
  }

  cloud_init              = true
  cloud_init_storage_pool = var.template_storage

  # Ubuntu autoinstall (subiquity) — Packer serves user-data + meta-data over HTTP
  http_directory = "${path.root}/http"
  boot_wait      = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\"<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]

  ssh_username         = "root"
  ssh_password         = var.build_ssh_password
  ssh_timeout          = "30m"
  ssh_pty              = true
  ssh_handshake_attempts = 100
}

locals {
  shared_setup_dir = "${path.root}/../../nomad-cluster-disk-image/setup"
}

build {
  sources = ["source.proxmox-iso.ubuntu"]

  provisioner "file" {
    source      = "${local.shared_setup_dir}/supervisord.conf"
    destination = "/tmp/supervisord.conf"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}/daemon.json"
    destination = "/tmp/daemon.json"
  }

  provisioner "file" {
    source      = "${local.shared_setup_dir}/limits.conf"
    destination = "/tmp/limits.conf"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /etc/docker",
      "mv /tmp/daemon.json /etc/docker/daemon.json",
      "curl -fsSL https://get.docker.com -o /tmp/get-docker.sh",
      "sh /tmp/get-docker.sh",
      "rm -f /tmp/get-docker.sh",
    ]
  }

  provisioner "shell" {
    inline = [
      "apt-get update",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y nvme-cli unzip jq net-tools qemu-utils make build-essential openssh-client openssh-server nfs-common qemu-guest-agent dnsutils netcat-openbsd cloud-init",
    ]
  }

  provisioner "shell" {
    inline = [
      "snap install go --classic || apt-get install -y golang-go",
    ]
  }

  provisioner "shell" {
    inline = [
      "systemctl enable docker",
      "systemctl enable qemu-guest-agent",
    ]
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/gruntwork",
      "git clone --branch v0.1.3 https://github.com/gruntwork-io/bash-commons.git /tmp/bash-commons",
      "cp -r /tmp/bash-commons/modules/bash-commons/src /opt/gruntwork/bash-commons",
      "rm -rf /tmp/bash-commons",
    ]
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-consul.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.consul_version}"
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-nomad.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.nomad_version}"
  }

  provisioner "shell" {
    script          = "${local.shared_setup_dir}/install-vault.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }} --version ${var.vault_version}"
  }

  provisioner "shell" {
    inline = [
      "mkdir -p /opt/nomad/plugins",
    ]
  }

  # Tune open file limits and conntrack
  provisioner "shell" {
    inline = [
      "mv /tmp/limits.conf /etc/security/limits.conf",
      "echo 'net.netfilter.nf_conntrack_max = 2097152' >> /etc/sysctl.conf",
    ]
  }

  # Clean cloud-init state so new clones re-initialise with their own cloud-init config
  provisioner "shell" {
    inline = [
      "cloud-init clean --logs",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
    ]
  }
}
