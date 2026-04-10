output "network_id" {
  value = hcloud_network.cluster.id
}

output "subnet_id" {
  value = hcloud_network_subnet.cluster.id
}

output "vswitch_subnet_id" {
  value = var.vswitch_id != null ? hcloud_network_subnet.vswitch[0].id : null
}
