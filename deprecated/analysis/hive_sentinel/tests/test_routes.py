import pytest
from unittest.mock import patch
from src import create_app
from stix2validator import validate_instance, print_results
from tests.mocks.tetra_mock import mock_log

@pytest.fixture
def client():
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


@patch("src.tetra_log.controller.fetch_tetragon_logs", return_value=mock_log)
def test_fetch_tetra(mock_fetch, client):
    res = client.get("/tetragon")
    assert res.status_code == 200
    assert isinstance(res.get_json(), list)
    assert res.get_json()[0]["process_exec"]["parent"]["binary"] == "/bin/sh"

@patch("src.tetra_log.controller.fetch_tetragon_logs", return_value=mock_log)
def test_fetch_stix(mock_fetch, client):
    res = client.get("/tetragon/fetch-stix")
    assert res.status_code == 200
    data = res.get_json()
    assert isinstance(data, list) or isinstance(data, dict)

    if isinstance(data, dict) and data.get("type") == "bundle":
        for obj in data.get("objects", []):
            results = validate_instance(obj)
            print_results(results)
            assert results.is_valid  # ✅ will fail the test if STIX object is invalid

    elif isinstance(data, list):  # multiple bundles
        for bundle in data:
            if isinstance(bundle, dict) and bundle.get("type") == "bundle":
                for obj in bundle.get("objects", []):
                    results = validate_instance(obj)
                    print_results(results)
                    assert results.is_valid
    else:
        assert False, "Unexpected STIX format from /fetch-stix"

