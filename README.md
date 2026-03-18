# Systematic Trade Monitor

This repository is a faithful local recreation of the monitoring stack described in:

- Article: [Monitoring Trading Systems](https://osquant.com/papers/monitoring-trading-systems/)
- Reference repository: [robolyst/trading-monitoring-demo](https://github.com/robolyst/trading-monitoring-demo)

Citation:
Letchford (2023), "How to engineer a monitoring system for your trading strategy", OS Quant.

The source project contents were provided locally at `web/trading-monitoring-demo-main`, and this repo’s runnable stack files were aligned to that source.

[Further enhancements under construction]

## Project objective

The core objective is to demonstrate an end-to-end observability pipeline for a trading-like process, using a realistic but minimal architecture.

At a high level, the system proves that you can:

1. Generate structured trading events continuously.
2. Ingest those events with minimal coupling.
3. Store them as queryable time-series data.
4. Visualize behavior in near real time.
5. Operate the whole workflow in a repeatable, containerized local environment.

This is less about trading alpha and more about engineering reliability and visibility.

## What you should learn from this project

By reading and running this repo, you should build confidence in:

1. How to design a decoupled telemetry pipeline.
2. How structured logs become time-series metrics.
3. How container orchestration controls service dependencies.
4. How Grafana provisioning turns dashboards into version-controlled infrastructure.
5. How to validate data flow stage-by-stage when debugging distributed systems.

## Architecture at a glance

```text
Trader process (Python)
  -> JSON log line (stdout + file)
  -> shared volume file
  -> Telegraf tail input
  -> Telegraf JSON parser + timestamp mapping
  -> Telegraf socket_writer output (Influx line protocol)
  -> QuestDB ILP TCP ingestion (port 9009)
  -> QuestDB table (price_log)
  -> Grafana PostgreSQL datasource (port 8812)
  -> Provisioned dashboard
```

## Why these tools were chosen

## Docker and Docker Compose

### What Docker is

Docker is a container runtime that packages an application with its dependencies into a reproducible unit. For this project, each major system component runs in its own container.

### What Docker Compose is

Compose is a multi-container orchestration layer for local development. It defines service topology, environment variables, shared volumes, ports, and startup dependencies in one file (`docker-compose.yaml`).

### Why Docker/Compose are used here

1. Eliminates host dependency drift.
2. Makes setup one command (`docker compose up --build`).
3. Provides deterministic networking between services.
4. Models a production-like multi-service deployment pattern.

## Trader service (Python + NumPy + structlog)

### What this service is

A synthetic producer that simulates a continuously moving price series.

### Why NumPy

`numpy` provides fast and concise random number generation (`np.random.randn`) to model noisy returns.

### Why structlog

`structlog` emits machine-readable JSON logs, which are easier to parse safely than free-form text. Structured logging is foundational for stable telemetry pipelines.

## Telegraf

### What Telegraf is

Telegraf is an ingestion and transformation agent with pluggable inputs and outputs. Think of it as a data-plane adapter between producers and data stores.

### What it does in this project

1. Tails the trader log file.
2. Parses JSON line-by-line.
3. Maps event/timestamp fields into metric semantics.
4. Emits Influx line protocol over TCP to QuestDB.

### Why Telegraf is useful here

1. Keeps producer code simple.
2. Encapsulates parsing and forwarding behavior in config.
3. Allows future extension (filters, processors, additional outputs) without changing app code.

## QuestDB

### What QuestDB is

QuestDB is a high-performance time-series database with SQL support and multiple ingestion interfaces (including ILP and PostgreSQL wire protocol).

### What it does in this project

1. Receives line protocol on port `9009`.
2. Creates/stores table `price_log`.
3. Exposes query interfaces:
   - Web/REST (`9000`)
   - PostgreSQL wire (`8812`) used by Grafana

### Why QuestDB fits

1. Fast append-heavy ingest.
2. SQL-friendly analytics.
3. Straightforward local deployment.

## Grafana OSS

### What Grafana is

Grafana is a visualization and dashboard platform for operational and analytical telemetry.

### What it does in this project

1. Connects to QuestDB using PostgreSQL datasource provisioning.
2. Loads dashboard JSON automatically at startup.
3. Renders a near-real-time price chart.

### Why Grafana provisioning matters

Provisioning converts UI configuration into files. This makes dashboards reproducible, reviewable, and source-controlled.

## End-to-end data contract

The producer emits JSON events with a stable schema:

```json
{
  "event": "price_log",
  "price": 101.234,
  "level": "info",
  "timestamp": "2026-03-15T13:06:23.760660Z"
}
```

Field semantics:

1. `event`: logical measurement name (`price_log`), used downstream as table/measurement identity.
2. `price`: floating-point value to monitor over time.
3. `level`: log level tag (currently `info` from structlog/logging integration).
4. `timestamp`: event time in UTC ISO format; parsed by Telegraf as event timestamp.

## Repository structure

```text
.
├── docker-compose.yaml
├── telegraf.conf
├── Makefile
├── trader/
│   ├── Dockerfile
│   └── trader.py
├── grafana/
│   └── provisioning/
│       ├── dashboards/
│       │   ├── dashboard.json
│       │   └── dashboards.yaml
│       └── datasources/
│           └── datasources.yaml
└── web/
    └── trading-monitoring-demo-main/
```

## Section-by-section code walkthrough

## 1) `trader/trader.py`

Execution flow:

1. Reads `LOG_FILE_NAME` from environment.
2. Configures Python logging with:
   - console handler for container logs
   - file handler to shared volume path
3. Configures `structlog` processors for level + UTC timestamp + JSON rendering.
4. Initializes `price = 100`.
5. Infinite loop:
   - updates price by multiplicative noisy return (`price *= (1 + randn * 0.01)`)
   - logs JSON event `event="price_log"` and `price`
   - sleeps `0.5s`

Engineering rationale:

1. Multiplicative update resembles return dynamics better than additive jitter.
2. JSON logs reduce parser ambiguity.
3. Explicit timestamping preserves event-time semantics.
4. Continuous loop creates realistic streaming telemetry.

## 2) `trader/Dockerfile`

Build flow:

1. Base image: `python:3.11.0-slim-buster`.
2. Installs pinned dependencies:
   - `numpy==1.23.5`
   - `structlog==22.3.0`
3. Sets `WORKDIR /app`.
4. Copies `trader.py` into container.

Rationale:

1. Pinning dependency versions improves reproducibility.
2. Slim image keeps local build size reasonable.
3. Compose defines runtime command, keeping Dockerfile generic.

## 3) `telegraf.conf`

Agent behavior:

1. Collect interval: `1s`.
2. Flush interval: `1s`.

Input plugin (`[[inputs.tail]]`):

1. Reads log file path from `$LOG_FILE_NAME`.
2. Tails from beginning (`from_beginning=true`).
3. Parses strict JSON (`json_strict=true`).
4. Uses:
   - `json_name_key = "event"`
   - `json_time_key = "timestamp"`
   - `json_time_format = "2006-01-02T15:04:05.999999Z"`

Output plugin (`[[outputs.socket_writer]]`):

1. Sends line protocol to `tcp://$QUESTDB_HOST_NAME`.
2. Uses `data_format = "influx"`.

Rationale:

1. Tail input decouples producer process from transport concerns.
2. Strict JSON parsing fails fast on bad input, improving data quality.
3. Socket output provides low-overhead write path into QuestDB ILP.

## 4) `docker-compose.yaml`

Services:

1. `trader`
   - builds local image
   - runs `python trader.py`
   - writes logs to shared `logdata` volume
2. `questdb`
   - exposes ports `9000`, `9009`, `8812`
   - healthcheck gate for dependent services
3. `telegraf`
   - waits for QuestDB healthy
   - reads shared log volume
   - loads `telegraf.conf`
4. `grafana`
   - waits for QuestDB healthy
   - mounts provisioning files
   - enables local auth defaults + anonymous editor mode

Infrastructure semantics:

1. Service DNS names equal Compose service names.
2. `depends_on` + healthcheck limit startup races.
3. Named volume `logdata` is the handoff buffer between producer and shipper.

## 5) Grafana provisioning files

### `grafana/provisioning/datasources/datasources.yaml`

1. Creates default datasource `QuestDB`.
2. Uses PostgreSQL connector type.
3. Endpoint from env `QUESTDB_URL` (`questdb:8812`).
4. Credentials `admin/quest` for local demo.

### `grafana/provisioning/dashboards/dashboards.yaml`

1. Registers file-based dashboard provider.
2. Points to `/etc/grafana/provisioning/dashboards`.

### `grafana/provisioning/dashboards/dashboard.json`

1. Defines panel/query/refresh defaults.
2. Uses SQL query against `price_log` time-series data.
3. Dashboard refresh interval is `5s`.

Note: export JSON may contain extra metadata fields from Grafana internals; the key behavior is successful loading plus valid query execution.

## Runtime lifecycle (what happens after `up`)

1. Compose network and volume are created.
2. QuestDB starts and becomes healthy.
3. Trader starts emitting JSON events into shared log file.
4. Telegraf starts tailing and forwarding parsed events.
5. QuestDB creates table `price_log` on first writes and appends rows.
6. Grafana starts, applies migrations, provisions datasource/dashboard, serves UI.
7. Dashboard queries QuestDB and updates continuously.

## Expected healthy signals

You should observe all of these in a healthy run.

1. `docker compose ps`
   - all services are `Up`
   - QuestDB is `healthy`
2. `docker compose logs trader`
   - steady stream of JSON `price_log` entries
3. `docker compose logs telegraf`
   - loaded inputs: `tail`
   - loaded outputs: `socket_writer`
   - no recurring parse errors
4. `docker compose logs questdb`
   - ILP connection from Telegraf
   - table creation `price_log`
   - WAL apply jobs with rows processed
5. QuestDB SQL API
   - `select count() from price_log` increases over time
6. Grafana UI/API
   - HTTP 200 on `/login`
   - dashboard `Trader log dashboard` visible

## How to run

```bash
docker compose up --build -d
```

Stop:

```bash
docker compose down
```

## Local endpoints

1. Grafana: `http://localhost:3000`
2. QuestDB web/SQL endpoint: `http://localhost:9000`
3. QuestDB PostgreSQL wire endpoint: `localhost:8812`
4. QuestDB ILP endpoint: `localhost:9009`

## Makefile shortcuts (recommended)

```bash
make up          # start stack
make ps          # service status
make logs        # follow all service logs
make count       # row count in price_log
make watch       # live terminal monitor (status + row count)
make endpoints   # print local URLs
make down        # stop stack
```

## Validation and smoke test procedure

Run these in order for an operational confidence check:

1. Start stack:
```bash
make up
```
2. Verify service status:
```bash
make ps
```
3. Verify ingestion count is increasing:
```bash
make count
sleep 2
make count
```
4. Follow logs:
```bash
make logs
```
5. Open Grafana UI and confirm live chart.

## Failure modes and troubleshooting

## Trader emits logs but no rows in QuestDB

Likely causes:

1. Telegraf cannot read log file path.
2. JSON parse failure in Telegraf.
3. Telegraf cannot connect to `questdb:9009`.

Checks:

1. `docker compose logs telegraf`
2. Confirm env vars in compose for `LOG_FILE_NAME` and `QUESTDB_HOST_NAME`.

## QuestDB has rows but Grafana chart is empty

Likely causes:

1. Datasource connectivity/config issue.
2. Dashboard query mismatch.
3. Time-range mismatch.

Checks:

1. Query QuestDB directly in web console.
2. Verify datasource is provisioned and default.
3. Set dashboard time range to recent window.

## Port conflicts

If `3000`, `9000`, `9009`, or `8812` are in use, remap host ports in `docker-compose.yaml`.

## ARM/Apple Silicon note

Some image tags may run via emulation depending on available manifests. If startup is slow on first run, image pull/extraction and architecture translation overhead are common causes.

## Security notes (local demo vs production)

Current settings are intentionally permissive for local convenience.

1. Grafana admin defaults are set in environment.
2. Anonymous Grafana access is enabled with editor role.
3. No TLS between internal services.

For production-like hardening:

1. Disable anonymous access.
2. Use secret management for credentials.
3. Add network segmentation and TLS.
4. Restrict exposed host ports.
5. Add authn/authz around query endpoints.

## Performance and scalability considerations

Current profile is tiny (single producer, low write rate), but architecture scales conceptually:

1. Add more producers writing structured logs.
2. Use multiple Telegraf agents or sidecars.
3. Partition by measurement/source strategy in QuestDB.
4. Add retention/compaction policies and alerting layers.

Potential bottlenecks to watch in larger systems:

1. File-tail throughput and log rotation strategy.
2. Telegraf parsing CPU.
3. QuestDB WAL apply latency.
4. Grafana query cadence and dashboard cardinality.

## Project scope boundaries

This project demonstrates observability architecture, not trading strategy quality.

Not included by design:

1. Risk engine and order management.
2. Signal generation/business alpha logic.
3. Compliance and audit controls.
4. High-availability deployment topology.

## Faithfulness note

This repo was recreated to match the provided source folder (`web/trading-monitoring-demo-main`) for the runnable stack files:

1. `docker-compose.yaml`
2. `telegraf.conf`
3. `trader/Dockerfile`
4. `trader/trader.py`
5. `grafana/provisioning/datasources/datasources.yaml`
6. `grafana/provisioning/dashboards/dashboards.yaml`
7. `grafana/provisioning/dashboards/dashboard.json`

## License/tooling note

All core components used here are available in free/open-source editions suitable for local experimentation.
