// ---
// Clickhouse
// ---
resource "random_string" "clickhouse_password" {
  length  = 32
  special = false
}

resource "random_string" "clickhouse_server_secret" {
  length  = 32
  special = false
}

output "clickhouse" {
  value = {
    username      = "e2b"
    password      = random_string.clickhouse_password.result
    server_secret = random_string.clickhouse_server_secret.result
  }
  sensitive = true
}

// ---
// Grafana
// ---
output "grafana" {
  value = {
    api_key                  = var.grafana_api_key
    otlp_url                 = var.grafana_otlp_url
    otel_collector_token     = var.grafana_otel_collector_token
    username                 = var.grafana_username
    logs_user                = var.grafana_logs_user
    logs_url                 = var.grafana_logs_url
    logs_collector_api_token = var.grafana_logs_collector_api_token
  }
  sensitive = true
}

// ---
// API Secret
// ---
resource "random_string" "api_secret" {
  length  = 32
  special = false
}

output "api_secret" {
  value     = random_string.api_secret.result
  sensitive = true
}

// ---
// Admin Token
// ---
resource "random_string" "admin_token" {
  length  = 32
  special = false
}

output "admin_token" {
  value     = random_string.admin_token.result
  sensitive = true
}

// ---
// Sandbox Access Token Hash Seed
// ---
resource "random_string" "sandbox_access_token_hash_seed" {
  length  = 32
  special = false
}

output "sandbox_access_token_hash_seed" {
  value     = random_string.sandbox_access_token_hash_seed.result
  sensitive = true
}

// ---
// Launch Darkly
// ---
output "launch_darkly_api_key" {
  value     = var.launch_darkly_api_key
  sensitive = true
}

// ---
// PostgreSQL
// ---
output "postgres_connection_string" {
  value     = var.postgres_connection_string
  sensitive = true
}

// ---
// Supabase
// ---
output "supabase_jwt_secrets" {
  value     = var.supabase_jwt_secrets
  sensitive = true
}
