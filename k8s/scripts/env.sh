# Shared settings for the Kubernetes scripts. Sourced, not executed.
# Every command names its context explicitly so the Compose Docker context and any other
# kubectl context are never switched or touched.
set -eu
K8S_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INTEGRATION_DIR="$(cd "$K8S_DIR/.." && pwd)"
WORKSPACE_DIR="$(cd "$INTEGRATION_DIR/.." && pwd)"
COLIMA_PROFILE="${COLIMA_PROFILE:-cra-k8s}"
KUBE_CONTEXT="${KUBE_CONTEXT:-colima-$COLIMA_PROFILE}"
DOCKER_CONTEXT="${DOCKER_CONTEXT:-colima-$COLIMA_PROFILE}"
NAMESPACE="${NAMESPACE:-cra}"
K6_IMAGE="${K6_IMAGE:-grafana/k6:2.3.0}"

k() { kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" "$@"; }
d() { docker --context "$DOCKER_CONTEXT" "$@"; }
