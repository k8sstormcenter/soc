-- Forensic SOC ClickHouse schema
-- Pixie DDL reference: src/vizier/funcs/md_udtfs/md_udtfs_impl.h (839af02)
-- Pixie type map (PixieTypeToClickHouseType):
--   TIME64NS → DateTime64(9), except event_time → DateTime64(3)
--   INT64 → Int64 | FLOAT64 → Float64 | STRING → String
--   BOOLEAN → UInt8 | UINT128 → String
-- Pixie adds: hostname String, event_time DateTime64(3)
-- Engine: MergeTree() | ORDER BY (hostname, event_time) | PARTITION BY toYYYYMM(event_time)

CREATE DATABASE IF NOT EXISTS forensic_db;

-- Kubescape alerts (Vector kubescape_to_alerts sink)
CREATE TABLE IF NOT EXISTS forensic_db.alerts (
    timestamp       DateTime64(3),
    ingest_time     DateTime64(3) DEFAULT now64(3),
    rule_id         LowCardinality(String),
    alert_name      LowCardinality(String),
    severity        UInt8,
    unique_id       String,
    cluster_name    LowCardinality(String),
    namespace       LowCardinality(String),
    pod_name        String,
    container_name  LowCardinality(String),
    container_id    String,
    workload_name   LowCardinality(String),
    workload_kind   LowCardinality(String),
    image           LowCardinality(String),
    infected_pid    UInt32,
    process_name    LowCardinality(String),
    process_cmdline String,
    message         String,
    raw_event       String
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(timestamp)
  ORDER BY (timestamp, severity, namespace, rule_id)
  TTL toDateTime(timestamp) + INTERVAL 90 DAY DELETE
  SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

-- Kubescape raw logs — columns match infer_flat.json exactly
-- Vector kubescape_enrich sink writes here, Pixie adaptive_export reads it
-- skip_unknown_fields=true on the Vector sink drops any extra fields
CREATE TABLE IF NOT EXISTS forensic_db.kubescape_logs (
    BaseRuntimeMetadata   String,
    CloudMetadata         String,
    RuleID                String,
    RuntimeK8sDetails     String,
    RuntimeProcessDetails String,
    event                 String,
    event_time            UInt64,
    hostname              String,
    level                 String DEFAULT '',
    message               String DEFAULT '',
    msg                   String DEFAULT '',
    processtree_depth     String DEFAULT ''
) ENGINE = MergeTree()
  ORDER BY (event_time, hostname)
  PARTITION BY toYYYYMM(toDateTime(event_time))
  TTL toDateTime(event_time) + INTERVAL 30 DAY DELETE
  SETTINGS index_granularity = 8192;

-- Pixie http_events (src/stirling/source_connectors/socket_tracer/http_table.h)
CREATE TABLE IF NOT EXISTS forensic_db.http_events (
    time_          DateTime64(9),
    upid           String,
    remote_addr    String,
    remote_port    Int64,
    local_addr     String,
    local_port     Int64,
    trace_role     Int64,
    encrypted      UInt8,
    major_version  Int64,
    minor_version  Int64,
    content_type   Int64,
    req_headers    String,
    req_method     String,
    req_path       String,
    req_body       String,
    req_body_size  Int64,
    resp_headers   String,
    resp_status    Int64,
    resp_message   String,
    resp_body      String,
    resp_body_size Int64,
    latency        Int64,
    hostname       String,
    event_time     DateTime64(3)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_time)
  ORDER BY (hostname, event_time);

-- Pixie dns_events (src/stirling/source_connectors/socket_tracer/dns_table.h)
CREATE TABLE IF NOT EXISTS forensic_db.dns_events (
    time_        DateTime64(9),
    upid         String,
    remote_addr  String,
    remote_port  Int64,
    local_addr   String,
    local_port   Int64,
    trace_role   Int64,
    encrypted    UInt8,
    req_header   String,
    req_body     String,
    resp_header  String,
    resp_body    String,
    latency      Int64,
    hostname     String,
    event_time   DateTime64(3)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_time)
  ORDER BY (hostname, event_time);

-- Pixie conn_stats (src/stirling/source_connectors/socket_tracer/conn_stats_table.h)
CREATE TABLE IF NOT EXISTS forensic_db.conn_stats (
    time_       DateTime64(9),
    upid        String,
    remote_addr String,
    remote_port Int64,
    trace_role  Int64,
    addr_family Int64,
    protocol    Int64,
    ssl         UInt8,
    conn_open   Int64,
    conn_close  Int64,
    conn_active Int64,
    bytes_sent  Int64,
    bytes_recv  Int64,
    hostname    String,
    event_time  DateTime64(3)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_time)
  ORDER BY (hostname, event_time);

-- Pixie process_stats (src/stirling/source_connectors/proc_stat/proc_stat_table.h)
CREATE TABLE IF NOT EXISTS forensic_db.process_stats (
    time_        DateTime64(9),
    upid         String,
    major_faults Int64,
    minor_faults Int64,
    cpu_utime_ns Int64,
    cpu_ktime_ns Int64,
    num_threads  Int64,
    vsize_bytes  Int64,
    rss_bytes    Int64,
    rchar_bytes  Int64,
    wchar_bytes  Int64,
    read_bytes   Int64,
    write_bytes  Int64,
    hostname     String,
    event_time   DateTime64(3)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_time)
  ORDER BY (hostname, event_time);

-- Pixie network_stats (src/stirling/source_connectors/network_stats/network_stats_table.h)
CREATE TABLE IF NOT EXISTS forensic_db.network_stats (
    time_      DateTime64(9),
    pod_id     String,
    rx_bytes   Int64,
    rx_packets Int64,
    rx_errors  Int64,
    rx_drops   Int64,
    tx_bytes   Int64,
    tx_packets Int64,
    tx_errors  Int64,
    tx_drops   Int64,
    hostname   String,
    event_time DateTime64(3)
) ENGINE = MergeTree()
  PARTITION BY toYYYYMM(event_time)
  ORDER BY (hostname, event_time);
