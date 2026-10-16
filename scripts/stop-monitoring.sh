#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
docker compose -f compose.yaml -f compose.monitoring.yaml --profile monitoring stop pgweb
