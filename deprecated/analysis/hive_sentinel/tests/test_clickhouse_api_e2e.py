# tests/test_clickhouse_api_e2e.py
import pytest
from flask import Flask
from src.clickhouse_api.controller import data_bp

@pytest.fixture
def test_app():
    app = Flask(__name__)
    app.register_blueprint(data_bp)
    app.config['TESTING'] = True
    return app.test_client()

def generate_test(endpoint, method_name, query_string, expected_filters, expected_limit):
    def test_func(test_app, monkeypatch):
        mock_response = [{"mock": "data"}]

        def mock_method(self, filters, limit):
            for key, value in expected_filters.items():
                assert filters.get(key) == value
            assert int(limit) == expected_limit
            return mock_response

        monkeypatch.setattr(f"src.clickhouse_api.service.DataService.{method_name}", mock_method)

        response = test_app.get(f"/{endpoint}{query_string}")
        assert response.status_code == 200
        assert response.get_json() == mock_response

    return test_func

test_http_events_endpoint = generate_test(
    endpoint="http_events",
    method_name="fetch_http_events",
    query_string="?pod_name=mypod&limit=10",
    expected_filters={"pod_name": "mypod"},
    expected_limit=10
)

test_dns_events_endpoint = generate_test(
    endpoint="dns_events",
    method_name="fetch_dns_events",
    query_string="?namespace=default&limit=20",
    expected_filters={"namespace": "default"},
    expected_limit=20
)

test_tetragon_logs_endpoint = generate_test(
    endpoint="tetragon_logs",
    method_name="fetch_tetragon_logs",
    query_string="?type=exec&limit=15",
    expected_filters={"type": "exec"},
    expected_limit=15
)

test_http_stix_endpoint = generate_test(
    endpoint="http_stix",
    method_name="fetch_http_stix",
    query_string="?limit=5",
    expected_filters={},
    expected_limit=5
)

test_dns_stix_endpoint = generate_test(
    endpoint="dns_stix",
    method_name="fetch_dns_stix",
    query_string="?limit=8",
    expected_filters={},
    expected_limit=8
)

test_tetragon_stix_endpoint = generate_test(
    endpoint="tetragon_stix",
    method_name="fetch_tetragon_stix",
    query_string="?limit=12",
    expected_filters={},
    expected_limit=12
)

test_kubescape_logs_endpoint = generate_test(
    endpoint="kubescape_logs",
    method_name="fetch_kubescape_logs",
    query_string="?level=info&limit=25",
    expected_filters={"level": "info"},
    expected_limit=25
)

test_kubescape_stix_endpoint = generate_test(
    endpoint="kubescape_stix",
    method_name="fetch_kubescape_stix",
    query_string="?limit=30",
    expected_filters={},
    expected_limit=30
)
