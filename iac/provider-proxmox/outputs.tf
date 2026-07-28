output "ingress_private_ip" {
  value       = module.cluster.ingress_private_ip
  description = "Private IP of the Traefik ingress VM. DNAT public 80/443 on the PVE host to this IP:8080 to expose the cluster externally."
}

output "control_server_private_ips" {
  value       = module.cluster.control_server_private_ips
  description = "Private IPs of the Nomad/Consul control servers (useful for retry_join debugging)."
}

output "domain_name" {
  value = var.domain_name
}
