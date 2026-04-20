#!/usr/bin/env bash
set -euo pipefail

# local-ci.sh — deploy ClickHouse + Kubescape + Vector into the existing k3s,
# then validate that all schemas work end-to-end.
# Namespaces: socdemo-ch (clickhouse), socdemo (kubescape + vector)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CH_DIR="$SCRIPT_DIR/tree/clickhouse-lab"
VEC_DIR="$SCRIPT_DIR/tree/vector-lab"
KS_DIR="$SCRIPT_DIR/tree/kubescape"
CH_NS="socdemo-ch"
KS_NS="socdemo"
CHI="forensic-soc-db"
INFER_JSON="$CH_DIR/infer_flat.json"
KUBESCAPE_CHART_VER="${KUBESCAPE_CHART_VER:-1.30.2}"

PASS=0; FAIL=0
check() { if eval "$2" >/dev/null 2>&1; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; return 0; }

echo "=== 1/5 ClickHouse ==="
kubectl create ns "$CH_NS" --dry-run=client -o yaml | kubectl apply -f -

# Operator
helm repo add altinity https://helm.altinity.com 2>/dev/null || true
helm repo update >/dev/null
helm status clickhouse-operator -n "$CH_NS" &>/dev/null || helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator --version 0.26.0 --namespace "$CH_NS" --create-namespace --wait

# Keeper — patch namespace
sed "s/namespace: clickhouse/namespace: $CH_NS/" "$CH_DIR/keeper.yaml" | kubectl apply -f -
echo "  waiting for keeper..."
kubectl wait --for=condition=Ready pod -l "clickhouse-keeper.altinity.com/chk=forensic-keeper" -n "$CH_NS" --timeout=120s 2>/dev/null || sleep 20

# ClickHouse — patch namespace
sed "s/namespace: clickhouse/namespace: $CH_NS/" "$CH_DIR/installation.yaml" | kubectl apply -f -
echo "  waiting for clickhouse pods..."
for i in $(seq 1 60); do
  kubectl get pods -n "$CH_NS" -l "clickhouse.altinity.com/chi=$CHI" --no-headers 2>/dev/null | grep -q Running && break
  sleep 5
done
CH_POD=$(kubectl get pods -n "$CH_NS" -l "clickhouse.altinity.com/chi=$CHI" -o jsonpath='{.items[0].metadata.name}')
for i in $(seq 1 60); do
  R=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT 1" 2>/dev/null) && break
  sleep 2
done

# Schema
kubectl exec -i -n "$CH_NS" "$CH_POD" -- clickhouse-client --multiquery < "$CH_DIR/schema.sql"
echo "  schema applied"

echo "=== 2/5 Schema validation ==="
EXPECTED_TABLES="alerts conn_stats dns_events http_events kubescape_logs network_stats process_stats"
ACTUAL_TABLES=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT name FROM system.tables WHERE database='forensic_db' ORDER BY name" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | xargs)
check "all tables exist" "[ '$ACTUAL_TABLES' = '$EXPECTED_TABLES' ]"

# Validate kubescape_logs columns match infer_flat.json keys
JSON_KEYS=$(python3 -c "import json; d=json.loads(open('$INFER_JSON').readline()); print(' '.join(sorted(d.keys())))")
CH_COLS=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT name FROM system.columns WHERE database='forensic_db' AND table='kubescape_logs' ORDER BY name" 2>/dev/null | tr -d '\r' | tr '\n' ' ' | xargs)
check "kubescape_logs columns match infer_flat.json" "[ '$JSON_KEYS' = '$CH_COLS' ]"

# Validate pixie table types match the Pixie export sink
check "http_events.time_ is DateTime64(9)" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT type FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='time_'\" 2>/dev/null | grep -q 'DateTime64(9)'"
check "http_events.upid is String" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT type FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='upid'\" 2>/dev/null | grep -q 'String'"
check "http_events.encrypted is UInt8" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT type FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='encrypted'\" 2>/dev/null | grep -q 'UInt8'"
check "http_events.remote_port is Int64" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT type FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='remote_port'\" 2>/dev/null | grep -q 'Int64'"
check "http_events has hostname column" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT name FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='hostname'\" 2>/dev/null | grep -q 'hostname'"
check "http_events has event_time DateTime64(3)" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT type FROM system.columns WHERE database='forensic_db' AND table='http_events' AND name='event_time'\" 2>/dev/null | grep -q 'DateTime64(3)'"
check "http_events engine is MergeTree" "kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q \"SELECT engine FROM system.tables WHERE database='forensic_db' AND name='http_events'\" 2>/dev/null | grep -q 'MergeTree'"

echo "=== 3/5 Insert test: kubescape_logs from infer_flat.json ==="
kubectl cp "$INFER_JSON" "$CH_NS/$CH_POD:/var/lib/clickhouse/user_files/infer_flat.json"
kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.kubescape_logs SELECT * FROM file('/var/lib/clickhouse/user_files/infer_flat.json', 'JSONEachRow') SETTINGS schema_inference_make_columns_nullable=0" 2>/dev/null
ROW_COUNT=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT count() FROM forensic_db.kubescape_logs" 2>/dev/null | tr -d '[:space:]')
check "kubescape_logs has rows after insert ($ROW_COUNT)" "[ '$ROW_COUNT' -ge 1 ]"

# Verify fields survived
ALERT=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT JSONExtractString(BaseRuntimeMetadata, 'alertName') FROM forensic_db.kubescape_logs LIMIT 1" 2>/dev/null | tr -d '[:space:]')
check "BaseRuntimeMetadata.alertName extractable ($ALERT)" "[ -n '$ALERT' ]"

PODNAME=$(kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "SELECT JSONExtractString(RuntimeK8sDetails, 'podName') FROM forensic_db.kubescape_logs LIMIT 1" 2>/dev/null | tr -d '[:space:]')
check "RuntimeK8sDetails.podName extractable ($PODNAME)" "[ -n '$PODNAME' ]"

echo "=== 4/5 Insert test: pixie tables ==="
kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.http_events (time_, upid, remote_addr, remote_port, req_method, req_path, resp_status, latency, hostname, event_time) VALUES (now64(9), 'test-upid', '10.0.0.1', 80, 'GET', '/health', 200, 1000000, 'node-01', now64(3))"
check "http_events insert works" "[ $(kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q 'SELECT count() FROM forensic_db.http_events' 2>/dev/null | tr -d '[:space:]') -ge 1 ]"

kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.dns_events (time_, upid, remote_addr, remote_port, req_body, resp_body, latency, hostname, event_time) VALUES (now64(9), 'test-upid', '10.0.0.53', 53, 'example.com', '1.2.3.4', 500000, 'node-01', now64(3))"
check "dns_events insert works" "[ $(kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q 'SELECT count() FROM forensic_db.dns_events' 2>/dev/null | tr -d '[:space:]') -ge 1 ]"

kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.conn_stats (time_, upid, remote_addr, remote_port, bytes_sent, bytes_recv, hostname, event_time) VALUES (now64(9), 'test-upid', '10.0.0.1', 80, 1024, 2048, 'node-01', now64(3))"
check "conn_stats insert works" "[ $(kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q 'SELECT count() FROM forensic_db.conn_stats' 2>/dev/null | tr -d '[:space:]') -ge 1 ]"

kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.process_stats (time_, upid, cpu_utime_ns, rss_bytes, hostname, event_time) VALUES (now64(9), 'test-upid', 100000, 65536, 'node-01', now64(3))"
check "process_stats insert works" "[ $(kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q 'SELECT count() FROM forensic_db.process_stats' 2>/dev/null | tr -d '[:space:]') -ge 1 ]"

kubectl exec -n "$CH_NS" "$CH_POD" -- clickhouse-client -q "INSERT INTO forensic_db.network_stats (time_, pod_id, rx_bytes, tx_bytes, hostname, event_time) VALUES (now64(9), 'test-pod', 4096, 2048, 'node-01', now64(3))"
check "network_stats insert works" "[ $(kubectl exec -n $CH_NS $CH_POD -- clickhouse-client -q 'SELECT count() FROM forensic_db.network_stats' 2>/dev/null | tr -d '[:space:]') -ge 1 ]"

echo "=== 5/5 Kubescape + Vector ==="
kubectl create ns "$KS_NS" --dry-run=client -o yaml | kubectl apply -f -

# Kubescape
helm repo add kubescape https://kubescape.github.io/helm-charts/ 2>/dev/null || true
helm repo update >/dev/null
if ! helm status kubescape -n "$KS_NS" &>/dev/null; then
  helm upgrade --install kubescape kubescape/kubescape-operator --version "$KUBESCAPE_CHART_VER" -n "$KS_NS" --create-namespace --values "$KS_DIR/values.yaml" --set ksNamespace="$KS_NS" --set clusterName=socdemo --set "excludeNamespaces=kube-system\,kube-public\,kube-node-lease\,$CH_NS\,$KS_NS" --wait --timeout 180s 2>/dev/null || echo "  kubescape install may need retry"
fi
kubectl apply -f "$KS_DIR/default-rules.yaml" -n "$KS_NS" 2>/dev/null || true

# Vector — rewrite the ClickHouse endpoint to point at socdemo-ch namespace
PATCHED_VALUES=$(mktemp)
sed "s/clickhouse-forensic-soc-db.clickhouse.svc.cluster.local/clickhouse-forensic-soc-db.$CH_NS.svc.cluster.local/g" "$VEC_DIR/values.yaml" > "$PATCHED_VALUES"
helm repo add vector https://helm.vector.dev 2>/dev/null || true
helm upgrade --install vector vector/vector --namespace "$KS_NS" -f "$PATCHED_VALUES" --wait --timeout 120s 2>/dev/null || echo "  vector install may need retry"
rm -f "$PATCHED_VALUES"

check "kubescape node-agent running" "kubectl get pods -n $KS_NS -l app=node-agent --no-headers 2>/dev/null | grep -q Running"
check "vector running" "kubectl get pods -n $KS_NS -l app.kubernetes.io/name=vector --no-headers 2>/dev/null | grep -q Running"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "Namespaces: $CH_NS (clickhouse), $KS_NS (kubescape+vector)"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
