import threading
from apscheduler.schedulers.background import BackgroundScheduler
from src.clickhouse_client import ClickHouseClient
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class StixETL:
    def __init__(self, table, processed_table, column_names, time_column_index, process_func, poll_interval=5):
        self.client = ClickHouseClient().get_client()
        self.table = table
        self.processed_table = processed_table
        self.column_names = column_names
        self.time_column_index = time_column_index
        self.process_func = process_func
        self.poll_interval = poll_interval

        # Track last seen ISO timestamp string
        # Initialize to earliest possible time to capture all data on first run
        self.last_seen_ts = '1970-01-01T00:00:00Z'

        self.lock = threading.Lock()
        self.scheduler = BackgroundScheduler()

    def fetch_and_process(self):
        with self.lock:
            logger.info(f"🚀 Running ETL fetch for table {self.table}")
            query = f"""
                SELECT * FROM {self.table}
                WHERE time > %(last_ts)s
                ORDER BY time ASC
                LIMIT 10
            """
            try:
                result = self.client.query(query, parameters={"last_ts": self.last_seen_ts})
                rows = result.result_rows
                logger.info(f"🔍 Fetched {len(rows)} rows after {self.last_seen_ts}")

                if not rows:
                    return

                processed_rows = [self.process_func(row) for row in rows]

                if processed_rows:
                    self.client.insert(
                        self.processed_table,
                        processed_rows,
                        column_names=self.column_names
                    )
                    logger.info(f"✅ Inserted {len(processed_rows)} rows into {self.processed_table}")

                    # Update last_seen_ts to the timestamp of the last row fetched
                    self.last_seen_ts = rows[-1][self.time_column_index]
                    logger.info(f"⏱️ Updated last_seen_ts to {self.last_seen_ts}")

            except Exception as e:
                logger.error(f"❌ Error during fetch_and_process: {e}", exc_info=True)

    def start(self):
        self.scheduler.add_job(self.fetch_and_process, 'interval', seconds=self.poll_interval)
        self.scheduler.start()

    def stop(self):
        self.scheduler.shutdown(wait=False)
