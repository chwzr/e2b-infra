// ---
// Network
// ---
output "network_id" {
  value = module.network.network_id
}

output "subnet_id" {
  value = module.network.subnet_id
}

// ---
// SSH
// ---
output "ssh_key_id" {
  value = hcloud_ssh_key.cluster.id
}
