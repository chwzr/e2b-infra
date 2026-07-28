# Per-nodepool private IPs of your pre-provisioned Ubuntu 24.04 servers.
# Each server must have the deploy SSH public key on root and be reachable
# from the deploy host. orchestrator + build hosts must expose /dev/kvm.
control_server_ips = ["10.0.0.10", "10.0.0.11", "10.0.0.12"]
api_ips            = ["10.0.0.20"]
ingress_ips        = ["10.0.0.30"]
orchestrator_ips   = ["10.0.0.40"]
build_ips          = ["10.0.0.50"]
clickhouse_ips     = ["10.0.0.60"]

# Optional: override pinned tool versions (defaults shown).
# consul_version = "1.16.2"
# nomad_version  = "1.6.2"
# vault_version  = "1.20.3"
