#!/bin/sh
set -eu
for service in identity profile scheduling notification discovery reputation; do
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v service="$service" -v password="$POSTGRES_PASSWORD" <<'SQL'
CREATE ROLE :"service" WITH LOGIN PASSWORD :'password';
CREATE DATABASE :"service" OWNER :"service";
SQL
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -v database="${service}_test" -v service="$service" <<'SQL'
CREATE DATABASE :"database" OWNER :"service";
SQL
done
