#!/bin/bash
# ACME DNS-01 "exec" provider script for lego (bundled with Traefik).
#
# Lego invokes us with:
#   $0 present|cleanup <fqdn> <value>
# where <fqdn> is the challenge FQDN (e.g. _acme-challenge.e2b.datacards.dev.)
# and <value> is the TXT record content to publish.
#
# Env:
#   HCLOUD_TOKEN    Hetzner Cloud API token with DNS zone access
#   HCLOUD_ZONE     Base zone name (e.g. datacards.dev)
#   HCLOUD_ZONE_ID  Numeric zone id from /v1/zones
#
# The Hetzner Cloud DNS API is rrset-oriented — a single TXT rrset can hold
# multiple values (needed when a cert covers base+wildcard, both challenged
# at the same FQDN). We handle that explicitly on both present and cleanup.

set -euo pipefail

CMD="${1:?missing cmd}"
FQDN="${2:?missing fqdn}"
VALUE="${3:?missing value}"

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN required}"
: "${HCLOUD_ZONE:?HCLOUD_ZONE required}"
: "${HCLOUD_ZONE_ID:?HCLOUD_ZONE_ID required}"

FQDN="${FQDN%.}"
if [[ "$FQDN" == "$HCLOUD_ZONE" ]]; then
  RELATIVE="@"
elif [[ "$FQDN" == *".$HCLOUD_ZONE" ]]; then
  RELATIVE="${FQDN%".$HCLOUD_ZONE"}"
else
  echo "fqdn $FQDN is not under zone $HCLOUD_ZONE" >&2
  exit 1
fi

api() {
  curl -fsS -H "Authorization: Bearer $HCLOUD_TOKEN" -H "Content-Type: application/json" "$@"
}

rrset_url="https://api.hetzner.cloud/v1/zones/$HCLOUD_ZONE_ID/rrsets/$RELATIVE/TXT"
zone_url="https://api.hetzner.cloud/v1/zones/$HCLOUD_ZONE_ID/rrsets"

case "$CMD" in
  present)
    # Try to create the rrset. If it already exists, add to it instead.
    body=$(jq -n --arg n "$RELATIVE" --arg v "\"$VALUE\"" \
      '{name:$n,type:"TXT",ttl:60,records:[{value:$v}]}')
    if api -X POST "$zone_url" -d "$body" >/dev/null 2>&1; then
      exit 0
    fi
    body=$(jq -n --arg v "\"$VALUE\"" '{records:[{value:$v}]}')
    api -X POST "$rrset_url/actions/add_records" -d "$body" >/dev/null
    ;;
  cleanup)
    # Try to remove just our value. If that leaves the rrset empty (or if the
    # call fails because it was the only record), fall back to deleting the
    # whole rrset. Both "record not found" style errors are silently OK.
    body=$(jq -n --arg v "\"$VALUE\"" '{records:[{value:$v}]}')
    if api -X POST "$rrset_url/actions/remove_records" -d "$body" >/dev/null 2>&1; then
      remaining=$(api "$rrset_url" 2>/dev/null | jq '.rrset.records | length' 2>/dev/null || echo 0)
      if [[ "$remaining" == "0" ]]; then
        api -X DELETE "$rrset_url" >/dev/null 2>&1 || true
      fi
    else
      api -X DELETE "$rrset_url" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "unknown cmd: $CMD" >&2
    exit 1
    ;;
esac
