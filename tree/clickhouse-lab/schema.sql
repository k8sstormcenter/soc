-- Forensic SOC database schema for kubescape alert storage
-- Run via: clickhouse-client --multiquery < schema.sql

CREATE DATABASE IF NOT EXISTS forensic_db ON CLUSTER 'soc-cluster';

-- Local table on each shard (ReplicatedMergeTree for HA)
CREATE TABLE IF NOT EXISTS forensic_db.alerts_local ON CLUSTER 'soc-cluster' (
    -- Time
    timestamp       DateTime64(3),
    ingest_time     DateTime64(3) DEFAULT now64(3),

    -- Alert identity
    rule_id         LowCardinality(String),
    alert_name      LowCardinality(String),
    severity        UInt8,
    unique_id       String,

    -- Kubernetes context
    cluster_name    LowCardinality(String),
    namespace       LowCardinality(String),
    pod_name        String,
    container_name  LowCardinality(String),
    container_id    String,
    workload_name   LowCardinality(String),
    workload_kind   LowCardinality(String),
    image           LowCardinality(String),

    -- Process context
    infected_pid    UInt32,
    process_name    LowCardinality(String),
    process_cmdline String,

    -- Alert message
    message         String,

    -- Full raw event JSON for deep forensics
    raw_event       String
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/forensic_db/alerts_local',
    '{replica}'
)
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, severity, namespace, rule_id)
TTL toDateTime(timestamp) + INTERVAL 90 DAY DELETE
SETTINGS
    index_granularity = 8192,
    ttl_only_drop_parts = 1;

-- Distributed table — routes INSERTs across shards by (namespace, pod_name) hash
CREATE TABLE IF NOT EXISTS forensic_db.alerts ON CLUSTER 'soc-cluster'
AS forensic_db.alerts_local
ENGINE = Distributed(
    'soc-cluster',
    'forensic_db',
    'alerts_local',
    sipHash64(namespace, pod_name)
);

-- Daily rollup materialized view (1-year retention for dashboards)
CREATE TABLE IF NOT EXISTS forensic_db.alerts_daily ON CLUSTER 'soc-cluster' (
    day             Date,
    rule_id         LowCardinality(String),
    alert_name      LowCardinality(String),
    namespace       LowCardinality(String),
    count           UInt64,
    max_severity    UInt8
)
ENGINE = ReplicatedSummingMergeTree(
    '/clickhouse/tables/{shard}/forensic_db/alerts_daily',
    '{replica}'
)
PARTITION BY toYYYYMM(day)
ORDER BY (day, rule_id, namespace)
TTL day + INTERVAL 365 DAY DELETE;

CREATE MATERIALIZED VIEW IF NOT EXISTS forensic_db.alerts_daily_mv ON CLUSTER 'soc-cluster'
TO forensic_db.alerts_daily AS
SELECT
    toDate(timestamp) AS day,
    rule_id,
    alert_name,
    namespace,
    count() AS count,
    max(severity) AS max_severity
FROM forensic_db.alerts_local
GROUP BY day, rule_id, alert_name, namespace;
