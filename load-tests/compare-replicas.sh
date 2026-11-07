#!/bin/sh
# Same workload, same per-pod resources and same cluster, run once per replica count.
# Only the replica count of DEPLOYMENTS changes between runs. The gateway is restarted before each
# run so its gRPC channel resolves the current Discovery pods (see k8s/README.md, gRPC section).
# Usage: load-tests/compare-replicas.sh [script.js] [NAME=value ...]
#   default: running-buddy.js SCENARIO=ramp TARGET_VUS=500
#   env: DEPLOYMENTS="gateway profile scheduling conditions discovery" REPLICA_COUNTS="1 2" SETTLE=30
LOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$LOAD_DIR/../k8s/scripts/env.sh"
DEPLOYMENTS="${DEPLOYMENTS:-gateway profile scheduling conditions discovery}"
REPLICA_COUNTS="${REPLICA_COUNTS:-1 2}"
SETTLE="${SETTLE:-30}"
script="${1:-running-buddy.js}"; [ "$#" -gt 0 ] && shift
[ "$#" -gt 0 ] || set -- SCENARIO=ramp TARGET_VUS=500
parent="$LOAD_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)-replica-comparison"
mkdir -p "$parent"

originals=""
for deployment in $DEPLOYMENTS; do
  originals="$originals $deployment=$(k get deployment "$deployment" -o jsonpath='{.spec.replicas}')"
done
restore() {
  for pair in $originals; do k scale deployment "${pair%%=*}" --replicas="${pair#*=}" >/dev/null; done
  k rollout restart deployment/gateway >/dev/null
}
trap restore EXIT

dirs=""
for count in $REPLICA_COUNTS; do
  echo "==> $count replica(s) of: $DEPLOYMENTS"
  for deployment in $DEPLOYMENTS; do k scale deployment "$deployment" --replicas="$count" >/dev/null; done
  for deployment in $DEPLOYMENTS; do k rollout status "deployment/$deployment" --timeout=300s >/dev/null; done
  k rollout restart deployment/gateway >/dev/null
  k rollout status deployment/gateway --timeout=300s >/dev/null
  sleep "$SETTLE"
  RESULT_DIR="$parent/replicas-$count" "$LOAD_DIR/run-k6.sh" "$script" "$@" "LABEL=replicas-$count"
  dirs="$dirs $parent/replicas-$count"
done

# shellcheck disable=SC2086
python3 "$LOAD_DIR/compare.py" $dirs | tee "$parent/comparison.md"
echo "Saved $parent"
