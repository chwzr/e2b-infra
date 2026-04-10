resource "hcloud_firewall" "cluster" {
  name = "${var.prefix}cluster"

  # SSH access
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
    description = "SSH access"
  }

  # Nomad API/UI
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "4646"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
    description = "Nomad API/UI"
  }

  # HTTP
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
    description = "HTTP"
  }

  # HTTPS
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
    description = "HTTPS"
  }

  # Ingress (Traefik)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "8080"
    source_ips = [
      "0.0.0.0/0",
      "::/0",
    ]
    description = "Ingress proxy"
  }
}
