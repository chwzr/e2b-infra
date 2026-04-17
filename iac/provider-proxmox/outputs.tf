output "ingress_public_ip" {
  value       = var.ingress_public_ip
  description = "Public IP of the Traefik ingress VM. Create a wildcard A record (*.<domain_name>) pointing here in your DNS provider."
}

output "control_server_private_ips" {
  value       = module.cluster.control_server_private_ips
  description = "Private IPs of the Nomad/Consul control servers (useful for retry_join debugging)."
}

output "domain_name" {
  value = var.domain_name
}
