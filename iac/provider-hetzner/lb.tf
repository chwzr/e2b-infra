resource "hcloud_load_balancer" "ingress" {
  name               = "${var.prefix}ingress"
  load_balancer_type = "lb11"
  location           = var.location
}

resource "hcloud_load_balancer_network" "ingress" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  network_id       = module.init.network_id
}

# HTTPS service — will be configured with TLS when domain/cert is set up
resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

# HTTP service (for redirect or direct access)
resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

# Nomad UI access
resource "hcloud_load_balancer_service" "nomad" {
  load_balancer_id = hcloud_load_balancer.ingress.id
  protocol         = "tcp"
  listen_port      = 4646
  destination_port = 4646

  health_check {
    protocol = "http"
    port     = 4646
    interval = 15
    timeout  = 10
    retries  = 3

    http {
      path = "/v1/agent/health"
    }
  }
}

# Add control servers as targets for Nomad UI
resource "hcloud_load_balancer_target" "control_server" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.ingress.id
  label_selector   = "role=server"
  use_private_ip   = true

  depends_on = [hcloud_load_balancer_network.ingress]
}
