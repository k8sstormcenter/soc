import pytest
import json
import uuid
from src.etl.pixie_etl.etl import PixieETL

@pytest.mark.parametrize("table_name,processed_table,stix_table,column_names,row_data,expected_row", [
    (
        "http_events",
        "http_logs",
        "http_stix",
        [
            "time_", "upid", "encrypted", "req_path",
            "pod_name", "namespace", "container_id", "pid", "node_name"
        ],
        [
            1234567890,
            uuid.UUID("00000003-0000-c8d4-0000-00000004354b"),
            1,
            "/test",
            "my-pod",
            "default",
            "d2eac5a343c067bacd3327b7a457802e314108a228ce0e6cad08c98824f335e2",
            51412,
            "node-01"
        ],
        [
            1234567890,
            uuid.UUID("00000003-0000-c8d4-0000-00000004354b"),
            1,
            "/test",
            "my-pod",
            "default",
            "d2eac5a343c067bacd3327b7a457802e314108a228ce0e6cad08c98824f335e2",
            51412,
            "node-01"
        ]
    ),
    (
        "dns_events",
        "dns_logs",
        "dns_stix",
        [
            "time_", "upid", "encrypted", "req_body",
            "pod_name", "namespace", "container_id", "pid", "node_name"
        ],
        [
            1234567891,
            uuid.UUID("00000003-0000-c8d4-0000-00000004354c"),
            0,
            json.dumps({"queries": [{"name": "example.com", "type": "A"}]}),
            "dns-pod",
            "dns-namespace",
            "abcd1234ef567890abcd1234ef567890abcd1234ef567890abcd1234ef567890",
            61413,
            "node-02"
        ],
        [
            1234567891,
            uuid.UUID("00000003-0000-c8d4-0000-00000004354c"),
            0,
            json.dumps({"queries": [{"name": "example.com", "type": "A"}]}),
            "dns-pod",
            "dns-namespace",
            "abcd1234ef567890abcd1234ef567890abcd1234ef567890abcd1234ef567890",
            61413,
            "node-02"
        ]
    )
])
def test_fetch_and_process_inserts_dual_data(mocker, table_name, processed_table, stix_table, column_names, row_data, expected_row):
    # Mock get_px_connection
    mock_conn = mocker.Mock()
    mock_script = mocker.Mock()
    mock_script.results.return_value = iter([row_data])
    mock_conn.prepare_script.return_value = mock_script
    mocker.patch("src.etl.pixie_etl.etl.get_px_connection", return_value=mock_conn)

    # Mock ClickHouseClient().get_client().insert
    mock_clickhouse_client = mocker.Mock()
    mock_clickhouse_client.insert = mocker.Mock()
    mock_clickhouse_client_cls = mocker.Mock()
    mock_clickhouse_client_cls.get_client.return_value = mock_clickhouse_client
    mocker.patch("src.etl.pixie_etl.etl.ClickHouseClient", return_value=mock_clickhouse_client_cls)

    etl = PixieETL(
        table_name=table_name,
        processed_table=processed_table,
        stix_table=stix_table,
        column_names=column_names,
        poll_interval=10
    )

    etl.fetch_and_process()

    # ✅ Check two inserts: raw logs + STIX
    assert mock_clickhouse_client.insert.call_count == 2

    # ✅ First insert: raw logs
    args_logs, kwargs_logs = mock_clickhouse_client.insert.call_args_list[0]
    assert args_logs[0] == processed_table
    inserted_rows_logs = args_logs[1]
    assert inserted_rows_logs[0] == expected_row
    assert kwargs_logs["column_names"] == column_names

    # ✅ Second insert: STIX bundles
    args_stix, kwargs_stix = mock_clickhouse_client.insert.call_args_list[1]
    assert args_stix[0] == stix_table
    inserted_rows_stix = args_stix[1]

    # Each row: [timestamp:int, data:str]
    assert isinstance(inserted_rows_stix[0][0], int)
    assert isinstance(inserted_rows_stix[0][1], str)

    # Column names should match your STIX table definition
    assert kwargs_stix["column_names"] == ["timestamp", "data"]

    # ✅ Ensure last_seen_ns updated correctly
    assert etl.last_seen_ns == row_data[0]

