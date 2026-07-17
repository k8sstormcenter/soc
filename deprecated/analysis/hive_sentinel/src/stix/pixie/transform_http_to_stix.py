from datetime import datetime
import json
from src.stix.core import (
    generate_stix_id,
    generate_unique_log_id,
)

def transform_http_row_to_stix(row):
    timestamp = row.get("time_", "{}")
    if isinstance(timestamp, int):
      if timestamp > 1e12:
          # ns -> s
          timestamp = datetime.fromtimestamp(timestamp / 1_000_000_000).isoformat(timespec="seconds") + "Z"
      else:
          # ms -> s
          timestamp = datetime.fromtimestamp(timestamp / 1000).isoformat(timespec="seconds") + "Z"

    req_headers = json.loads(row.get("req_headers", "{}"))
    resp_headers = json.loads(row.get("resp_headers", "{}"))

    method = row.get("req_method")
    path = row.get("req_path")
    status_code = row.get("resp_status")

    dst_ip = row.get("local_addr")
    dst_port = row.get("local_port")
    url = f"http://{dst_ip}:{dst_port}{path}" if dst_ip and dst_port and path else None

    src_ip = row.get("remote_addr")
    src_port = row.get("remote_port")

    pid = row.get("pid")
    container_id = row.get("container_id")
    pod_name = row.get("pod_name")
    namespace = row.get("namespace")
    node_name = row.get("node_name")

    corr_id = generate_unique_log_id(container_id, pid, pod_name, timestamp, "http_events")

    stix_objects = []

    network_traffic_object = {
        "type": "network-traffic",
        "id": generate_stix_id("network-traffic"),
        "protocols": ["tcp"],
        "extensions": {
            "x-pixie-http-ext": {
                "pid": pid,
                "container_id": container_id,
                "pod_name": pod_name,
                "namespace": namespace,
                "node_name": node_name,
                "method": method,
                "url": url,
                "status_code": status_code,
                "headers": req_headers,
                "src_ip": src_ip,
                "dst_ip": dst_ip,
                "src_port": src_port,
                "dst_port": dst_port,
                "raw_row": row, 
            }
        },
        "start": timestamp,
    }
    stix_objects.append(network_traffic_object)

    observed_data_object = {
        "type": "observed-data",
        "id": generate_stix_id("observed-data"),
        "created_time": timestamp,
        "first_observed": timestamp,
        "last_observed": timestamp,
        "number_observed": 1,
        "object_refs": [network_traffic_object["id"]],
        "extensions": {
            "correlation": corr_id,
            "note": "Pixie HTTP data wrapped in STIX observed-data"
        },
    }
    stix_objects.append(observed_data_object)

    return stix_objects
