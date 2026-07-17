import json
import os
import threading
from apscheduler.schedulers.background import BackgroundScheduler
from src.clickhouse_client import ClickHouseClient
from src.pixie_client import get_px_connection
from src.stix.pixie.orchestrator import transform_pixie_log_to_stix
from src.config import OUTPUT_DIR
import logging
import traceback

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PixieETL:
    def __init__(self, table_name, processed_table, stix_table, column_names, poll_interval=5):
        self.table_name = table_name
        self.processed_table = processed_table
        self.stix_table = stix_table
        self.column_names = column_names
        self.poll_interval = poll_interval
        self.timestamp = None
        self.namespace = None
        self.podname = None

        self.client = ClickHouseClient().get_client()
        self.scheduler = BackgroundScheduler()
        self.lock = threading.Lock()
        self.last_seen_ns = 0  # nanoseconds since epoch

        self.OUTPUT_FILE = os.path.join(OUTPUT_DIR, f"{self.stix_table}.json")

    def clean_bstring(self, val):
        val = val.decode("utf-8")
        if isinstance(val, str) and val.startswith("b'") and val.endswith("'"):
            return val[2:-1]
        return val

    def set_filters(self, timestamp=None, podname=None, namespace=None):
        self.timestamp = timestamp
        self.podname = podname
        self.namespace = namespace

    def fetch_px_logs(self):
        conn = get_px_connection()

        lower_bounds = []
        if self.last_seen_ns:
            lower_bounds.append(self.last_seen_ns)
        if self.timestamp:
            lower_bounds.append(int(self.timestamp))

        if lower_bounds:
            effective_start_ns = max(lower_bounds)
            start_time_arg = f"start_time={effective_start_ns}"
        else:
            start_time_arg = 'start_time="-20m"'

        filter_lines = ""
        if self.namespace:
            filter_lines += f'df = df[df.namespace == "{self.namespace}"]\n'
        if self.podname:
            filter_lines += f'df = df[df.pod_name == "{self.podname}"]\n'

        pxl_script = f"""
import px

df = px.DataFrame(table="{self.table_name}", {start_time_arg})
df.pod_name = px.pluck_array(px.split(df.ctx["pod_name"],"/"), 1)
df.namespace = df.ctx['namespace']
df.container_id = px.upid_to_container_id(df["upid"])
df.pid = px.upid_to_pid(df.upid)
df.node_name = px.upid_to_node_name(df.upid)

{filter_lines}
px.display(df, "{self.table_name}")
"""

        script = conn.prepare_script(pxl_script)
        logs = []

        for row in script.results(self.table_name):
            log = {}
            for col_name, val in zip(self.column_names, row):
                if isinstance(val, bytes):
                    val = val.decode()
                log[col_name] = val

            logs.append(log)

        logger.info(f"[{self.table_name} ETL] Fetched {len(logs)} rows")
        return logs

    def fetch_and_process(self):
        with self.lock:
            try:
                rows = self.fetch_px_logs()
                if not rows:
                    return

                processed_rows = [[row.get(col, None) for col in self.column_names] for row in rows]
                self.client.insert(self.processed_table, processed_rows, column_names=self.column_names)

                for row in rows:
                    all_stix_object, stix_bundle = transform_pixie_log_to_stix(row, self.stix_table)

                    with open(self.OUTPUT_FILE, "a") as f:
                        f.write(json.dumps(stix_bundle, default=str) + "\n")

                    self.client.insert(
                        self.stix_table,
                        [[
                            row.get("time_", 0),
                            json.dumps(
                                stix_bundle,
                                default=lambda o: o.decode(errors="replace") if isinstance(o, bytes) else str(o)
                            )
                        ]],
                        column_names=["timestamp", "data"]
                    )

                self.last_seen_ns = max(int(row.get('time_', 0)) for row in rows if 'time_' in row)

            except Exception as e:
                logger.error(f"[{self.table_name} ETL] Error: {e}")
                traceback.print_exc()

    def start(self):
        self.scheduler.add_job(self.fetch_and_process, 'interval', seconds=self.poll_interval)
        self.scheduler.start()

    def stop(self):
        self.scheduler.shutdown(wait=False)
