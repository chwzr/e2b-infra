variable "nomad_token" {
  type      = string
  sensitive = true
}

variable "nomad_endpoint" {
  type    = string
  default = "http://localhost:4646"
}

variable "consul_token" {
  type      = string
  sensitive = true
}

variable "consul_endpoint" {
  type    = string
  default = "http://localhost:8500"
}

variable "ingress_proxy_port" {
  type = number
}

variable "ingress_proxy_tls_port" {
  type        = number
  default     = 8443
  description = "HTTPS entrypoint (websecure) port on the ingress VM. PVE DNAT 443 → this."
}

variable "ingress_control_port" {
  type    = number
  default = 8900
}

variable "acme_email" {
  type        = string
  default     = ""
  description = "Contact email for Let's Encrypt. When set, Traefik requests certs via HTTP-01 for any Host it sees. Leave empty to disable TLS on websecure."
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "Domain suffix used to pre-issue ACME certs for well-known subdomains (api.DOMAIN, nomad.DOMAIN)."
}

variable "node_pool" {
  type = string
}

variable "update_stanza" {
  type = bool
}

variable "ingress_count" {
  type = number
}

variable "ingress_cpu_count" {
  type    = number
  default = 1
}

variable "ingress_memory_mb" {
  type    = number
  default = 512
}

variable "otel_collector_grpc_endpoint" {
  type        = string
  description = "OpenTelemetry collector gRPC endpoint (e.g., localhost:4317)"
}

variable "traefik_config_files" {
  type        = map(string)
  description = "Map of filename => content for additional Traefik dynamic configuration files"
}
