import uuid
from datetime import datetime, timezone
import re
import base64
import hashlib


def generate_stix_id(type):
    return f"{type}--{uuid.uuid4()}"


def _get_current_time_iso_format():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds") + "Z"


def create_relationship(source_ref, target_ref, relationship_type):
    return {
        "type": "relationship",
        "spec_version": "2.1",
        "id": generate_stix_id("relationship"),
        "created": _get_current_time_iso_format(),
        "modified": _get_current_time_iso_format(),
        "relationship_type": relationship_type,
        "source_ref": source_ref,
        "target_ref": target_ref,
    }


def sanitize_bundle(bundle):
    if not isinstance(bundle, dict):
        return bundle
    return {k: sanitize_bundle(v) for k, v in bundle.items() if v is not None}


def compare_stix_objects(obj, objects_array):
    for other_obj in objects_array:
        if obj["type"] == other_obj["type"]:
            if all(
                obj.get(key) == other_obj.get(key)
                for key in obj
                if key not in ["id", "created", "modified", "spec_version"]
            ) and all(
                other_obj.get(key) == obj.get(key)
                for key in other_obj
                if key not in ["id", "created", "modified", "spec_version"]
            ):
                return True
    return False


def create_process_stix_id(corr_id):
    if corr_id:
        try:
            truncated_id = corr_id[:36]
            return f"process--{truncated_id}"
        except Exception as e:
            print(f"Error generating process ID: {e}")


def unique_process_stix_id(exec_id):
    if exec_id:
        try:
            decoded_exec_id = base64.b64decode(exec_id).decode("utf-8")
            truncated_exec_id = decoded_exec_id[-36:]
            return f"process--{truncated_exec_id}"
        except Exception as e:
            print(f"Error decoding or hashing exec_id: {e}")

def short_md5(text, length=12):
    return hashlib.md5(text.encode()).hexdigest()[:length]

def generate_unique_log_id(container_id, pid, hostname, time, src):
    pid = str(pid).zfill(8)
    # handle hostname
    if hostname != "UnknownHost":
        host = short_md5(hostname)
    else:
        host = str(hostname[:12]).zfill(12)
    timestamp = re.sub(r"[-\:\.]", "", time[2:22])
    if src == "tetra":
        match = re.match(r"containerd://([0-9a-f]+)", container_id)
        con_id = match.group(1)[:12] if match else "unknown"
    elif src in "kubescape":
        con_id = container_id[:12]
    else:
        con_id = container_id[:12]
    return f"{timestamp}{con_id}{pid}{host}"
