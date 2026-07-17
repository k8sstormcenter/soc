from datetime import datetime
from src.clickhouse_client import ClickHouseClient
import json


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


def safe_json_parse(val):
    if isinstance(val, str):
        try:
            return json.loads(val)
        except Exception:
            return val
    return val


def fetch_kubescape_logs():
    client = ClickHouseClient().get_client()

    query = f"""
    SELECT
        {', '.join(ROOT_KEYS)},
        toUnixTimestamp64Nano(time) AS time_ns
    FROM kubescape_logs
    WHERE message LIKE '%Unexpected process launched%'
    """

    result = client.query(query)
    logs = []

    for row in result.result_rows:
        log = {}

        for idx, key in enumerate(ROOT_KEYS):
            value = row[idx]
            if key == "time" and isinstance(value, datetime):
                log[key] = value.isoformat(timespec="microseconds") + "Z"
            else:
                log[key] = safe_json_parse(value)

        log["time_ns"] = row[-1]
        logs.append(log)

    return logs
