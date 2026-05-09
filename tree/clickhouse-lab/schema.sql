-- Forensic SOC ClickHouse schema — KUBESCAPE side only.
-- ----------------------------------------------------------------------
-- This installer creates ONLY the kubescape ingest tables. The 12
-- pixie observation tables (http_events, dns_events, redis_events, …)
-- and the operator-owned forensic_db.adaptive_attribution table are
-- created by the adaptive_export operator at boot, via its embedded
-- DDL (see pixie/src/vizier/services/adaptive_export/internal/clickhouse/
-- {schema.sql, apply.go}).
--
-- Owner split:
--   soc/tree/clickhouse-lab (this file): forensic_db, alerts, kubescape_logs
--   adaptive_export operator (Apply at boot): 12 pixie tables + adaptive_attribution
--
-- The operator refuses to start if any pixie table was auto-created by
-- Pixie's retention plugin BEFORE the operator's Apply ran (would be
-- missing namespace + pod columns required by analyst JOINs against
-- adaptive_attribution). See clickhouse.VerifyPixieSchema.
--
-- Pixie type map (PixieTypeToClickHouseType, used by the operator):
--   TIME64NS → DateTime64(9), except event_time → DateTime64(3)
--   INT64 → Int64 | FLOAT64 → Float64 | STRING → String
--   BOOLEAN → UInt8 | UINT128 → String

CREATE DATABASE IF NOT EXISTS forensic_db;

-- Kubescape alerts (Vector kubescape_to_alerts sink).
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

-- Kubescape raw logs — columns match infer_flat.json exactly.
-- Vector kubescape_enrich sink writes here; the adaptive_export operator
-- polls this table (WHERE hostname='<this-node>' AND event_time>watermark)
-- and derives the workload anomaly_hash = sha256[:16] of (pid:comm:pod:ns).
-- The anomaly_hash column below is preserved DEFAULT '' for compat with
-- any existing Vector VRL transform that pre-computes it; the operator
-- itself does not depend on it being non-empty.
-- skip_unknown_fields=true on the Vector sink drops any extra fields.
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
    processtree_depth     String DEFAULT '',
    anomaly_hash          String DEFAULT ''
) ENGINE = MergeTree()
  ORDER BY (event_time, hostname)
  PARTITION BY toYYYYMM(toDateTime(event_time))
  TTL toDateTime(event_time) + INTERVAL 30 DAY DELETE
  SETTINGS index_granularity = 8192;
