import os

USE_PIXIE = os.getenv("USE_PIXIE", "true").lower() == "true"
if USE_PIXIE:
    from src.kubescape_log.data.pixie_reader import fetch_kubescape_logs
else:
    from src.kubescape_log.data.clickhouse_reader import fetch_kubescape_logs
