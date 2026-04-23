# Systematic Trade Monitor

A local, containerized monitoring stack for a simulated trading process.

This README is the operations-focused guide (run, verify, debug). For architecture, motivations, and implementation deep dive, see:

- [`docs/architecture.md`](docs/architecture.md)

## 1. What You Get

This project runs four connected services:

1. `trader` (Python): emits structured JSON price events continuously.
2. `telegraf`: tails trader logs and forwards parsed metrics.
3. `questdb`: stores time-series data (`price_log`).
4. `grafana`: visualizes data with a provisioned dashboard.

## 2. Quick Start

From the repo root:

```bash
docker compose up --build -d
```

Check status:

```bash
docker compose ps
```

Stop:

```bash
docker compose down
```

## 3. Endpoints

1. Grafana UI: `http://localhost:3000`
2. QuestDB Web/SQL API: `http://localhost:9000`
3. QuestDB ILP ingest port: `localhost:9009`
4. QuestDB PostgreSQL wire port: `localhost:8812`

## 4. Verify It Is Working

## 4.1 Verify services are up

```bash
docker compose ps
```

Expected:

1. All services are `Up`.
2. `questdb` is `healthy`.

## 4.2 Verify producer activity

```bash
docker compose logs --tail=50 trader
```

Expected:

1. JSON log lines with `event: "price_log"`.
2. Continuously changing `price` values.

## 4.3 Verify ingestion into QuestDB

```bash
curl -s "http://localhost:9000/exec?query=select%20count()%20from%20price_log"
```

Run twice a few seconds apart. Expected: count increases.

## 4.4 Verify dashboard availability

1. Open `http://localhost:3000`.
2. Confirm dashboard `Trader log dashboard` is visible.
3. Confirm chart updates over time.

## 5. Makefile Commands

Use the built-in shortcuts:

```bash
make up          # start stack
make ps          # service status
make logs        # follow all service logs
make trader-logs # trader logs only
make telegraf-logs
make questdb-logs
make grafana-logs
make count       # QuestDB row count in price_log
make watch       # live terminal monitor
make endpoints   # print endpoint URLs
make down        # stop stack
```

## 6. Typical Operator Workflow

1. `make up`
2. `make ps`
3. `make count`
4. `make logs` (or service-specific logs)
5. Open Grafana and QuestDB UIs
6. `make down` when done

## 7. Troubleshooting

## 7.1 Docker daemon not available

Symptom:

- Errors about `docker.sock` not found or connection denied.

Fix:

1. Start Docker Desktop / Docker Engine.
2. Retry `make up`.

## 7.2 Trader logs exist, but no rows in QuestDB

Checks:

1. `docker compose logs telegraf`
2. Confirm `LOG_FILE_NAME` and volume mount are correct.
3. Confirm Telegraf output points to `questdb:9009`.

## 7.3 QuestDB has rows, Grafana panel empty

Checks:

1. Confirm datasource is provisioned.
2. Confirm dashboard query references `price_log`.
3. Expand Grafana time range to recent 15m.

## 7.4 Slow startup on Apple Silicon

Some image tags may run via emulation depending on available manifests; first startup may be slower due to image pull and extraction.

## 8. Production-Readiness Notes

Current setup is intentionally local/dev-friendly:

1. Grafana anonymous access is enabled.
2. Static local credentials are used.
3. Internal traffic is unencrypted.

For production-like deployment, harden auth, secret management, network policy, and TLS.

## 9. Documentation Map

1. `README.md` (this file): runbook and operations.
2. `docs/architecture.md`: motivation, architecture, and implementation details.
