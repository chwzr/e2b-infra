output "network_id" {
  value = hcloud_network.cluster.id
}

output "subnet_id" {
  value = hcloud_network_subnet.cluster.id
}
