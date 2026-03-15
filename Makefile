SHELL := /bin/bash

.PHONY: up down restart ps logs trader-logs telegraf-logs questdb-logs grafana-logs count watch endpoints

up:
	docker compose up --build -d

down:
	docker compose down

restart: down up

ps:
	docker compose ps

logs:
	docker compose logs -f trader telegraf questdb grafana

trader-logs:
	docker compose logs -f trader

telegraf-logs:
	docker compose logs -f telegraf

questdb-logs:
	docker compose logs -f questdb

grafana-logs:
	docker compose logs -f grafana

count:
	curl -s "http://localhost:9000/exec?query=select%20count()%20from%20price_log"

watch:
	@echo "Live monitor. Press Ctrl+C to stop."
	@while true; do \
		clear; \
		echo "=== Docker Services ==="; \
		docker compose ps; \
		echo; \
		echo "=== QuestDB Row Count (price_log) ==="; \
		curl -s "http://localhost:9000/exec?query=select%20count()%20from%20price_log" || true; \
		echo; \
		echo; \
		echo "=== Endpoints ==="; \
		echo "Grafana: http://localhost:3000"; \
		echo "QuestDB: http://localhost:9000"; \
		sleep 2; \
	done

endpoints:
	@echo "Grafana: http://localhost:3000"
	@echo "QuestDB: http://localhost:9000"
