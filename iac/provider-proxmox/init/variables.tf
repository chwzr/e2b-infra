variable "prefix" {
  type = string
}

variable "bucket_prefix" {
  type = string
}

// ---
// Secrets passthrough variables
// These are stored externally (not in a managed secret service)
// and passed through as variables
// ---

variable "postgres_connection_string" {
  type      = string
  default   = " "
  sensitive = true
}

variable "supabase_jwt_secrets" {
  type      = string
  default   = " "
  sensitive = true
}

variable "launch_darkly_api_key" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_api_key" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_otlp_url" {
  type    = string
  default = " "
}

variable "grafana_otel_collector_token" {
  type      = string
  default   = " "
  sensitive = true
}

variable "grafana_username" {
  type    = string
  default = " "
}

variable "grafana_logs_user" {
  type    = string
  default = " "
}

variable "grafana_logs_url" {
  type    = string
  default = " "
}

variable "grafana_logs_collector_api_token" {
  type      = string
  default   = " "
  sensitive = true
}
