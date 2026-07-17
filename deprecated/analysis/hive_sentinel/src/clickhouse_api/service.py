# src/services/data_service.py
from src.clickhouse_api.repository import ClickHouseRepository

ALLOWED_FILTER_KEYS = {
    'default.http_events': ['pod_name', 'node_name', 'namespace', 'container_id', 'remote_addr'],
    'default.dns_events': ['pod_name', 'node_name', 'namespace', 'container_id', 'remote_addr'],
    'default.tetragon_logs': ['node_name', 'type'],
    'default.http_stix': [],
    'default.dns_stix': [],
    'default.tetragon_stix': [],
    'default.kubescape_logs': ['event', 'level', 'msg'],
    'default.kubescape_stix': []
}

def sanitize_filters(table_name, filters):
    allowed_keys = ALLOWED_FILTER_KEYS.get(table_name, [])
    sanitized = {k: v for k, v in filters.items() if k in allowed_keys}
    return sanitized

class DataService:
    def __init__(self):
        pass

    def fetch_http_events(self, filters: dict, limit: int = 100):
        table_name = 'default.http_events'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='time_')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_dns_events(self, filters: dict, limit: int = 100):
        table_name = 'default.dns_events'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='time_')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_tetragon_logs(self, filters: dict, limit: int = 100):
        table_name = 'default.tetragon_logs'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='time')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_http_stix(self, filters: dict, limit: int = 100):
        table_name = 'default.http_stix'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='timestamp')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_dns_stix(self, filters: dict, limit: int = 100):
        table_name = 'default.dns_stix'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='timestamp')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_tetragon_stix(self, filters: dict, limit: int = 100):
        table_name = 'default.tetragon_stix'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='timestamp')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_kubescape_logs(self, filters: dict, limit: int = 100):
        table_name = 'default.kubescape_logs'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='time')
        return repo.query_table(filters=sanitized_filters, limit=limit)

    def fetch_kubescape_stix(self, filters: dict, limit: int = 100):
        table_name = 'default.kubescape_stix'
        sanitized_filters = sanitize_filters(table_name, filters)
        repo = ClickHouseRepository(table_name, order_by_column='timestamp')
        return repo.query_table(filters=sanitized_filters, limit=limit)
