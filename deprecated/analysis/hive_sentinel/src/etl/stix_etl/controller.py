# File: analysis/hive_sentinel/src/etl/stix_etl_launcher.py

import json
from src.etl.stix_etl.etl import StixETL
from src.stix.kubescape.orchestrator import transform_kubescape_logs_to_stix
from src.stix.tetra.orchestrator import transform_tetragon_to_stix

# Process Tetragon logs to STIX row

def process_tetragon_row(row):
    log = {
        "timestamp": row[0],
        "node_name": row[1],
        f"{row[2]}": json.loads(row[3]),
    }
    stix_objects, bundles = transform_tetragon_to_stix([log])
    log_key = row[2]
    pod_name = log.get(log_key, {}).get("process", {}).get("pod", {}).get("name", "unknown")
    namespace = log.get(log_key, {}).get("process", {}).get("pod", {}).get("namespace", "unknown")
    data = json.dumps(stix_objects)
    return [log["timestamp"], pod_name, namespace, data]

# Process Kubescape logs to STIX row

def process_kubescape_row(row):
    log = {
        "BaseRuntimeMetadata": json.loads(row[0]),
        "CloudMetadata": json.loads(row[1]) if row[1] != "empty" else {},
        "RuleID": row[2],
        "RuntimeK8sDetails": json.loads(row[3]),
        "RuntimeProcessDetails": json.loads(row[4]),
        "event": json.loads(row[5]),
        "level": row[6],
        "message": row[7],
        "msg": row[8],
        "timestamp": row[9],
    }
    stix_objects, bundles = transform_kubescape_logs_to_stix([log])
    pod_name = log["RuntimeK8sDetails"].get("podName", "unknown")
    namespace = log["RuntimeK8sDetails"].get("podNamespace", "unknown")
    data = json.dumps(stix_objects)
    return [log["timestamp"], pod_name, namespace, data]

# STIX table columns
stix_columns = ["timestamp", "pod_name", "namespace", "data"]

# Tetragon ETL

tetragon_stix_etl = StixETL(
    table="tetragon_logs",
    processed_table="tetragon_stix",
    column_names=stix_columns,
    time_column_index=0,
    process_func=process_tetragon_row,
    poll_interval=10
)

# Kubescape ETL

kubescape_stix_etl = StixETL(
    table="kubescape_logs",
    processed_table="kubescape_stix",
    column_names=stix_columns,
    time_column_index=9,
    process_func=process_kubescape_row,
    poll_interval=10
)

def start_stix_etls():
    print("[INFO] Starting Tetragon STIX ETL")
    tetragon_stix_etl.start()
    print("[INFO] Starting Kubescape STIX ETL")
    kubescape_stix_etl.start()
