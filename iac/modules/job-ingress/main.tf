locals {
  traefik_config = templatefile("${path.module}/jobs/traefik.toml", {
    ingress_port     = var.ingress_proxy_port
    ingress_tls_port = var.ingress_proxy_tls_port
    control_port     = var.ingress_control_port
    acme_email       = var.acme_email
    domain_name      = var.domain_name

    nomad_endpoint = var.nomad_endpoint
    nomad_token    = var.nomad_token

    consul_endpoint = var.consul_endpoint
    consul_token    = var.consul_token

    otel_collector_grpc_endpoint = var.otel_collector_grpc_endpoint
  })
}

resource "nomad_job" "ingress" {
  jobspec = templatefile("${path.module}/jobs/ingress.hcl", {
    count         = var.ingress_count
    node_pool     = var.node_pool
    update_stanza = var.update_stanza
    cpu_count     = var.ingress_cpu_count
    memory_mb     = var.ingress_memory_mb

    ingress_port     = var.ingress_proxy_port
    ingress_tls_port = var.ingress_proxy_tls_port
    control_port     = var.ingress_control_port

    traefik_config = local.traefik_config
    config_files   = var.traefik_config_files
  })
}
