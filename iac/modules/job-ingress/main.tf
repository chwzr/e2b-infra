locals {
  traefik_config = templatefile("${path.module}/jobs/traefik.toml", {
    ingress_port     = var.ingress_proxy_port
    ingress_tls_port = var.ingress_proxy_tls_port
    control_port     = var.ingress_control_port
    acme_email       = var.acme_email
    domain_name      = var.domain_name
    hcloud_token     = var.hcloud_token

    nomad_endpoint = var.nomad_endpoint
    nomad_token    = var.nomad_token

    consul_endpoint = var.consul_endpoint
    consul_token    = var.consul_token

    otel_collector_grpc_endpoint = var.otel_collector_grpc_endpoint
  })

  # When DNS-01 is configured, inject a dummy file-provider router whose sole
  # purpose is to carry `tls.domains = {apex, *.apex}` — Traefik only eager-
  # issues certs from router-level tls.domains, not entrypoint-level.
  # The rule matches a host nobody will ever send, so it won't shadow real
  # routes. Cert goes straight into acme.json and is served for any SNI match.
  acme_wildcard_config_files = var.hcloud_token != "" && var.domain_name != "" ? {
    "wildcard.toml" = <<-EOT
      [http.routers.wildcard-cert-trigger]
        rule        = "Host(`acme-wildcard-trigger.${var.domain_name}`)"
        service     = "noop@internal"
        entryPoints = ["websecure"]
        [http.routers.wildcard-cert-trigger.tls]
          certResolver = "letsencrypt"
          [[http.routers.wildcard-cert-trigger.tls.domains]]
            main = "${var.domain_name}"
            sans = ["*.${var.domain_name}"]
    EOT
  } : {}
}

resource "nomad_job" "ingress" {
  jobspec = templatefile("${path.module}/jobs/ingress.hcl", {
    count         = var.ingress_count
    node_pool     = var.node_pool
    update_stanza = var.update_stanza
    cpu_count     = var.ingress_cpu_count
    memory_mb     = var.ingress_memory_mb
    ingress_image = var.ingress_image

    ingress_port     = var.ingress_proxy_port
    ingress_tls_port = var.ingress_proxy_tls_port
    control_port     = var.ingress_control_port

    hcloud_token   = var.hcloud_token
    hcloud_zone    = var.hcloud_zone
    hcloud_zone_id = var.hcloud_zone_id

    traefik_config = local.traefik_config
    config_files   = merge(var.traefik_config_files, local.acme_wildcard_config_files)
  })
}
