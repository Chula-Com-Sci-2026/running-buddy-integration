#!/bin/sh
# One-time switch of an existing stack from the Python Profile/Notification to the team services.
# A volume created after the switch needs nothing.
#
# Non-destructive: the Python databases are renamed to profile_legacy / notification_legacy (their
# rows stay there), and fresh empty profile / notification databases are created for the team
# migrations. On the broker it deletes the Python worker's queue and its cra.dead exchange, which
# the team consumer declares with a different type.
set -eu
cd "$(dirname "$0")/.."
. ./.env

docker compose stop profile notification notification-worker >/dev/null 2>&1 || true
docker compose up -d --wait postgres rabbitmq

psql() { docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U postgres -At "$@"; }

for service in profile notification; do
  # The Python schema is recognised by its schema_migrations table; the team services use their own.
  python_schema=$(psql -d "$service" -c "SELECT to_regclass('public.schema_migrations') IS NOT NULL" 2>/dev/null || echo f)
  if [ "$python_schema" = t ]; then
    if [ "$(psql -d postgres -c "SELECT count(*) FROM pg_database WHERE datname='${service}_legacy'")" != 0 ]; then
      echo "${service}_legacy already exists; resolve it by hand before switching" >&2
      exit 1
    fi
    psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$service'" >/dev/null
    psql -d postgres -c "ALTER DATABASE \"$service\" RENAME TO \"${service}_legacy\""
    psql -d postgres -c "CREATE DATABASE \"$service\" OWNER \"$service\""
    echo "$service: Python database kept as ${service}_legacy; created an empty $service database"
  else
    echo "$service: already on the team schema or empty; unchanged"
  fi
done

admin() { docker compose exec -T rabbitmq rabbitmqadmin --username cra --password "$BROKER_PASSWORD" "$@"; }
admin delete queue --name notifications.buddy.v1 >/dev/null 2>&1 && echo "broker: removed the Python queue notifications.buddy.v1" || true
if admin list exchanges 2>/dev/null | grep -E 'cra\.dead.*fanout' >/dev/null; then
  admin delete exchange --name cra.dead >/dev/null && echo "broker: removed the fanout cra.dead exchange (the team consumer redeclares it as topic)"
fi

echo "Done. Start the stack with: docker compose up -d --build"
