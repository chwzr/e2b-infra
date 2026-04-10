locals {
  domain_parts        = split(".", var.domain_name)
  domain_is_subdomain = length(local.domain_parts) > 2

  // Take last 2 parts (root domain)
  domain_root = local.domain_is_subdomain ? join(".", slice(local.domain_parts, length(local.domain_parts) - 2, length(local.domain_parts))) : var.domain_name
}

data "hcloud_zone" "domain" {
  name = local.domain_root
}

# Wildcard DNS record pointing to the load balancer
resource "hcloud_zone_rrset" "wildcard" {
  zone = data.hcloud_zone.domain.name
  name = "*"
  type = "A"
  ttl  = 3600
  records = [
    { value = hcloud_load_balancer.ingress.ipv4 },
  ]
}
