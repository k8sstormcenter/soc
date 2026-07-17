# Hive Sentinel

Hive Sentinel is a microservice that connects to a Pixie observability cluster and ClickHouse, fetches Tetragon and Kubescape logs, and transforms them into [STIX 2.1](https://oasis-open.github.io/cti-documentation/stix/intro) bundles for security operations and threat detection pipelines.

## 🧬 What It Does

* Connects to Pixie via their Python SDK to retrieve logs.
* Connects to ClickHouse to persist processed STIX objects.
* Parses, cleans, and converts logs to STIX 2.1 format with custom correlation logic.
* Runs automated ETL pipelines for:

  * Tetragon to STIX
  * Kubescape to STIX
  * Pixie http\_events and dns\_events to Clickhouse tables alongside with their STIX transformations
* Exposes REST API endpoints to:

  * Fetch raw and STIX-transformed logs
  * Start/stop Pixie ETL pipelines
  * Check ETL status
  * Query ClickHouse table contents with filters for debugging

## 🚀 Deployment with Makefile

Navigate to the `/honeycluster` directory:

```bash
make hive-sentinel HIVE_SENTINEL_IMAGE=ghcr.io/<your-org>/hivesentinel:<tag>
```

This will:

* Generate the Pixie API token automatically.
* Fetch the Pixie Cluster ID.
* Retrieve the ClickHouse admin password.
* Uses the `honey` namespace
* Deploy Hive Sentinel using the environment variables injected from `honeystack/hive_sentinel/values.yaml.templatefile`.

## How to Run Locally (Development)

Install [Poetry](https://python-poetry.org/) and run:

```bash
poetry install
poetry run python main.py
```

Configure your Pixie and ClickHouse environment variables before starting.

## Environment Setup

Create a `.env` file:

```
PIXIE_API_TOKEN=px-api-...
PIXIE_CLUSTER_ID=...
CLICKHOUSE_HOST=localhost
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=...
CLICKHOUSE_DB=default
```

## 🚀 How to Test

```bash
poetry install
poetry run pytest
```

Covers Pixie ETL, STIX ETL, and REST endpoints.

## Endpoints

### Pixie ETL Control

* `POST /pixie-etl/start` - Start ETL for a table with filters
* `POST /pixie-etl/stop` - Stop ETL by UUID
* `GET /pixie-etl/status` - List running ETLs

### Data Fetch Endpoints

Fetch raw logs:

* `GET /http_events`
* `GET /dns_events`
* `GET /tetragon_logs`
* `GET /kubescape_logs`

Fetch STIX bundles:

* `GET /http_stix`
* `GET /dns_stix`
* `GET /tetragon_stix`
* `GET /kubescape_stix`

All endpoints support `?limit=` and filters for debugging pipelines.

## Filters

Use filters to refine data retrieval during testing:

### `/http_events`, `/dns_events`

* `pod_name`, `node_name`, `namespace`, `container_id`, `remote_addr`

### `/tetragon_logs`

* `node_name`, `type`

### `/kubescape_logs`

* `event`, `level`, `msg`

### `/http_stix`, `/dns_stix`, `/tetragon_stix`, `/kubescape_stix`

* Only `limit` supported, no pagination

## 🛠️ Developer Notes

👉 Uses `apscheduler` for periodic ETL polling.
👉 Uses `clickhouse-connect` for ingestion.
👉 Uses `python-dotenv` for local environment management.
👉 StixETLs start automatically in production and are disabled during tests.
👉 During the tests, Pixie and Clickhouse connections are mocked. No real Database connection used

---

Made with ❤️ for scalable observability and STIX pipelines.
