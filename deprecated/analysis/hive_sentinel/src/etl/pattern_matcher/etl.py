# File: analysis/hive_sentinel/src/etl/kubescape_matcher_etl.py

import os
import json
import threading
import traceback
import logging
from apscheduler.schedulers.background import BackgroundScheduler
from src.stix.core import generate_stix_id
from src.clickhouse_client import ClickHouseClient
from src.config import OUTPUT_DIR
from src.stix.matcher import get_attack_patterns, get_pattern, matches

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PatternMatcherETL:
    def __init__(self, poll_interval=5):
        self.timestamp = None
        self.podname = None
        self.namespace = None
        self.poll_interval = poll_interval
        self.OUTPUT_FILE = os.path.join(OUTPUT_DIR, "matched_patterns.json")

        self.client = ClickHouseClient().get_client()
        self.scheduler = BackgroundScheduler()
        self.lock = threading.Lock()
        self.last_seen_ts = "1970-01-01T00:00:00Z"
        self.time_column_index = 0

        self.attack_patterns = get_attack_patterns()

    def set_filters(self, timestamp=None, podname=None, namespace=None):
        self.timestamp = timestamp
        self.podname = podname
        self.namespace = namespace

    def fetch_logs(self):
        query = """
        SELECT timestamp, data
        FROM kubescape_stix
        WHERE timestamp > %(start_ts)s
          AND pod_name = %(pod)s
          AND namespace = %(ns)s
        ORDER BY timestamp ASC
        LIMIT 100
        """

        params = {
            "start_ts": self.last_seen_ts,
            "pod": self.podname,
            "ns": self.namespace
        }

        result = self.client.query(query, parameters=params)
        return result.result_rows

    def fetch_and_process(self):
        with self.lock:
            try:
                rows = self.fetch_logs()
                if not rows:
                    return

                for timestamp, data in rows:
                    objects = json.loads(data)
                    stix_bundle = {
                        "type": "bundle",
                        "id": generate_stix_id("bundle"),
                        "spec_version": "2.1",
                        "objects": objects,
                    }

                    matching_patterns = []
                    for attack_bundle in self.attack_patterns:
                        pattern, indicator_id = get_pattern(attack_bundle)
                        pattern_id = attack_bundle["id"]

                        if matches(pattern, stix_bundle):
                            matching_patterns.append((indicator_id, pattern_id, attack_bundle))

                    if matching_patterns:
                        matches_result = [
                            {"indicator_id": i, "pattern_id": p, "attack": a["objects"]}
                            for i, p, a in matching_patterns
                        ]

                        stix_bundle["extensions"] = {
                            "x-matching-patterns": matches_result
                        }

                        with open(self.OUTPUT_FILE, "a") as f:
                            f.write(json.dumps(stix_bundle) + "\n")

                        self.client.insert(
                            table="matched_attack_patterns",
                            data=[(timestamp, json.dumps(stix_bundle), json.dumps(matches_result))],
                            column_names=["timestamp", "bundle", "matches"]
                        )

                        logger.info("[PatternMatcherETL] Match found and written")

                self.last_seen_ts = rows[-1][self.time_column_index]
                logger.info(f"[PatternMatcherETL] Updated last_seen_ts to {self.last_seen_ts}")

            except Exception as e:
                logger.error(f"[PatternMatcherETL] Error: {e}")
                traceback.print_exc()

    def start(self):
        self.scheduler.add_job(self.fetch_and_process, 'interval', seconds=self.poll_interval)
        self.scheduler.start()

    def stop(self):
        self.scheduler.shutdown(wait=False)
