# Architecture and Implementation Deep Dive

This document explains the system design, motivations, and implementation details end to end.

## 1. Why This Project Exists

Trading systems fail in practice not only because of strategy logic, but because of weak observability:

1. Missing visibility into real-time behavior.
2. No clear trace from producer event to dashboard output.
3. Slow incident diagnosis when data pipelines degrade.

This project demonstrates a minimal but realistic observability architecture that turns raw event logs into queryable time-series data and live dashboards.

## 2. Design Principles

The implementation follows these principles:

1. **Decoupling**: producer does not write directly to DB.
2. **Structured telemetry**: logs are machine-readable JSON.
3. **Composable pipeline**: ingestion/transformation is config-driven.
4. **Fast storage/query path**: TSDB + SQL interface.
5. **Reproducibility**: infrastructure and dashboards are file-provisioned.

## 3. End-to-End Workflow

```text
Trader (Python)
  -> JSON logs (stdout + file)
  -> shared Docker volume
  -> Telegraf tail input parses JSON
  -> Telegraf emits Influx line protocol
  -> QuestDB ingests on ILP port
  -> table: price_log
  -> Grafana queries via Postgres wire
  -> dashboard panel updates
```

### 3.1 Runtime sequence after startup

1. Docker network + shared volume initialize.
2. QuestDB starts and passes health check.
3. Trader starts generating events every ~0.5s.
4. Telegraf tails the trader log file and forwards records.
5. QuestDB creates/updates `price_log` table.
6. Grafana provisions datasource/dashboard and serves UI.

## 4. Technology Stack and Responsibilities

## 4.1 Docker Compose (`docker-compose.yaml`)

Compose controls service topology and lifecycle.

Responsibilities:

1. Starts all services with one command.
2. Defines service dependencies (`depends_on`, health conditions).
3. Exposes host ports.
4. Defines and mounts shared volume (`logdata`).

Why this matters:

1. Single-command reproducibility.
2. Deterministic local environment.
3. Explicit service contracts and startup order.

## 4.2 Trader Service (`trader/trader.py`)

The trader is a synthetic event producer.

Core behavior:

1. Initializes `price = 100`.
2. Each loop applies multiplicative random return:
   - `price = price * (1 + np.random.randn() * 0.01)`
3. Emits JSON event with fields:
   - `event` (`price_log`)
   - `price` (float)
   - `timestamp` (UTC ISO)
   - `level` (logging field)
4. Sleeps for 0.5 seconds and repeats.

Implementation details:

1. Uses Python logging root logger.
2. Writes to stdout and to file path set by `LOG_FILE_NAME`.
3. Uses `structlog` JSON renderer for stable schema.

Why this shape:

1. Multiplicative updates resemble return dynamics.
2. File+stdout logging helps both ingestion and debugging.
3. Structured logs reduce parser fragility.

## 4.3 Telegraf (`telegraf.conf`)

Telegraf is the ingestion/transform bridge.

Input (`inputs.tail`):

1. Tails trader log file from shared volume.
2. Parses strict JSON.
3. Maps event name via `json_name_key`.
4. Uses event timestamp via `json_time_key` + `json_time_format`.

Output (`outputs.socket_writer`):

1. Converts parsed records to Influx line protocol.
2. Sends to QuestDB ILP endpoint (`questdb:9009`).

Operational value:

1. Producer remains transport-agnostic.
2. Parsing/forwarding logic is config-driven.
3. Easy to extend with extra processors/outputs later.

## 4.4 QuestDB

QuestDB is the time-series sink and query backend.

In this stack:

1. Receives writes on ILP port (`9009`).
2. Stores rows in `price_log`.
3. Provides SQL/Web API on `9000`.
4. Provides PostgreSQL wire protocol on `8812` for Grafana.

Why QuestDB:

1. Efficient append/write workload handling.
2. SQL analytics workflow.
3. Simple local operations for monitoring demos.

## 4.5 Grafana Provisioning

Grafana is fully file-provisioned here.

Files:

1. `grafana/provisioning/datasources/datasources.yaml`
2. `grafana/provisioning/dashboards/dashboards.yaml`
3. `grafana/provisioning/dashboards/dashboard.json`

Responsibilities:

1. Bootstraps datasource automatically.
2. Bootstraps dashboard automatically.
3. Avoids click-ops and keeps dashboard config versioned.

## 5. Data Model and Contract

Event schema emitted by trader:

```json
{
  "event": "price_log",
  "price": 101.234,
  "level": "info",
  "timestamp": "2026-03-15T13:06:23.760660Z"
}
```

Field meanings:

1. `event`: logical metric/table key.
2. `price`: numeric observed value.
3. `level`: metadata from logging pipeline.
4. `timestamp`: event time used for time-series indexing.

Design note:

- Stable schema is critical. If schema drifts, parsing and dashboards break silently or degrade.

## 6. Reliability and Observability Behavior

Healthy indicators:

1. Trader logs continuously.
2. Telegraf shows input/output plugins loaded without parse errors.
3. QuestDB log shows ILP connection and `price_log` writes.
4. Row count in `price_log` increases over time.
5. Grafana dashboard is reachable and live-updating.

Failure boundaries:

1. **Producer failure**: no new events generated.
2. **Ingestion failure**: trader logs exist but DB count stalls.
3. **Storage/query failure**: ingestion may continue but dashboards fail.
4. **Visualization failure**: data exists but chart renders empty.

## 7. Why the File-Tail Pattern Is Useful

This architecture intentionally avoids direct producer-to-database writes.

Benefits:

1. Producers stay simple and focused.
2. Ingestion policy can change independently.
3. Replay/debug via logs is easier.
4. One producer stream can fan out to multiple sinks later.

Trade-offs:

1. File I/O and tailing add one hop.
2. Log rotation and file management become operational concerns.

## 8. Security and Environment Caveats

Current settings optimize developer convenience:

1. Grafana anonymous mode is enabled.
2. Static credentials are used in local config.
3. No TLS in internal communication.

For production-like use:

1. Disable anonymous access and tighten RBAC.
2. Store secrets in a proper secret manager.
3. Restrict exposed ports.
4. Add TLS and network segmentation.

## 9. Scalability Considerations

This is a single-producer demo, but the pattern scales.

Possible scale directions:

1. Add more producers.
2. Add more metrics per event stream.
3. Introduce broker-based transport if needed (Kafka/NATS).
4. Add alerting and SLO dashboards.

Potential bottlenecks to monitor first:

1. Telegraf parse throughput.
2. QuestDB write/read contention.
3. Grafana query frequency and panel cardinality.

## 10. Scope Boundaries

This project focuses on monitoring pipeline engineering.

Out of scope by design:

1. Strategy alpha generation.
2. Execution/risk engine implementation.
3. Compliance reporting and enterprise controls.
4. HA/disaster-recovery topology.

## 11. File-Level Implementation Index

1. `docker-compose.yaml`: topology, wiring, volumes, ports, startup dependencies.
2. `telegraf.conf`: log tail parsing and QuestDB forwarding path.
3. `trader/trader.py`: synthetic event generation and structured logging.
4. `trader/Dockerfile`: deterministic trader runtime image.
5. `grafana/provisioning/**`: datasource/dashboard infrastructure as code.
6. `Makefile`: operational shortcuts for run/verify/observe workflows.

## 12. Practical Review Checklist

When evaluating pipeline health quickly:

1. Is producer generating events?
2. Is Telegraf parsing them cleanly?
3. Is QuestDB count increasing?
4. Is Grafana querying the expected table?
5. Does the chart track latest timestamps?

If all five are true, the end-to-end monitoring path is functioning correctly.
