import pytest
from unittest.mock import patch, MagicMock
from src import create_app
from src.etl.pixie_etl.controller import running_etls

@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

@patch("src.etl.pixie_etl.controller.PixieETL")
def test_start_stop_status_endpoints(mock_pixie_etl_cls, client):
    # Mock PixieETL to avoid real ETL logic
    mock_etl_instance = MagicMock()
    mock_pixie_etl_cls.return_value = mock_etl_instance

    # 1️⃣ Test start endpoint
    payload = {
        "tablename": "http_events",
        "timestamp": 1719923456000000000,
        "podname": "my-pod",
        "namespace": "default",
        "poll_interval": 2
    }
    response = client.post("/pixie-etl/start", json=payload)
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "started"
    assert data["tablename"] == "http_events"
    assert "uuid" in data

    etl_uuid = data["uuid"]

    # Check that PixieETL was instantiated correctly
    mock_pixie_etl_cls.assert_called_once()
    mock_etl_instance.set_filters.assert_called_once()
    mock_etl_instance.start.assert_called_once()

    # 2️⃣ Test status endpoint
    status_response = client.get("/pixie-etl/status")
    assert status_response.status_code == 200
    status_data = status_response.get_json()
    assert "running_etls" in status_data
    assert etl_uuid in status_data["running_etls"]

    # 3️⃣ Test stop endpoint
    stop_payload = {"uuid": etl_uuid}
    stop_response = client.post("/pixie-etl/stop", json=stop_payload)
    assert stop_response.status_code == 200
    stop_data = stop_response.get_json()
    assert stop_data["status"] == "stopped"
    assert stop_data["uuid"] == etl_uuid

    # Confirm ETL's stop method was called
    mock_etl_instance.stop.assert_called_once()

    # Confirm ETL removed from running_etls
    assert etl_uuid not in running_etls
