output "control_server_private_ips" {
  value = module.control_server.private_ips
}

output "api_private_ips" {
  value = module.api.private_ips
}

output "ingress_private_ip" {
  value = module.ingress.private_ip
}

output "ingress_public_ip" {
  value = module.ingress.public_ip
}

output "orchestrator_private_ips" {
  value = module.orchestrator.private_ips
}

output "build_private_ips" {
  value = module.build.private_ips
}

output "clickhouse_private_ips" {
  value = module.clickhouse.private_ips
}
