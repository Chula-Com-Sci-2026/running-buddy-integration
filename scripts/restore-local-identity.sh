#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
docker compose -f compose.yaml -f compose.team-identity.yaml stop team-identity-worker
# Rebuild explicitly: keep the Python fallback independent of any previously tagged image.
docker compose -f compose.yaml up -d --build --wait --force-recreate identity gateway
