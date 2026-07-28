output "ingress_private_ip" {
  value       = module.cluster.ingress_private_ip
  description = "Private IP of the Traefik ingress server. Point public 80/443 at this host (or a load balancer in front of it)."
}

output "control_server_private_ips" {
  value       = module.cluster.control_server_private_ips
  description = "Private IPs of the Nomad/Consul control servers (useful for retry_join debugging)."
}

output "domain_name" {
  value = var.domain_name
}
