import os
import sys

# Check if running under pytest
IS_PYTEST = "pytest" in sys.modules

# ClickHouse config
CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "localhost")
CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", 8123))
CLICKHOUSE_USER = os.getenv("CLICKHOUSE_USER", "default")
CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "")
CLICKHOUSE_DB = os.getenv("CLICKHOUSE_DB", "default")

# Pixie config
PIXIE_API_TOKEN = os.getenv("PIXIE_API_TOKEN")
PIXIE_CLUSTER_ID = os.getenv("PIXIE_CLUSTER_ID")
USE_PIXIE = os.getenv("USE_PIXIE", "true").lower() == "true"

# Dev mode
DEV_MODE = os.getenv("DEV_MODE", "false").lower() == "true"

# Output directory for writing bundles to file
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "/tmp")
