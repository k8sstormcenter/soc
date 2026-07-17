import pytest
from unittest.mock import patch, MagicMock
from src import create_app
from src.etl.pattern_matcher.controller import running_matchers


@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


@patch("src.etl.pattern_matcher.controller.PatternMatcherETL")
def test_pattern_matcher_api(mock_pattern_etl_cls, client):
    # Mock the ETL instance
    mock_etl_instance = MagicMock()
    mock_etl_instance.is_running.return_value = True
    mock_pattern_etl_cls.return_value = mock_etl_instance

    # 1️⃣ Start ETL
    payload = {
        "timestamp": "2025-07-15T15:32:44Z",
        "pod": "webapp-pod-xyz",
        "namespace": "default"
    }

    response = client.post("/pattern-matcher/start", json=payload)
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "started"
    assert "uuid" in data
    assert data["params"]["pod"] == "webapp-pod-xyz"

    matcher_uuid = data["uuid"]

    # Validate ETL setup
    mock_pattern_etl_cls.assert_called_once()
    mock_etl_instance.set_filters.assert_called_once_with(
        "2025-07-15T15:32:44Z", "webapp-pod-xyz", "default"
    )
    mock_etl_instance.start.assert_called_once()

    # 2️⃣ Status check
    status_resp = client.get("/pattern-matcher/status")
    assert status_resp.status_code == 200
    status_data = status_resp.get_json()
    assert "running_matchers" in status_data
    assert matcher_uuid in status_data["running_matchers"]
    assert status_data["running_matchers"][matcher_uuid]["running"] is True

    # 3️⃣ Stop ETL
    stop_resp = client.post("/pattern-matcher/stop", json={"uuid": matcher_uuid})
    assert stop_resp.status_code == 200
    stop_data = stop_resp.get_json()
    assert stop_data["status"] == "stopped"
    assert stop_data["uuid"] == matcher_uuid

    mock_etl_instance.stop.assert_called_once()
    assert matcher_uuid not in running_matchers

