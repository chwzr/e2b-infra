#!/usr/bin/env bash
#
# Configure a Proxmox VE host for E2B self-hosting. Runs on the PVE host as
# root. Idempotent — re-run safely after changing .env values.
#
# Sets up:
#   1. Nested virtualization           (/etc/modprobe.d/kvm-nested.conf)
#   2. IP forwarding                   (/etc/sysctl.d/99-e2b.conf)
#   3. Cluster bridge + SNAT via SDN   (Simple zone "e2bzone", vnet $BRIDGE)
#   4. DNAT 80/443 → ingress VM        (systemd unit e2b-nat.service)
#
# Env vars (defaults match .env.proxmox.template):
#   BRIDGE          cluster bridge name, ≤ 8 chars for SDN VNet   (vmbr1)
#   SUBNET_CIDR     cluster subnet                                (10.0.0.0/24)
#   GATEWAY_IP      PVE host IP on $BRIDGE (acts as gateway)      (10.0.0.1)
#   INGRESS_IP      Traefik ingress VM's private IP               (10.0.0.41)
#   INGRESS_PORT    Traefik listens here inside the VM            (8080)
#   PUBLIC_IFACE    public uplink on the host                     (vmbr0)
#
# This script does NOT create the PVE API token — do that manually in the UI.

set -euo pipefail

BRIDGE="${BRIDGE:-vmbr1}"
SUBNET_CIDR="${SUBNET_CIDR:-10.0.0.0/24}"
GATEWAY_IP="${GATEWAY_IP:-10.0.0.1}"
# Ingress IP defaults to the .41 host of $SUBNET_CIDR (matches the ingress
# Terraform module's ip_offset=41). Override INGRESS_IP explicitly if needed.
if [[ -z "${INGRESS_IP:-}" ]]; then
  _base="${SUBNET_CIDR%/*}"
  INGRESS_IP="${_base%.*}.41"
fi
INGRESS_PORT="${INGRESS_PORT:-8080}"
INGRESS_TLS_PORT="${INGRESS_TLS_PORT:-8443}"
PUBLIC_IFACE="${PUBLIC_IFACE:-vmbr0}"
ZONE="${ZONE:-e2bzone}"

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------- preflight ----------

[[ $EUID -eq 0 ]]                            || die "must run as root"
command -v pvesh >/dev/null                  || die "pvesh not found — this is not a Proxmox VE host"
ip link show "$PUBLIC_IFACE" >/dev/null 2>&1 || die "public interface '$PUBLIC_IFACE' does not exist (set PUBLIC_IFACE=...)"
(( ${#BRIDGE} <= 8 ))                        || die "BRIDGE name '$BRIDGE' is too long (Proxmox SDN VNets are ≤ 8 chars)"

# ---------- 1. nested virtualization ----------

log "Step 1: nested virtualization"
if grep -qE '^flags\b.* vmx( |$)' /proc/cpuinfo; then
  KVM_MOD=kvm_intel; MOD_OPT=kvm-intel
elif grep -qE '^flags\b.* svm( |$)' /proc/cpuinfo; then
  KVM_MOD=kvm_amd;   MOD_OPT=kvm-amd
else
  die "CPU has no hardware virtualization flag (vmx/svm) — nested KVM impossible"
fi

conf=/etc/modprobe.d/kvm-nested.conf
nested_active=$(cat "/sys/module/$KVM_MOD/parameters/nested" 2>/dev/null || echo N)

# Persist the setting so nested survives a reboot regardless of runtime state.
if ! grep -qE "^\s*options\s+$MOD_OPT\s+nested=1\b" "$conf" 2>/dev/null; then
  printf 'options %s nested=1\n' "$MOD_OPT" > "$conf"
  log "persisted $MOD_OPT nested=1 in $conf"
else
  log "$conf already declares $MOD_OPT nested=1"
fi

# Only attempt to reload the module if nested isn't already active. Reloading
# while guests are running typically fails with EBUSY / "Invalid argument".
if [[ $nested_active == Y || $nested_active == 1 ]]; then
  log "nested virt already active at runtime (kvm_mod=$KVM_MOD)"
else
  if modprobe -r "$KVM_MOD" 2>/dev/null && modprobe "$KVM_MOD"; then
    log "reloaded $KVM_MOD with nested=1"
  else
    warn "could not reload $KVM_MOD (guests may be holding /dev/kvm)."
    warn "Config persisted — reboot the PVE host to activate nested virt."
  fi
fi

# ---------- 2. IP forwarding ----------

log "Step 2: IP forwarding"
cat > /etc/sysctl.d/99-e2b.conf <<'EOF'
# Managed by setup-pve-host.sh — required for the PVE host to route between
# the cluster bridge and the public uplink.
net.ipv4.ip_forward=1
EOF
sysctl --quiet -p /etc/sysctl.d/99-e2b.conf

# ---------- 3. cluster bridge + SNAT (SDN) ----------

log "Step 3: cluster bridge ($BRIDGE) + SNAT"
if grep -qE "^\s*iface\s+$BRIDGE\s" /etc/network/interfaces 2>/dev/null; then
  warn "$BRIDGE is already defined in /etc/network/interfaces."
  warn "Skipping SDN setup — this script did NOTHING for the cluster bridge."
  warn "Verify manually that:"
  warn "  - $BRIDGE has address $GATEWAY_IP on $SUBNET_CIDR"
  warn "  - traffic from $SUBNET_CIDR is MASQUERADEd out $PUBLIC_IFACE"
  warn "Remove the manual stanza and re-run if you want SDN to own this."
else
  if ! pvesh get "/cluster/sdn/zones/$ZONE" >/dev/null 2>&1; then
    log "creating SDN zone '$ZONE' (type=simple, ipam=pve)"
    pvesh create /cluster/sdn/zones --type simple --zone "$ZONE" --ipam pve
  fi

  if ! pvesh get "/cluster/sdn/vnets/$BRIDGE" >/dev/null 2>&1; then
    log "creating SDN vnet '$BRIDGE' in zone '$ZONE'"
    pvesh create /cluster/sdn/vnets --vnet "$BRIDGE" --zone "$ZONE"
  fi

  # Subnet IDs are "<zone>-<cidr>" with '/' → '-'. Try-create + detect
  # "already exists" so we don't depend on jq.
  if out=$(pvesh create "/cluster/sdn/vnets/$BRIDGE/subnets" \
      --subnet "$SUBNET_CIDR" --type subnet \
      --gateway "$GATEWAY_IP" --snat 1 2>&1); then
    log "created SDN subnet $SUBNET_CIDR (gateway $GATEWAY_IP, SNAT on)"
  elif [[ $out == *"already exists"* || $out == *"already defined"* ]]; then
    log "SDN subnet $SUBNET_CIDR already exists"
  else
    printf '%s\n' "$out" >&2
    die "failed to create SDN subnet"
  fi

  log "committing SDN config (pvesh set /cluster/sdn — reloads networking)"
  pvesh set /cluster/sdn
fi

# ---------- 4. DNAT + FORWARD via systemd unit ----------

log "Step 4: DNAT 80/443 → $INGRESS_IP:$INGRESS_PORT"

cat > /usr/local/sbin/e2b-nat-up <<'EOF'
#!/usr/bin/env bash
# Installed by setup-pve-host.sh.
# Reads: INGRESS_IP, INGRESS_PORT, INGRESS_TLS_PORT, PUBLIC_IFACE.
set -e
: "${INGRESS_IP:?}"
: "${INGRESS_PORT:?}"
: "${INGRESS_TLS_PORT:?}"
: "${PUBLIC_IFACE:?}"
# 80 → HTTP entrypoint (also used by Let's Encrypt HTTP-01)
iptables -t nat -C PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 80 \
  -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT" 2>/dev/null \
|| iptables -t nat -A PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 80 \
  -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT"
# 443 → HTTPS (websecure) entrypoint
iptables -t nat -C PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
  -j DNAT --to-destination "$INGRESS_IP:$INGRESS_TLS_PORT" 2>/dev/null \
|| iptables -t nat -A PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
  -j DNAT --to-destination "$INGRESS_IP:$INGRESS_TLS_PORT"
# FORWARD accepts — one per port
for p in "$INGRESS_PORT" "$INGRESS_TLS_PORT"; do
  iptables -C FORWARD -d "$INGRESS_IP/32" -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -d "$INGRESS_IP/32" -p tcp --dport "$p" -j ACCEPT
done
EOF

cat > /usr/local/sbin/e2b-nat-down <<'EOF'
#!/usr/bin/env bash
# Installed by setup-pve-host.sh.
# Reads: INGRESS_IP, INGRESS_PORT, INGRESS_TLS_PORT, PUBLIC_IFACE.
set +e
: "${INGRESS_IP:?}"
: "${INGRESS_PORT:?}"
: "${INGRESS_TLS_PORT:?}"
: "${PUBLIC_IFACE:?}"
# 80 → INGRESS_PORT
while iptables -t nat -C PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 80 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT" 2>/dev/null; do
  iptables -t nat -D PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 80 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT"
done
# 443 → INGRESS_TLS_PORT
while iptables -t nat -C PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_TLS_PORT" 2>/dev/null; do
  iptables -t nat -D PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_TLS_PORT"
done
# Also clean up legacy rules that forwarded 443 → INGRESS_PORT (single-port layout).
while iptables -t nat -C PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT" 2>/dev/null; do
  iptables -t nat -D PREROUTING -i "$PUBLIC_IFACE" -p tcp --dport 443 \
    -j DNAT --to-destination "$INGRESS_IP:$INGRESS_PORT"
done
for p in "$INGRESS_PORT" "$INGRESS_TLS_PORT"; do
  while iptables -C FORWARD -d "$INGRESS_IP/32" -p tcp --dport "$p" -j ACCEPT 2>/dev/null; do
    iptables -D FORWARD -d "$INGRESS_IP/32" -p tcp --dport "$p" -j ACCEPT
  done
done
exit 0
EOF

chmod +x /usr/local/sbin/e2b-nat-up /usr/local/sbin/e2b-nat-down

cat > /etc/systemd/system/e2b-nat.service <<EOF
[Unit]
Description=E2B DNAT/FORWARD rules for ingress VM
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=INGRESS_IP=$INGRESS_IP
Environment=INGRESS_PORT=$INGRESS_PORT
Environment=INGRESS_TLS_PORT=$INGRESS_TLS_PORT
Environment=PUBLIC_IFACE=$PUBLIC_IFACE
ExecStart=/usr/local/sbin/e2b-nat-up
ExecStop=/usr/local/sbin/e2b-nat-down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
# restart (not start) so rule changes after .env edits re-apply cleanly
systemctl restart e2b-nat.service
systemctl enable e2b-nat.service >/dev/null 2>&1

# ---------- summary ----------

cat <<EOF

DONE.

Next steps (manual):
  1. Create a Proxmox API token for Terraform:
       Datacenter → Permissions → API Tokens → Add
     Uncheck "Privilege Separation" so it inherits the user's roles.
     For non-root users, grant PVEVMAdmin on /, Datastore.Allocate on the
     storage pool, and Sys.Audit on / (replaces VM.Monitor in PVE 9).
     Copy the token ID and secret into your .env.

  2. Verify on this host:
       ip -4 addr show $BRIDGE | grep -w $GATEWAY_IP
       iptables -t nat -L PREROUTING -n | grep $INGRESS_IP:$INGRESS_PORT
       systemctl status e2b-nat.service
       cat /sys/module/$KVM_MOD/parameters/nested   # expect Y (Intel) or 1 (AMD)
EOF
