from src.stix.core import (
    generate_unique_log_id,
    create_process_stix_id,
    generate_stix_id,
)
from src.stix.core import _get_current_time_iso_format


def transform_kubescape_object_to_stix(log):

    base_metadata = log.get("BaseRuntimeMetadata", {})
    runtime_k8s = log.get("RuntimeK8sDetails", {})
    runtime_process = log.get("RuntimeProcessDetails", {})
    cloud_metadata = log.get("CloudMetadata", {}) or {}
    event = log.get("event", {}) or {}

    container_id = runtime_k8s.get("containerID", "")
    pid = runtime_process.get("processTree", {}).get("ppid", -1)
    # hostname = cloud_metadata.get("instance_id", {}) or ""  # Original implementation from lightening rod
    # hostname = event.get("k8s", {}).get("node", "UnknownHost") # matches with tetragon which uses node_name according to lightening rod
    pod_name = runtime_k8s.get("podName", "UnknownHost") # this way we can match with http logs' pod names
    timestamp = log.get("time", log.get("timestamp", "UnknownTime"))
    corr_id = generate_unique_log_id(
        container_id, pid, pod_name, timestamp, "kubescape"
    )

    stix_objects = []

    process_object = {
        "type": "process",
        "id": create_process_stix_id(corr_id),
        "pid": pid,
        "command_line": runtime_process.get("processTree", {}).get("cmdline", ""),
        "cwd": runtime_process.get("processTree", {}).get("cwd", ""),
        "created_time": timestamp,
        "extensions": {
            "container_id": container_id,
            "flags": log.get("message", ""),
            "image_id": runtime_k8s.get("image", ""),
            "pod_name": pod_name,
            "namespace": runtime_k8s.get("namespace", ""),
            "function_name": log.get("RuleID", ""),
            "parent_pid": runtime_process.get("processTree", {}).get("ppid", -1),
            "parent_command_line": runtime_process.get("processTree", {}).get(
                "pcomm", ""
            ),
            "kprobe0.capability": base_metadata.get("arguments", {}).get(
                "capability", ""
            ),
            "kprobe1.syscall": base_metadata.get("arguments", {}).get("syscall", ""),
            "kprobe2.trace": base_metadata.get("trace", {}),
            "kprobe3.severity": base_metadata.get("severity", {}),
            "kprobe4.infectedPID": base_metadata.get("infectedPID", {}),
        },
    }
    stix_objects.append(process_object)

    observed_data_object = {
        "type": "observed-data",
        "id": generate_stix_id("observed-data"),
        "created_time": timestamp,
        "first_observed": timestamp,
        "last_observed": timestamp,
        "number_observed": 1,
        "object_refs": [process_object["id"]],
        "extensions": {
            "alert_name": base_metadata.get("alertName", ""),
            "correlation": corr_id,
            "rule_id": log.get("RuleID", ""),
            "node_info": event.get("k8s", {}).get("node", ""),
            "children": runtime_process.get("processTree", {}).get("children", []),
        },
    }
    stix_objects.append(observed_data_object)

    return stix_objects
