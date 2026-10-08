#!/bin/sh
# Ensures the ES256 keypair for node-agent's direct alert stream exists:
#   $NS/node-agent-direct-jwt      key.pem    dx-daemon signs its bearer tokens
#   $NS/node-agent-direct-jwt-pub  public.pem node-agent verifies them
# Create-if-absent: an existing pair is never touched, so a second run changes
# nothing. The private key is never written to disk.
set -eu
NS=${NS:-honey}
PRIV=node-agent-direct-jwt
PUB=node-agent-direct-jwt-pub

has() { kubectl -n "$NS" get secret "$1" >/dev/null 2>&1; }

if has "$PRIV"; then
  has "$PUB" && exit 0
  # Public half missing: derive it from the existing private key.
  kubectl -n "$NS" get secret "$PRIV" -o jsonpath='{.data.key\.pem}' | base64 -d \
    | openssl ec -pubout 2>/dev/null \
    | kubectl -n "$NS" create secret generic "$PUB" --from-file=public.pem=/dev/stdin
  exit 0
fi

# No private key: mint a pair. A public half left without its private key
# verifies nothing, so it is replaced.
key=$(openssl ecparam -name prime256v1 -genkey -noout)
printf '%s\n' "$key" | kubectl -n "$NS" create secret generic "$PRIV" --from-file=key.pem=/dev/stdin
printf '%s\n' "$key" | openssl ec -pubout 2>/dev/null \
  | kubectl -n "$NS" create secret generic "$PUB" --from-file=public.pem=/dev/stdin --dry-run=client -o yaml \
  | kubectl apply -f - >/dev/null
