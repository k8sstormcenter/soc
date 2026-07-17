from src.stix.core import (
    generate_stix_id,
    _get_current_time_iso_format,
    create_process_stix_id,
    generate_unique_log_id,
)


def kprobe(k, element):
    try:
        return (
            k.get(element, {}).get("string_arg", "")
            or k.get(element, {}).get("int_arg", "")
            or k.get(element, {}).get("sock_arg", "")
            or k.get(element, {}).get("file_arg", "")
        )
    except:
        return ""


def transform_kprobe_to_stix(log, node_name, k):
    parent = log.get("parent", {})
    process = log.get("process", {})
    container_id = process.get("pod", {}).get("container", {}).get("id", "")
    pid = process.get("pid", -1)
    timestamp = process.get("start_time")
    corr_id = generate_unique_log_id(container_id, pid, node_name, timestamp, "tetra")

    process_object = {
        "type": "process",
        "id": create_process_stix_id(corr_id),
        "pid": pid,
        "command_line": f"{process.get('binary')} {process.get('arguments')}",
        "cwd": process.get("cwd"),
        "created_time": timestamp,
        "extensions": {
            "x-tetra-ext": {
                "extension_type": "property-extension",
                "flags": process.get("flags", ""),
                "image_id": process.get("pod", {})
                .get("container", {})
                .get("image", {})
                .get("id", ""),
                "container_id": container_id,
                "pod_name": process.get("pod", {}).get("name", ""),
                "namespace": process.get("pod", {}).get("namespace", ""),
                "function_name": log.get("function_name", ""),
                "parent_pid": parent.get("exec_id"),
                "parent_command_line": f"{parent.get('binary')} {parent.get('arguments')}",
                "parent_cwd": parent.get("cwd"),
                "grand_parent_pid": parent.get("parent_exec_id"),
                "kprobe0": kprobe(k, "kprobe0"),
                "kprobe1": kprobe(k, "kprobe1"),
                "kprobe2": kprobe(k, "kprobe2"),
                "kprobe3": kprobe(k, "kprobe3"),
                "kprobe4": kprobe(k, "kprobe4"),
            },
        },
    }

    current_time = log.get("time", _get_current_time_iso_format())
    observed_data_object = {
        "type": "observed-data",
        "id": generate_stix_id("observed-data"),
        "created": current_time,
        "first_observed": current_time,
        "last_observed": current_time,
        "number_observed": 1,
        "object_refs": [process_object["id"]],
        "extensions": {
            "x-tetra-ext": {
                "extension_type": "toplevel-property-extension",
                "alert_name": log.get("action"),
                "correlation": corr_id,
                "rule_id": log.get("policy_name"),
                "node_info": {"node_name": node_name},
                "children": "",
            },
        },
    }

    return [process_object, observed_data_object]
