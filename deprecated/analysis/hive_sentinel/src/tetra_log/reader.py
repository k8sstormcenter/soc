import json
from src.pixie_client import get_px_connection


PXL_SCRIPT = """
import px
df = px.DataFrame(table="tetragon.json")
px.display(df, "tetragon")
"""


def clean_bstring(val):
    val = val.decode("utf-8")
    if isinstance(val, str) and val.startswith("b'") and val.endswith("'"):
        return val[2:-1]
    return val


def fetch_tetragon_logs():
    conn = get_px_connection()

    script = conn.prepare_script(PXL_SCRIPT)
    tetragon_logs = []

    for row in script.results("tetragon"):
        log = {}
        raw_payload = row["payload"]
        parsed_payload = json.loads(raw_payload)
        log[clean_bstring(row["type"])] = parsed_payload
        log["node_name"] = clean_bstring(row["node_name"])
        log["time"] = clean_bstring(row["time"])
        tetragon_logs.append(log)

    return tetragon_logs
