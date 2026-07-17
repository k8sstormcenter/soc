from clickhouse_connect import get_client
import os
import logging
import sys
IS_PYTEST = "pytest" in sys.modules

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ClickHouseClient:
    def __init__(self):
        logger.info("🔌 Connecting to ClickHouse...")
        
        self.client =  get_client(
            host=os.getenv("CLICKHOUSE_HOST", "localhost"),
            port=int(os.getenv("CLICKHOUSE_PORT", 8123)),
            username=os.getenv("CLICKHOUSE_USER", "default"),
            password=os.getenv("CLICKHOUSE_PASSWORD", ""),
            database=os.getenv("CLICKHOUSE_DB", "default"),
            secure=False,
        ) if not IS_PYTEST else None
        logger.info("✅ ClickHouse client initialized.")

    def get_client(self):
        return self.client
