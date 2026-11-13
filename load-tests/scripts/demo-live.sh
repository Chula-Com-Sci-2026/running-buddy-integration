#!/bin/sh
# Two-minute live load test for the demo: k6 dashboard against the local k3s gateway, and one Profile
# pod deletion halfway through to show traffic keeps flowing while Kubernetes replaces it.
set -eu

CONTEXT="${CONTEXT:-colima-cra-k8s}"
NAMESPACE="${NAMESPACE:-cra}"
BASE_URL="${BASE_URL:-http://localhost:30090}"
TARGET_VUS="${TARGET_VUS:-100}"
KILL_AFTER_SECONDS="${KILL_AFTER_SECONDS:-60}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if ! curl -fsS --max-time 5 "$BASE_URL/up" >/dev/null 2>&1; then
  echo "Gateway is not answering at $BASE_URL. Run k8s/scripts/check.sh first." >&2
  exit 1
fi

(
  sleep "$KILL_AFTER_SECONDS"
  echo "--- deleting the Profile pod(s) now ---"
  kubectl --context "$CONTEXT" -n "$NAMESPACE" delete pod -l app=profile --wait=false
) &
KILLER=$!
trap 'kill "$KILLER" 2>/dev/null || true' EXIT INT TERM

BASE_URL="$BASE_URL" SCENARIO=ramp TARGET_VUS="$TARGET_VUS" RAMP_STAGES="30s:1,90s:1,10s:0" \
  "$SCRIPT_DIR/run-dashboard.sh" "$SCRIPT_DIR/../k6/running-buddy.js"
