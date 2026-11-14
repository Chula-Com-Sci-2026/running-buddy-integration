#!/bin/sh
# Two-minute live load test for the demo: k6 dashboard against the local k3s gateway, and one Profile
# pod deletion halfway through to show traffic keeps flowing while Kubernetes replaces it.
# On iTerm or Terminal it also opens demo-watch.sh (live gateway requests, pods, node CPU) in a new window;
# WATCH=false skips that.
set -eu

CONTEXT="${CONTEXT:-colima-cra-k8s}"
NAMESPACE="${NAMESPACE:-cra}"
BASE_URL="${BASE_URL:-http://localhost:30090}"
TARGET_VUS="${TARGET_VUS:-100}"
KILL_AFTER_SECONDS="${KILL_AFTER_SECONDS:-60}"
WATCH="${WATCH:-true}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
k() { kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }

if ! curl -fsS --max-time 5 "$BASE_URL/up" >/dev/null 2>&1; then
  echo "Gateway is not answering at $BASE_URL. Run k8s/scripts/check.sh first." >&2
  exit 1
fi

printf '\033[1m== Before the test: services and replicas ==\033[0m\n'
k get deployments gateway profile scheduling conditions discovery identity
printf '\n\033[1m== Plan ==\033[0m\n'
printf '  0:00  ramp up to %s users over 30 s\n' "$TARGET_VUS"
printf '  0:30  hold %s users for 90 s\n' "$TARGET_VUS"
printf '  %d:%02d  delete the Profile pod(s); traffic should keep flowing\n' $((KILL_AFTER_SECONDS / 60)) $((KILL_AFTER_SECONDS % 60))
printf '  2:00  ramp down, then the k6 summary prints below\n\n'

if [ "$WATCH" = true ]; then
  # The new window starts without this shell's PATH, so kubectl from Homebrew would be missing there.
  watch_cmd="cd '$(pwd)' && PATH='$PATH' CONTEXT='$CONTEXT' NAMESPACE='$NAMESPACE' '$SCRIPT_DIR/demo-watch.sh'"
  case "${TERM_PROGRAM:-}" in
    iTerm.app) osascript -e "tell application \"iTerm\" to create window with default profile command \"sh -c \\\"$watch_cmd\\\"\"" >/dev/null ;;
    Apple_Terminal) osascript -e "tell application \"Terminal\" to do script \"$watch_cmd\"" >/dev/null ;;
    *) echo "Open the live feed in another terminal: $SCRIPT_DIR/demo-watch.sh" ;;
  esac
fi

(
  sleep "$KILL_AFTER_SECONDS"
  printf '\n\033[1;31m--- %s deleting the Profile pod(s) now ---\033[0m\n' "$(date +%H:%M:%S)"
  k delete pod -l app=profile --wait=false
) &
KILLER=$!
trap 'kill "$KILLER" 2>/dev/null || true' EXIT INT TERM

BASE_URL="$BASE_URL" SCENARIO=ramp TARGET_VUS="$TARGET_VUS" RAMP_STAGES="30s:1,90s:1,10s:0" \
  "$SCRIPT_DIR/run-dashboard.sh" "$SCRIPT_DIR/../k6/running-buddy.js"
