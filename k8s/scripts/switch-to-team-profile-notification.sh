#!/bin/sh
# One-time switch of an existing cluster from the Python Profile/Notification to the team services,
# the Kubernetes counterpart of scripts/switch-to-team-profile-notification.sh. Run it before
# deploy.sh on a cluster deployed earlier; a new cluster needs nothing.
#
# Non-destructive: the Python databases are renamed to profile_legacy / notification_legacy and
# fresh empty ones are created. On the broker it deletes the Python worker's queue and its fanout
# cra.dead exchange, which the team consumer declares as a topic exchange.
. "$(dirname "$0")/env.sh"

k scale deployment profile notification notification-worker --replicas=0 >/dev/null 2>&1 || true
psql() { k exec -i statefulset/postgres -- psql -v ON_ERROR_STOP=1 -U postgres -At "$@"; }

for service in profile notification; do
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

broker_password=$(k get secret cra-secrets -o jsonpath='{.data.BROKER_PASSWORD}' | base64 -d)
admin() { k exec statefulset/rabbitmq -- rabbitmqadmin --username cra --password "$broker_password" "$@"; }
admin delete queue --name notifications.buddy.v1 >/dev/null 2>&1 && echo "broker: removed the Python queue notifications.buddy.v1" || true
if admin list exchanges 2>/dev/null | grep -E 'cra\.dead.*fanout' >/dev/null; then
  admin delete exchange --name cra.dead >/dev/null && echo "broker: removed the fanout cra.dead exchange (the team consumer redeclares it as topic)"
fi

echo "Done. Build the team images and deploy: k8s/scripts/build-images.sh profile notification && k8s/scripts/deploy.sh"
