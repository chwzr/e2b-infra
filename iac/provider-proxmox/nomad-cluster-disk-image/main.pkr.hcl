packer {
  required_version = ">=1.8.4"

  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# Clones an Ubuntu 24.04 cloud-image base template (prepared one-time by the
# user, see nomad-cluster-disk-image/prepare-base-template.sh) and installs
# Docker, Consul, Nomad, Vault, qemu-guest-agent, and the shared setup scripts.
# The resulting template is what Terraform clones for every node-pool VM.
source "proxmox-clone" "ubuntu" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_tls_insecure

  node                 = var.proxmox_node
  vm_id                = var.vm_id
  vm_name              = "${var.template_name}-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
  template_name        = var.template_name
  template_description = "E2B Nomad cluster base image (Ubuntu 24.04 cloud image) built by Packer"

  clone_vm_id = var.cloudimg_base_vm_id
  full_clone  = true

  cpu_type = "host"
  cores    = 2
  memory   = 4096
  os       = "l26"
  onboot   = false

  scsi_controller = "virtio-scsi-single"

  network_adapters {
    bridge = var.packer_build_bridge
    model  = "virtio"
  }

  # The base template already carries a cloud-init drive + the SSH public key
  # baked in via `qm set --ciuser ubuntu --sshkeys ...` during prepare-base-template.sh.
  # Packer SSHes in as `ubuntu` using the matching private key, then runs
  # provisioners with `sudo` (matches the GCP/AWS Packer flow).
  cloud_init              = true
  cloud_init_storage_pool = var.template_storage

  # Static IP for the Packer build VM. The cluster bridge has no DHCP — all
  # VMs (including this ephemeral builder) get IPs via cloud-init.
  ipconfig {
    ip      = var.build_ip
    gateway = var.build_gateway
  }
  nameserver = var.build_nameserver

  ssh_username           = "ubuntu"
  ssh_private_key_file   = var.ssh_private_key_file
  ssh_timeout            = "10m"
  ssh_handshake_attempts = 100
  ssh_pty                = true

  # Use the static IP from ipconfig directly rather than polling qemu-guest-agent
  # for discovery. The agent isn't running in the freshly-cloned cloud image — it
  # gets installed during Packer provisioning. Without this override, Packer
  # loops on `500 QEMU guest agent is not running` until ssh_timeout.
  ssh_host = split("/", var.build_ip)[0]

  # Bastion / jump host. Packer runs SSH from wherever `packer build` is
  # invoked; when that's outside the cluster subnet, the build VM's private IP
  # is unreachable directly. Configure a bastion (typically the PVE host) to
  # route SSH through. All four fields default to empty/harmless values — the
  # block is only active when ssh_bastion_host is set.
  ssh_bastion_host             = var.ssh_bastion_host
  ssh_bastion_port             = var.ssh_bastion_port
  ssh_bastion_username         = var.ssh_bastion_username
  ssh_bastion_private_key_file = coalesce(var.ssh_bastion_private_key_file, var.ssh_private_key_file)
}

locals {
  shared_setup_dir = "${path.root}/../../nomad-cluster-disk-image/setup"
}

build {
  sources = ["source.proxmox-clone.ubuntu"]

  # Wait for cloud-init to finish before doing anything else. Ubuntu cloud
  # images run apt-get update / unattended-upgrades on first boot, which holds
  # the dpkg frontend lock and conflicts with the Docker install script below.
  # `cloud-init status --wait` returns exit 2 for "done with recoverable
  # errors" (typical on fresh cloud images — non-critical modules like
  # update-hostname or ssh-authkey-fingerprints occasionally fail). The key
  # modules (network, ssh) already succeeded since Packer connected — tolerate
  # exit 2 and let later provisioners surface any real problem.
  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait || [ $? -eq 2 ]",
    ]
  }

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

  # Install Docker
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/docker",
      "sudo mv /tmp/daemon.json /etc/docker/daemon.json",
      "curl -fsSL https://get.docker.com -o /tmp/get-docker.sh",
      "sudo sh /tmp/get-docker.sh",
      "rm -f /tmp/get-docker.sh",
    ]
  }

  # Base packages
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvme-cli unzip jq net-tools qemu-utils make build-essential openssh-client openssh-server nfs-common qemu-guest-agent dnsutils netcat-openbsd cloud-init",
    ]
  }

  # Go
  provisioner "shell" {
    inline = [
      "sudo snap install go --classic || sudo apt-get install -y golang-go",
    ]
  }

  # Enable docker + qemu-guest-agent so they start on first boot of cloned VMs
  provisioner "shell" {
    inline = [
      "sudo systemctl enable docker",
      "sudo systemctl enable qemu-guest-agent",
    ]
  }

  # bash-commons (required by install-consul.sh / install-nomad.sh / install-vault.sh)
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/gruntwork",
      "git clone --branch v0.1.3 https://github.com/gruntwork-io/bash-commons.git /tmp/bash-commons",
      "sudo cp -r /tmp/bash-commons/modules/bash-commons/src /opt/gruntwork/bash-commons",
      "rm -rf /tmp/bash-commons",
    ]
  }

  # Consul / Nomad / Vault (scripts already sudo internally)
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
      "sudo mkdir -p /opt/nomad/plugins",
    ]
  }

  # Tune open-file limits and conntrack
  provisioner "shell" {
    inline = [
      "sudo mv /tmp/limits.conf /etc/security/limits.conf",
      "echo 'net.netfilter.nf_conntrack_max = 2097152' | sudo tee -a /etc/sysctl.conf",
    ]
  }

  # Reset cloud-init and machine-id so each VM cloned from this template
  # re-initialises with its own cloud-init config (IP, hostname, SSH key).
  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
    ]
  }
}
