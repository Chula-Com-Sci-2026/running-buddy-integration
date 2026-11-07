#!/bin/sh
# Ordered, repeatable deployment. Kubernetes does not honour Compose depends_on, so the order is
# explicit: data stores ready -> roles/databases -> migrations (once) -> applications.
# Re-running is safe: every step is idempotent and no volume or PVC is deleted.
. "$(dirname "$0")/env.sh"

echo "==> Secrets"
"$K8S_DIR/scripts/create-secrets.sh"

echo "==> Data stores"
kubectl --context "$KUBE_CONTEXT" apply -f "$K8S_DIR/namespace.yaml"
k apply -f "$K8S_DIR/service-endpoints.yaml" -f "$K8S_DIR/infra/"
for store in postgres redis rabbitmq; do
  k rollout status "statefulset/$store" --timeout=300s
done

echo "==> Roles and databases"
k delete job db-bootstrap --ignore-not-found
k apply -f "$K8S_DIR/jobs/db-bootstrap.yaml"
k wait --for=condition=complete job/db-bootstrap --timeout=180s
k logs job/db-bootstrap

echo "==> Migrations (one Job per service, before any application pod starts)"
k delete job -l app.kubernetes.io/component=migration --ignore-not-found
k apply -f "$K8S_DIR/jobs/migrations.yaml"
k wait --for=condition=complete job -l app.kubernetes.io/component=migration --timeout=300s

echo "==> Applications"
kubectl --context "$KUBE_CONTEXT" apply -k "$K8S_DIR"
for deployment in identity identity-worker profile conditions scheduling notification \
                  notification-worker discovery discovery-outbox reputation gateway; do
  k rollout status "deployment/$deployment" --timeout=300s
done
k get pods -o wide
