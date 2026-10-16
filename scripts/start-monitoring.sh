#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Demo services must already have initialized their tables. This starts no application services.
docker compose up -d --wait postgres
python3 scripts/prepare-monitoring.py
docker compose -f compose.yaml -f compose.monitoring.yaml --profile monitoring up -d pgweb
echo 'PostgreSQL viewer: http://localhost:8081 (choose a service bookmark, schema demo_monitor)'
echo 'RabbitMQ dashboard, when the demo broker is running: http://localhost:15678'
