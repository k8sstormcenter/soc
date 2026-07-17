import pytest
from unittest.mock import MagicMock, patch
from src.etl.stix_etl.controller import process_kubescape_row, stix_columns
from src.etl.stix_etl.etl import StixETL
import json

@pytest.fixture
def sample_rows():
    # Simulate ClickHouse rows with ISO8601 timestamp and data string
    return [
        [ 
           "{\"alertName\":\"Unexpected system call\",\"arguments\":{\"syscall\":\"pivot_root\"},\"infectedPID\":84862,\"md5Hash\":\"4e79f11b07df8f72e945e0e3b3587177\",\"profileMetadata\":{\"completion\":\"complete\",\"failOnProfile\":true,\"name\":\"replicaset-webapp-mywebapp-67965968bb\",\"status\":\"completed\",\"type\":0},\"severity\":1,\"sha1Hash\":\"b361a04dcb3086d0ecf960d3acaa776c62f03a55\",\"size\":\"730 kB\",\"timestamp\":\"2025-07-15T13:33:29.959206033Z\",\"trace\":{},\"uniqueID\":\"6a4ac7e4e4b094a2c27a46e6cc171dc9\"}",
           "empty",
           "R0003",
           "{\"clusterName\":\"bobexample\",\"containerID\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"containerName\":\"mywebapp-app\",\"hostNetwork\":false,\"namespace\":\"webapp\",\"podName\":\"webapp-mywebapp-67965968bb-hmnrq\",\"podNamespace\":\"webapp\",\"workloadKind\":\"Deployment\",\"workloadName\":\"webapp-mywebapp\",\"workloadNamespace\":\"webapp\"}",
           "{\"containerID\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"processTree\":{\"cmdline\":\"apache2 -DFOREGROUND\",\"comm\":\"apache2\",\"cwd\":\"/var/www/html\",\"gid\":0,\"path\":\"/usr/sbin/apache2\",\"pcomm\":\"containerd-shim\",\"pid\":84862,\"ppid\":84328,\"startTime\":\"0001-01-01T00:00:00Z\",\"uid\":0}}",
           "{\"k8s\":{\"containerName\":\"mywebapp-app\",\"namespace\":\"webapp\",\"node\":\"cplane-01\",\"owner\":{},\"podLabels\":{\"app.kubernetes.io/instance\":\"webapp\",\"app.kubernetes.io/name\":\"mywebapp\",\"pod-template-hash\":\"67965968bb\"},\"podName\":\"webapp-mywebapp-67965968bb-hmnrq\"},\"runtime\":{\"containerId\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"runtimeName\":\"containerd\"},\"timestamp\":1752586409959206033,\"type\":\"normal\"}",
           "error",
           "Unexpected system call: pivot_root",
           "Unexpected system call",
           "2025-07-15T13:33:29Z"
        ],
        [ 
           "{\"alertName\":\"Unexpected system call\",\"arguments\":{\"syscall\":\"pivot_root\"},\"infectedPID\":84862,\"md5Hash\":\"4e79f11b07df8f72e945e0e3b3587177\",\"profileMetadata\":{\"completion\":\"complete\",\"failOnProfile\":true,\"name\":\"replicaset-webapp-mywebapp-67965968bb\",\"status\":\"completed\",\"type\":0},\"severity\":1,\"sha1Hash\":\"b361a04dcb3086d0ecf960d3acaa776c62f03a55\",\"size\":\"730 kB\",\"timestamp\":\"2025-07-15T13:33:29.959206033Z\",\"trace\":{},\"uniqueID\":\"6a4ac7e4e4b094a2c27a46e6cc171dc9\"}",
           "empty",
           "R0003",
           "{\"clusterName\":\"bobexample\",\"containerID\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"containerName\":\"mywebapp-app\",\"hostNetwork\":false,\"namespace\":\"webapp\",\"podName\":\"webapp-mywebapp-67965968bb-hmnrq\",\"podNamespace\":\"webapp\",\"workloadKind\":\"Deployment\",\"workloadName\":\"webapp-mywebapp\",\"workloadNamespace\":\"webapp\"}",
           "{\"containerID\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"processTree\":{\"cmdline\":\"apache2 -DFOREGROUND\",\"comm\":\"apache2\",\"cwd\":\"/var/www/html\",\"gid\":0,\"path\":\"/usr/sbin/apache2\",\"pcomm\":\"containerd-shim\",\"pid\":84862,\"ppid\":84328,\"startTime\":\"0001-01-01T00:00:00Z\",\"uid\":0}}",
           "{\"k8s\":{\"containerName\":\"mywebapp-app\",\"namespace\":\"webapp\",\"node\":\"cplane-01\",\"owner\":{},\"podLabels\":{\"app.kubernetes.io/instance\":\"webapp\",\"app.kubernetes.io/name\":\"mywebapp\",\"pod-template-hash\":\"67965968bb\"},\"podName\":\"webapp-mywebapp-67965968bb-hmnrq\"},\"runtime\":{\"containerId\":\"04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1\",\"runtimeName\":\"containerd\"},\"timestamp\":1752586409959206033,\"type\":\"normal\"}",
           "error",
           "Unexpected system call: pivot_root",
           "Unexpected system call",
           "2025-07-15T13:33:29Z"
        ]
      ]

@pytest.fixture
def processed_rows(sample_rows):
    # Return processed rows using the same ISO timestamps
    return [
        [
            '2025-07-15T13:33:29Z',
            'webapp-mywebapp-67965968bb-hmnrq',
            'webapp',
            '[{"type": "process", "id": "process--250718T0754024504935e4da811000848620", "pid": 84862, "command_line": "apache2 -DFOREGROUND", "cwd": "/var/www/html", "created_time": "2025-07-18T07:54:02.458809+00:00Z", "extensions": {"container_id": "04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1", "flags": "Unexpected system call: pivot_root", "image_id": "", "pod_name": "webapp-mywebapp-67965968bb-hmnrq", "namespace": "webapp", "function_name": "R0003", "parent_pid": 84328, "parent_command_line": "containerd-shim", "kprobe0.capability": "", "kprobe1.syscall": "pivot_root", "kprobe2.trace": {}, "kprobe3.severity": 1, "kprobe4.infectedPID": 84862}}, {"type": "observed-data", "id": "observed-data--1f916810-5676-4af7-8fd8-d7f8895a694e", "created_time": "2025-07-18T07:54:02.458809+00:00Z", "first_observed": "2025-07-18T07:54:02.458809+00:00Z", "last_observed": "2025-07-18T07:54:02.458809+00:00Z", "number_observed": 1, "object_refs": ["process--250718T0754024504935e4da811000848620"], "extensions": {"alert_name": "Unexpected system call", "correlation": "250715T133329Z04935e4da811000843289f0e6fa8cc52", "rule_id": "R0003", "node_info": "cplane-01", "children": []}}]'
        ],
        [
            '2025-07-15T13:33:29Z',
            'webapp-mywebapp-67965968bb-hmnrq',
            'webapp',
            '[{"type": "process", "id": "process--250718T0754024604935e4da811000848620", "pid": 84862, "command_line": "apache2 -DFOREGROUND", "cwd": "/var/www/html", "created_time": "2025-07-18T07:54:02.466150+00:00Z", "extensions": {"container_id": "04935e4da811b72fe84da42fa691cfd273eb4a0680de6d73f72e61c0d044b4f1", "flags": "Unexpected system call: pivot_root", "image_id": "", "pod_name": "webapp-mywebapp-67965968bb-hmnrq", "namespace": "webapp", "function_name": "R0003", "parent_pid": 84328, "parent_command_line": "containerd-shim", "kprobe0.capability": "", "kprobe1.syscall": "pivot_root", "kprobe2.trace": {}, "kprobe3.severity": 1, "kprobe4.infectedPID": 84862}}, {"type": "observed-data", "id": "observed-data--0710df9a-764d-4dcf-ab83-108d8d88db8c", "created_time": "2025-07-18T07:54:02.466150+00:00Z", "first_observed": "2025-07-18T07:54:02.466150+00:00Z", "last_observed": "2025-07-18T07:54:02.466150+00:00Z", "number_observed": 1, "object_refs": ["process--250718T0754024604935e4da811000848620"], "extensions": {"alert_name": "Unexpected system call", "correlation": "250715T133329Z04935e4da811000843289f0e6fa8cc52", "rule_id": "R0003", "node_info": "cplane-01", "children": []}}]'
        ]
    ]

@patch("src.etl.stix_etl.etl.ClickHouseClient")
def test_stix_etl_fetch_and_process(mock_clickhouse_client_cls, sample_rows, processed_rows):
    # Mock ClickHouseClient().get_client()
    mock_client = MagicMock()
    mock_result = MagicMock()
    mock_result.result_rows = sample_rows
    mock_client.query.return_value = mock_result
    mock_clickhouse_client_cls.return_value.get_client.return_value = mock_client

    # Mock process_func to return our processed_rows fixtures
    def mock_process_func(row):
        return process_kubescape_row(row)

    etl = StixETL(
        table="test_table",
        processed_table="test_processed_table",
        column_names=stix_columns,
        time_column_index=0,
        process_func=mock_process_func,
        poll_interval=5
    )

    # Act
    etl.fetch_and_process()

    # Assert: insert called correctly
    mock_client.insert.assert_called_once()
    args, kwargs = mock_client.insert.call_args
    assert args[0] == "test_processed_table"
    actual_fields = [extract_fields(row) for row in args[1]]
    expected_fields = [extract_fields(row) for row in processed_rows]

    for i, (actual, expected) in enumerate(zip(actual_fields, expected_fields)):
        for key in expected:
            assert actual[key] == expected[key], f"Row {i} - {key} mismatch:\nActual: {actual[key]}\nExpected: {expected[key]}"

    assert kwargs["column_names"] == stix_columns

    # Assert: last_seen_ts is updated to the ISO string of the last row
    assert etl.last_seen_ts == sample_rows[-1][0]


def extract_fields(row):
    timestamp = row[0]
    pod_name = None
    namespace = None
    correlation = None

    stix_objects = json.loads(row[3])
    for obj in stix_objects:
        if obj["type"] == "process":
            pod_name = obj["extensions"].get("pod_name")
            namespace = obj["extensions"].get("namespace")
        elif obj["type"] == "observed-data":
            correlation = obj["extensions"].get("correlation")
    
    return {
        "timestamp": timestamp,
        "pod_name": pod_name,
        "namespace": namespace,
        "correlation": correlation,
    }