#!/bin/sh
# Run a local k6 script with a live dashboard and a saved HTML report.
set -eu

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <script.js> [k6 run options...]" >&2
  exit 2
fi
if ! command -v k6 >/dev/null 2>&1; then
  echo 'k6 is required on the host. Install it before running this script.' >&2
  exit 127
fi
if [ ! -f "$1" ]; then
  echo "Test script not found: $1" >&2
  exit 2
fi

LOAD_TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DASHBOARD_RESULTS_DIR="$(mktemp -d "$LOAD_TEST_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)-dashboard-XXXXXX")"
export K6_WEB_DASHBOARD=true
export K6_WEB_DASHBOARD_OPEN="${K6_WEB_DASHBOARD_OPEN:-true}"
export K6_WEB_DASHBOARD_HOST="${K6_WEB_DASHBOARD_HOST:-127.0.0.1}"
export K6_WEB_DASHBOARD_PORT="${K6_WEB_DASHBOARD_PORT:-5665}"
# k6 defaults to one point every 10 s, so a 2-minute demo moves in 12 steps; 2 s looks live.
export K6_WEB_DASHBOARD_PERIOD="${K6_WEB_DASHBOARD_PERIOD:-2s}"
export K6_WEB_DASHBOARD_EXPORT="$DASHBOARD_RESULTS_DIR/report.html"

printf 'Live dashboard: http://%s:%s\n' "$K6_WEB_DASHBOARD_HOST" "$K6_WEB_DASHBOARD_PORT"
printf 'HTML report: %s\n' "$K6_WEB_DASHBOARD_EXPORT"
exec k6 run "$@"
