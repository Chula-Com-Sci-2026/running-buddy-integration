#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/init-env.py
test -d ../team-identity-service/.git || { echo 'Clone the team Identity PR branch into ../team-identity-service first.'; exit 1; }
docker compose up -d --wait postgres rabbitmq
# Only the local PostgreSQL operator creates databases. Application-role privileges stay unchanged.
docker compose exec -T postgres sh -c 'for database in identity_team identity_team_test; do psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '\''${database}'\''" | grep -q 1 || createdb -U postgres -O identity "$database"; done'
docker compose -f compose.yaml -f compose.team-identity.yaml up -d --build --wait
docker compose -f compose.yaml -f compose.team-identity.yaml exec -T identity node scripts/seed-demo.js
docker compose -f compose.yaml -f compose.team-identity.yaml run --rm --no-deps tools python seed.py
