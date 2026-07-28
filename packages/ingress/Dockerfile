ARG TRAEFIK_VERSION=v3.5

# Pull the official Traefik binary out of the FROM-scratch image.
FROM traefik:${TRAEFIK_VERSION} AS traefik

# Alpine base with shell + curl + jq so we can run the ACME "exec" DNS-01
# hook (acme-hcloud-dns.sh) against Hetzner Cloud DNS.
FROM alpine:3.20

RUN apk add --no-cache bash curl jq ca-certificates

COPY --from=traefik /usr/local/bin/traefik /usr/local/bin/traefik
COPY acme-hcloud-dns.sh /usr/local/bin/acme-hcloud-dns.sh
RUN chmod +x /usr/local/bin/acme-hcloud-dns.sh

EXPOSE 80 443 8080
ENTRYPOINT ["/usr/local/bin/traefik"]
