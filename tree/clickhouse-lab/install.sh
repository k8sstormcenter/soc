#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="clickhouse"
CHI="forensic-soc-db"
KEEPER="forensic-keeper"
SKIP_OP=false
# --skip-vector is accepted as a no-op: nothing here installs vector any more.
while [[ $# -gt 0 ]]; do case $1 in --skip-operator) SKIP_OP=true;; --skip-vector) ;; *) echo "Unknown: $1"; exit 1;; esac; shift; done

command -v helm &>/dev/null || { curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; }

# Operator
if ! $SKIP_OP; then
  helm repo add altinity https://helm.altinity.com 2>/dev/null || true
  helm repo update
  helm status clickhouse-operator -n "$NS" &>/dev/null || helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator --version 0.26.0 --namespace "$NS" --create-namespace
fi

# Keeper
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$SCRIPT_DIR/keeper.yaml"
for i in $(seq 1 40); do
  kubectl get pods -n "$NS" -l "clickhouse-keeper.altinity.com/chk=$KEEPER" --no-headers 2>/dev/null | grep -q Running && break
  [[ "$i" -eq 40 ]] && { echo "Keeper failed to start"; exit 1; }
  sleep 3
done

# ClickHouse — apply and wait, with crash-loop recovery (stale PVC configs)
kubectl apply -f "$SCRIPT_DIR/installation.yaml"
CH_OK=false
for i in $(seq 1 60); do
  TOTAL=$(kubectl get pods -n "$NS" -l "clickhouse.altinity.com/chi=$CHI" --no-headers 2>/dev/null | wc -l)
  READY=$(kubectl get pods -n "$NS" -l "clickhouse.altinity.com/chi=$CHI" --no-headers 2>/dev/null | grep -c Running || true)
  CRASH=$(kubectl get pods -n "$NS" -l "clickhouse.altinity.com/chi=$CHI" --no-headers 2>/dev/null | grep -c CrashLoopBackOff || true)
  if [[ "$TOTAL" -gt 0 && "$TOTAL" == "$READY" ]]; then CH_OK=true; break; fi
  # If crash-looping (e.g. stale config checksum on PVC), wipe and retry once
  if [[ "$CRASH" -gt 0 && "$i" -gt 8 ]]; then
    echo "CH crash-loop detected — wiping CHI + PVCs for clean start..."
    kubectl delete chi "$CHI" -n "$NS" --wait 2>/dev/null || true
    kubectl delete pvc -n "$NS" -l "clickhouse.altinity.com/chi=$CHI" --wait 2>/dev/null || true
    sleep 5
    kubectl apply -f "$SCRIPT_DIR/installation.yaml"
  fi
  sleep 5
done
$CH_OK || { echo "ClickHouse failed to start"; exit 1; }
CH_POD=$(kubectl get pods -n "$NS" -l "clickhouse.altinity.com/chi=$CHI" -o jsonpath='{.items[0].metadata.name}')
for i in $(seq 1 90); do
  R=$(kubectl exec -n "$NS" "$CH_POD" -- clickhouse-client -q "SELECT count() FROM system.clusters WHERE cluster='soc-cluster'" 2>/dev/null | tr -d '[:space:]') || true
  [[ -n "$R" && "$R" -ge 1 ]] 2>/dev/null && break
  [[ "$i" -eq 90 ]] && { echo "Cluster not registered"; exit 1; }
  sleep 2
done

# Schema
kubectl exec -i -n "$NS" "$CH_POD" -- clickhouse-client --multiquery < "$SCRIPT_DIR/schema.sql"


echo "ClickHouse ready: $CHI (1x1) in ns/$NS | analyst:changeme-analyst | ingest:changeme-ingest"
