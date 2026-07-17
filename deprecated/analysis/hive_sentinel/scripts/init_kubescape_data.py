import json
from clickhouse_connect import get_client
import os
import sys
from dotenv import load_dotenv

load_dotenv()

ROOT_KEYS = [
    "time",
    "RuleID",
    "level",
    "message",
    "msg",
    "event",
    "BaseRuntimeMetadata",
    "CloudMetadata",
    "RuntimeK8sDetails",
    "RuntimeProcessDetails",
]


def get_clickhouse_client():
    return get_client(
        host=os.getenv("CLICKHOUSE_HOST", "localhost"),
        port=int(os.getenv("CLICKHOUSE_PORT", 8123)),
        username=os.getenv("CLICKHOUSE_USER", "default"),
        password=os.getenv("CLICKHOUSE_PASSWORD", ""),
        database=os.getenv("CLICKHOUSE_DB", "default"),
        secure=False,
    )


def create_table_if_not_exists(client):
    drop_stmt = "DROP TABLE IF EXISTS kubescape"
    client.command(drop_stmt)

    create_stmt = """
    CREATE TABLE kubescape (
        time DateTime64(9, 'UTC'),
        RuleID String,
        level String,
        message String,
        msg String,
        event JSON,
        BaseRuntimeMetadata JSON,
        CloudMetadata JSON,
        RuntimeK8sDetails JSON,
        RuntimeProcessDetails JSON
    ) ENGINE = MergeTree()
    ORDER BY time
    """
    client.command(create_stmt)


def insert_json_file(client, file_path, fixed_time=None):
    rows = []

    with open(file_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            try:
                obj = json.loads(line)
                time_value = fixed_time if fixed_time else obj["time"]

                rows.append(
                    (
                        time_value,
                        obj.get("RuleID", ""),
                        obj.get("level", ""),
                        obj.get("message", ""),
                        obj.get("msg", ""),
                        json.dumps(obj.get("event")),
                        json.dumps(obj.get("BaseRuntimeMetadata")),
                        json.dumps(obj.get("CloudMetadata")),
                        json.dumps(obj.get("RuntimeK8sDetails")),
                        json.dumps(obj.get("RuntimeProcessDetails")),
                    )
                )
            except Exception as e:
                print(f"Error parsing line {line_num}: {e}")
    client.insert(
        "kubescape",
        rows,
        column_names=[
            "time",
            "RuleID",
            "level",
            "message",
            "msg",
            "event",
            "BaseRuntimeMetadata",
            "CloudMetadata",
            "RuntimeK8sDetails",
            "RuntimeProcessDetails",
        ],
    )

    print(f"Inserted {len(rows)} rows into 'kubescape' table")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(
            "Usage: python init_kubescape_data.py path/to/kubescape.json [--time=ISO_TIME]"
        )
        sys.exit(1)

    file_path = sys.argv[1]
    fixed_time = None

    for arg in sys.argv[2:]:
        if arg.startswith("--time="):
            fixed_time = arg.split("=", 1)[1]

    client = get_clickhouse_client()
    create_table_if_not_exists(client)
    insert_json_file(client, file_path, fixed_time=fixed_time)
