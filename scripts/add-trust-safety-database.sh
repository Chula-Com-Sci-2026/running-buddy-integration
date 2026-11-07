#!/bin/sh
# init-databases.sh only runs on a new volume. Run this once on an existing one; it is safe to repeat.
set -eu
cd "$(dirname "$0")/.."
docker compose exec -T postgres sh -eu <<'CONTAINER'
psql -v ON_ERROR_STOP=1 -U postgres -d postgres -v password="$POSTGRES_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE trust_safety WITH LOGIN PASSWORD %L', :'password')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='trust_safety')\gexec
SELECT 'CREATE DATABASE trust_safety OWNER trust_safety'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='trust_safety')\gexec
SELECT 'CREATE DATABASE trust_safety_test OWNER trust_safety'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='trust_safety_test')\gexec
SQL
CONTAINER
