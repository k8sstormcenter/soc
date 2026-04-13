#!/usr/bin/env bash
set -euo pipefail

# ClickHouse + Vector forensic database installer for iximiuz labs
# Usage: ./install.sh [--skip-operator] [--skip-vector]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VECTOR_DIR="$(cd "$SCRIPT_DIR/../vector-lab" 2>/dev/null && pwd)" || VECTOR_DIR=""
NAMESPACE="clickhouse"
CHI_NAME="forensic-soc-db"
KEEPER_NAME="forensic-keeper"

SKIP_OPERATOR=false
SKIP_VECTOR=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-operator) SKIP_OPERATOR=true; shift ;;
    --skip-vector)   SKIP_VECTOR=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ---------- Helm prerequisite ----------
if ! command -v helm &>/dev/null; then
  log "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ---------- 1. Altinity ClickHouse Operator ----------
if ! $SKIP_OPERATOR; then
  log "Installing Altinity ClickHouse Operator..."
  helm repo add altinity https://helm.altinity.com 2>/dev/null || true
  helm repo update
  if helm status clickhouse-operator -n "$NAMESPACE" &>/dev/null; then
    log "Operator already installed, skipping."
  else
    helm install clickhouse-operator altinity/altinity-clickhouse-operator \
      --version 0.26.0 \
      --namespace "$NAMESPACE" \
      --create-namespace \
      --wait --timeout 120s
  fi
  log "Operator ready."
fi

# ---------- 2. ClickHouse Keeper ----------
log "Deploying ClickHouse Keeper..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$SCRIPT_DIR/keeper.yaml"

log "Waiting for Keeper pod..."
for i in $(seq 1 40); do
  READY=$(kubectl get pods -n "$NAMESPACE" -l "clickhouse-keeper.altinity.com/chk=$KEEPER_NAME" \
    --no-headers 2>/dev/null | grep -c Running || true)
  if [[ "$READY" -ge 1 ]]; then
    log "Keeper is running."
    break
  fi
  if [[ "$i" -eq 40 ]]; then
    log "ERROR: Keeper did not start within 120s."
    kubectl get pods -n "$NAMESPACE"
    exit 1
  fi
  sleep 3
done

# ---------- 3. ClickHouse Installation ----------
log "Deploying ClickHouse cluster (2 shards × 1 replica)..."
kubectl apply -f "$SCRIPT_DIR/installation.yaml"

log "Waiting for ClickHouse pods (up to 5 min)..."
for i in $(seq 1 60); do
  TOTAL=$(kubectl get pods -n "$NAMESPACE" \
    -l "clickhouse.altinity.com/chi=$CHI_NAME" \
    --no-headers 2>/dev/null | wc -l)
  READY=$(kubectl get pods -n "$NAMESPACE" \
    -l "clickhouse.altinity.com/chi=$CHI_NAME" \
    --no-headers 2>/dev/null | grep -c Running || true)

  # Early crash detection
  CRASH=$(kubectl get pods -n "$NAMESPACE" \
    -l "clickhouse.altinity.com/chi=$CHI_NAME" \
    --no-headers 2>/dev/null | grep -c CrashLoopBackOff || true)
  if [[ "$CRASH" -gt 0 && "$i" -gt 6 ]]; then
    log "ERROR: ClickHouse pods are crash-looping."
    kubectl logs -n "$NAMESPACE" \
      -l "clickhouse.altinity.com/chi=$CHI_NAME" \
      --tail=5 2>&1 | grep -i "error\|exception" || true
    exit 1
  fi

  if [[ "$TOTAL" -ge 2 && "$READY" -ge 2 ]]; then
    log "All $READY ClickHouse pods are running."
    break
  fi
  if [[ "$i" -eq 60 ]]; then
    log "ERROR: ClickHouse pods did not start within 5 min."
    kubectl get pods -n "$NAMESPACE"
    exit 1
  fi
  sleep 5
done

# Wait for CH to accept connections
log "Waiting for ClickHouse to accept connections..."
sleep 10

# ---------- 4. Apply schema ----------
log "Applying forensic database schema..."

CH_POD=$(kubectl get pods -n "$NAMESPACE" \
  -l "clickhouse.altinity.com/chi=$CHI_NAME" \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -i -n "$NAMESPACE" "$CH_POD" -- \
  clickhouse-client --multiquery < "$SCRIPT_DIR/schema.sql"

log "Schema applied."

# ---------- 5. Smoke test ----------
log "Running smoke test..."

# Insert via ingest_writer
kubectl exec -n "$NAMESPACE" "$CH_POD" -- \
  clickhouse-client --user ingest_writer --password changeme-ingest \
  -q "INSERT INTO forensic_db.alerts (timestamp, rule_id, alert_name, severity, namespace, pod_name, message) VALUES (now(), 'TEST', 'Smoke Test', 1, 'test-ns', 'test-pod', 'install verification')"

# Read via forensic_analyst
RESULT=$(kubectl exec -n "$NAMESPACE" "$CH_POD" -- \
  clickhouse-client --user forensic_analyst --password changeme-analyst \
  -q "SELECT count() FROM forensic_db.alerts WHERE rule_id = 'TEST'")

if [[ "$RESULT" -ge 1 ]]; then
  log "Smoke test PASSED (inserted and queried test event)."
else
  log "Smoke test FAILED (expected >=1 row, got $RESULT)."
  exit 1
fi

# Verify analyst cannot write
if kubectl exec -n "$NAMESPACE" "$CH_POD" -- \
  clickhouse-client --user forensic_analyst --password changeme-analyst \
  -q "INSERT INTO forensic_db.alerts (timestamp, rule_id) VALUES (now(), 'SHOULD_FAIL')" 2>/dev/null; then
  log "WARNING: Analyst user was able to INSERT — append-only enforcement broken!"
else
  log "Append-only enforcement verified (analyst INSERT correctly denied)."
fi

# Clean up test row
kubectl exec -n "$NAMESPACE" "$CH_POD" -- \
  clickhouse-client -q "ALTER TABLE forensic_db.alerts_local ON CLUSTER 'soc-cluster' DELETE WHERE rule_id = 'TEST'" 2>/dev/null || true

# ---------- 6. Vector (optional) ----------
if ! $SKIP_VECTOR; then
  if [[ -z "$VECTOR_DIR" || ! -f "$VECTOR_DIR/values.yaml" ]]; then
    log "WARNING: vector-lab/values.yaml not found at $VECTOR_DIR. Skipping Vector."
  else
    log "Installing Vector for log ingestion..."
    helm repo add vector https://helm.vector.dev 2>/dev/null || true
    helm repo update

    if helm status vector -n honey &>/dev/null; then
      log "Vector already installed, upgrading..."
      helm upgrade vector vector/vector \
        --namespace honey \
        -f "$VECTOR_DIR/values.yaml" \
        --wait --timeout 120s 2>&1 || log "WARNING: Vector upgrade failed."
    else
      helm install vector vector/vector \
        --namespace honey \
        -f "$VECTOR_DIR/values.yaml" \
        --wait --timeout 120s 2>&1 || log "WARNING: Vector install failed."
    fi
  fi
fi

# ---------- Summary ----------
echo ""
echo "========================================"
echo "ClickHouse forensic database is ready!"
echo ""
echo "Cluster:    $CHI_NAME (2 shards × 1 replica)"
echo "Namespace:  $NAMESPACE"
echo "HTTP API:   port 8123"
echo "Native:     port 9000"
echo ""
echo "Users:"
echo "  forensic_analyst / changeme-analyst  (SELECT only)"
echo "  ingest_writer    / changeme-ingest   (INSERT only)"
echo ""
echo "Port-forward:"
echo "  kubectl port-forward -n $NAMESPACE svc/clickhouse-$CHI_NAME 8123:8123"
echo ""
echo "Connect:"
echo "  clickhouse-client -h 127.0.0.1 --user forensic_analyst --password changeme-analyst"
echo "========================================"
