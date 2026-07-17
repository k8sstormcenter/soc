from src.pixie_client import get_px_connection
import json
from datetime import datetime, timezone

PXL_SCRIPT = """
import px
df = px.DataFrame(table="kubescape.json")
df = df[
    px.contains(
        df.message, 
        "Unexpected process launched"
    )]

    
px.display(df, "kubescape")
"""


def iso_to_nanoseconds(iso_ts: str) -> int:
    """
    Convert ISO 8601 timestamp with nanoseconds to nanoseconds since Unix epoch.

    Example: "2025-05-15T10:19:35.195123920Z" -> 1747304375195123920
    """
    # Remove the trailing 'Z' for UTC
    if iso_ts.endswith("Z"):
        iso_ts_no_z = iso_ts[:-1]
    else:
        iso_ts_no_z = iso_ts

    try:
        # Try parsing with microseconds
        dt = datetime.strptime(iso_ts_no_z, "%Y-%m-%dT%H:%M:%S.%f").replace(tzinfo=timezone.utc)
        # Extract nanoseconds beyond microsecond precision if present
        extra_nanos_str = iso_ts_no_z[26:] if len(iso_ts_no_z) > 26 else "0"
        extra_nanos = int(extra_nanos_str.ljust(3, '0')[:3]) # Ensure 3 digits for nano, pad with 0 if needed
    except ValueError:
        # If parsing with microseconds fails, try without
        dt = datetime.strptime(iso_ts_no_z, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
        extra_nanos = 0

    # Convert to nanoseconds
    base_nanos = int(dt.timestamp() * 1_000_000_000)
    return base_nanos + extra_nanos


def clean_bstring(val):
    val = val.decode("utf-8")
    if isinstance(val, str) and val.startswith("b'") and val.endswith("'"):
        return val[2:-1]
    return val


def try_json_parse(val):
    if isinstance(val, bytes):
        val = val.decode("utf-8")

    if val == "null":
        return None

    if not isinstance(val, str):
        return val

    try:
        return json.loads(val)
    except (json.JSONDecodeError, TypeError):
        return val


ROOT_KEYS = [
    "BaseRuntimeMetadata",
    "CloudMetadata",
    "RuleID",
    "RuntimeK8sDetails",
    "RuntimeProcessDetails",
    "event",
    "level",
    "message",
    "msg",
    "time",
]


def fetch_kubescape_logs():
    conn = get_px_connection()
    script = conn.prepare_script(PXL_SCRIPT)
    results = script.results("kubescape")

    kubescape_logs = []

    for row in results:
        log = {}

        for key in ROOT_KEYS:
            val = row[key]
            parsed = try_json_parse(val)
            log[key] = parsed

        log["time_ns"] = iso_to_nanoseconds(log["time"])
        kubescape_logs.append(log)

    return kubescape_logs
