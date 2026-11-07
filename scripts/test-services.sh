#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Test-only databases; no production/demo tables are truncated.
for service in identity profile scheduling notification; do
  docker compose run --rm --no-deps -e "DATABASE_URL=postgresql://${service}:$(sed -n 's/^DB_PASSWORD=//p' .env)@postgres:5432/${service}_test" "$service" pytest -q
 done
docker compose run --rm --no-deps -e "DATABASE_URL=postgresql://trust_safety:$(sed -n 's/^DB_PASSWORD=//p' .env)@postgres:5432/trust_safety_test" trust-safety pytest -q
docker compose run --rm --no-deps -e REDIS_URL=redis://redis:6379/15 conditions pytest -q
docker compose run --rm --no-deps gateway pytest -q
for service in discovery reputation; do
  docker compose run --rm --no-deps -e RAILS_ENV=test "$service" sh -c 'bin/rails db:migrate && bin/rails test'
  docker compose run --rm --no-deps "$service" bin/rubocop
 done
