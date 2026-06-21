resource "random_uuid" "nomad_acl_token" {}

resource "random_uuid" "consul_acl_token" {}

resource "random_uuid" "consul_dns_request_token" {}

resource "random_id" "consul_gossip_encryption_key" {
  byte_length = 32
}

output "cluster" {
  sensitive = true
  value = {
    nomad_acl_token              = random_uuid.nomad_acl_token.id
    consul_acl_token             = random_uuid.consul_acl_token.id
    consul_dns_request_token     = random_uuid.consul_dns_request_token.id
    consul_gossip_encryption_key = random_id.consul_gossip_encryption_key.b64_std
  }
}
