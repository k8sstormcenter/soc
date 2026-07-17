import json
from src.pixie_client import get_px_connection
from src.kubescape_log.data.kubescape_reader import (
    fetch_kubescape_logs,
)


def get_dns_script(event_time_ns):
    print(event_time_ns)
    return f"""
import px

df = px.DataFrame(table='dns_events')

df = df[px.abs(px.time_to_int64(df.time_) - {event_time_ns}) < px.parse_duration("15s")]

df.resolve_name = px.pluck(px.pluck_array(px.pluck(df.req_body, "queries"), 0), "name")
df = df[px.regex_match(".*.cluster.local", df.resolve_name) != True]

df = df['time_', 'latency', 'req_header', 'req_body',
        'resp_header', 'resp_body']

px.display(df, "dns")
"""


def get_http_script(event_time_ns, pod_name):
    return f"""
import px

def add_source_dest_columns(df):
    df.pod = df.ctx['pod']
    df.namespace = df.ctx['namespace']

    # If remote_addr is a pod, get its name. If not, use IP address.
    df.ra_pod = px.pod_id_to_pod_name(px.ip_to_pod_id(df.remote_addr))
    df.is_ra_pod = df.ra_pod != ''
    df.ra_name = px.select(df.is_ra_pod, df.ra_pod, df.remote_addr)

    df.is_server_tracing = df.trace_role == 2
    df.is_source_pod_type = px.select(df.is_server_tracing, df.is_ra_pod, True)
    df.is_dest_pod_type = px.select(df.is_server_tracing, True, df.is_ra_pod)

    # Set source and destination based on trace_role.
    df.source = px.select(df.is_server_tracing, df.ra_name, df.pod)
    df.destination = px.select(df.is_server_tracing, df.pod, df.ra_name)

    # Filter out messages with empty source / destination.
    df = df[df.source != '']
    df = df[df.destination != '']

    df = df.drop(['ra_pod', 'is_ra_pod', 'ra_name', 'is_server_tracing'])

    return df

df = px.DataFrame(table='http_events')
df = add_source_dest_columns(df)
df = df[px.abs(px.time_to_int64(df.time_) - {event_time_ns}) < px.parse_duration("15s")]
df = df[df.source == "webapp/{pod_name}"]
df = df['time_', 'latency', 'major_version', 'req_path',
        'req_method', 'req_headers', 'req_body', 'req_body_size', 'resp_status',
        'resp_message', 'resp_headers', 'resp_body', 'resp_body_size']

px.display(df, "http")
"""


def deep_clean_bstrings(val):
    if isinstance(val, dict):
        return {k: deep_clean_bstrings(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [deep_clean_bstrings(i) for i in val]
    elif isinstance(val, bytes):
        try:
            return val.decode("utf-8")
        except:
            return str(val)
    return val


def extract_log_fields(row, keys):
    return {k: deep_clean_bstrings(row[k]) for k in keys}


def get_bundle():
    kubescape_logs = fetch_kubescape_logs()
    conn = get_px_connection()
    bundle = []

    dns_keys = [
        "time_",
        "latency",
        "req_header",
        "req_body",
        "resp_header",
        "resp_body",
    ]

    http_keys = [
        "time_",
        "latency",
        "major_version",
        "req_path",
        "req_method",
        "req_headers",
        "req_body",
        "req_body_size",
        "resp_status",
        "resp_message",
        "resp_headers",
        "resp_body",
        "resp_body_size",
    ]

    for k_log in kubescape_logs:
        event = {**k_log}

        dns_script = conn.prepare_script(get_dns_script(event["time_ns"]))
        dns_logs = [
            extract_log_fields(row, dns_keys) for row in dns_script.results("dns")
        ]
        # dns_logs.persist_forensically()  # (to_db)
        http_script = conn.prepare_script(
            get_http_script(event["time_ns"], event["pod_name"])
        )
        http_logs = [
            extract_log_fields(row, http_keys) for row in http_script.results("http")
        ]
        # http_logs.persist_forensically()  # (to_db)

        event["dns_logs"] = dns_logs
        event["http_logs"] = http_logs
        bundle.append(event)

    return bundle
