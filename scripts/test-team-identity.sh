#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
docker compose -f compose.yaml -f compose.team-identity.yaml run --rm --no-deps identity npm test
docker compose -f compose.yaml -f compose.team-identity.yaml run --rm --no-deps tools python check_flows.py
docker compose -f compose.yaml -f compose.team-identity.yaml run --rm --no-deps tools python check_broker.py
