import pytest
from unittest.mock import MagicMock

@pytest.fixture(autouse=True)
def patch_clickhouse_and_pixie(monkeypatch):
    # Patch ClickHouseClient
    mock_client = MagicMock()
    mock_client.get_client.return_value = MagicMock()
    monkeypatch.setattr("src.clickhouse_client.ClickHouseClient", lambda: mock_client)

    # Patch get_px_connection
    monkeypatch.setattr("src.pixie_client.get_px_connection", lambda: MagicMock())
    monkeypatch.setattr("src.tetra_log.reader.get_px_connection", lambda: MagicMock())