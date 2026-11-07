#!/bin/sh
# Gateway -> Discovery gRPC behaviour with two Discovery replicas and one gateway pod (one channel).
# For each MODE it (1) measures how ListBuddyRequests calls spread over the Discovery pods, then
# (2) deletes the busiest pod mid-probe and records errors and whether the replacement pod ever
# receives calls, and (3) scales 1 -> 2 mid-probe to see whether the existing channel uses the new
# pod. Calls per pod are counted from each pod's own Rails log ("BuddyRequest Load").
#   clusterip: DISCOVERY_TARGET=discovery:50051, gRPC default pick_first (Compose-equivalent)
#   headless:  DISCOVERY_TARGET=dns:///discovery-headless:50051, DISCOVERY_LB_POLICY=round_robin
# Usage: [MODES="clusterip headless"] k8s/scripts/grpc-check.sh
. "$(dirname "$0")/env.sh"
MODES="${MODES:-clusterip headless}"
RATE="${PROBE_RATE:-10}"
out="$INTEGRATION_DIR/load-tests/results/$(date -u +%Y%m%dT%H%M%SZ)-grpc-check"
mkdir -p "$out"
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
counts() {  # pod=count for every Discovery pod
  for pod in $(k get pods -l app=discovery --field-selector=status.phase=Running -o name); do
    echo "${pod#pod/}=$(k exec "$pod" -c discovery -- grep -c 'BuddyRequest Load' log/development.log 2>/dev/null || echo 0)"
  done | sort
}
delta() {  # before-file after-file -> per-pod calls in between
  python3 - "$1" "$2" <<'PY'
import sys
read = lambda p: dict(l.strip().split('=') for l in open(p) if '=' in l)
before, after = read(sys.argv[1]), read(sys.argv[2])
rows = {pod: int(n) - int(before.get(pod, 0)) for pod, n in after.items()}
total = sum(rows.values()) or 1
for pod, n in rows.items():
    print(f'{pod}: {n} calls ({100 * n / total:.0f}%)' + ('' if pod in before else '  <- replacement pod'))
PY
}
probe() {  # seconds label
  TOOL_ENV="PROBE_PATH=/api/v1/buddy-requests,PROBE_RATE=$RATE,PROBE_DURATION=$1" \
    "$K8S_DIR/scripts/run-tool.sh" python availability_probe.py >"$out/$2-probe.log" 2>&1
  grep PROBE_SUMMARY "$out/$2-probe.log" | sed 's/^PROBE_SUMMARY //' >"$out/$2-probe.json"
}

original_discovery="$(k get deployment discovery -o jsonpath='{.spec.replicas}')"
original_gateway="$(k get deployment gateway -o jsonpath='{.spec.replicas}')"
k scale deployment gateway --replicas=1 >/dev/null
k scale deployment discovery --replicas=2 >/dev/null

for mode in $MODES; do
  case "$mode" in
    clusterip) target=discovery:50051 policy= ;;
    headless) target=dns:///discovery-headless:50051 policy=round_robin ;;
    *) echo "unknown mode $mode" >&2; exit 2 ;;
  esac
  echo "== $mode: DISCOVERY_TARGET=$target DISCOVERY_LB_POLICY=${policy:-<unset>}" | tee -a "$out/summary.txt"
  k patch configmap service-endpoints --type merge -p "{\"data\":{\"DISCOVERY_TARGET\":\"$target\",\"DISCOVERY_LB_POLICY\":\"$policy\"}}" >/dev/null
  k rollout restart deployment/gateway >/dev/null
  k rollout status deployment/gateway --timeout=120s >/dev/null
  k rollout status deployment/discovery --timeout=180s >/dev/null
  sleep 5

  counts >"$out/$mode-a-before.txt"
  probe 30 "$mode-a"
  counts >"$out/$mode-a-after.txt"
  echo "-- distribution, 30 s at $RATE req/s, two ready Discovery pods:" | tee -a "$out/summary.txt"
  delta "$out/$mode-a-before.txt" "$out/$mode-a-after.txt" | tee -a "$out/summary.txt"

  busiest="$(delta "$out/$mode-a-before.txt" "$out/$mode-a-after.txt" | sort -t: -k2 -n -r | head -1 | cut -d: -f1)"
  counts >"$out/$mode-b-before.txt"
  probe 75 "$mode-b" &
  pid=$!
  sleep 20
  echo "$(stamp) delete pod/$busiest" | tee -a "$out/summary.txt"
  k delete pod "$busiest" --wait=false >/dev/null
  sleep 2
  until [ "$(k get deployment discovery -o jsonpath='{.status.readyReplicas}')" = 2 ] && \
        [ "$(k get pods -l app=discovery --no-headers | wc -l | tr -d ' ')" = 2 ]; do sleep 1; done
  echo "$(stamp) replacement ready (2/2)" | tee -a "$out/summary.txt"
  wait "$pid" || true
  counts >"$out/$mode-b-after.txt"
  echo "-- during/after replacement (75 s probe):" | tee -a "$out/summary.txt"
  delta "$out/$mode-b-before.txt" "$out/$mode-b-after.txt" | tee -a "$out/summary.txt"
  python3 -c "import json,sys; s=json.load(open(sys.argv[1])); print(f\"probe: sent={s['sent']} ok={s['ok']} failed={s['failed']} p95={s['p95Ms']}ms max={s['maxMs']}ms failures={[(f['at'], f['status']) for f in s['failures']]}\")" "$out/$mode-b-probe.json" | tee -a "$out/summary.txt"
  grep '^t+' "$out/$mode-b-probe.log" | awk '$5 != "failed=0" || $6 ~ /max=[0-9]{4}/' | tee -a "$out/summary.txt" || true

  # (3) Scale-out with no connection failure: does the existing channel ever use the new pod?
  k scale deployment discovery --replicas=1 >/dev/null
  until [ "$(k get pods -l app=discovery --no-headers | wc -l | tr -d ' ')" = 1 ]; do sleep 1; done
  sleep 5
  counts >"$out/$mode-c-before.txt"
  probe 60 "$mode-c" &
  pid=$!
  sleep 10
  echo "$(stamp) scale discovery 1 -> 2" | tee -a "$out/summary.txt"
  k scale deployment discovery --replicas=2 >/dev/null
  k rollout status deployment/discovery --timeout=180s >/dev/null
  echo "$(stamp) second pod ready" | tee -a "$out/summary.txt"
  wait "$pid" || true
  counts >"$out/$mode-c-after.txt"
  echo "-- scale-out during a 60 s probe:" | tee -a "$out/summary.txt"
  delta "$out/$mode-c-before.txt" "$out/$mode-c-after.txt" | sed 's/replacement pod/added pod/' | tee -a "$out/summary.txt"
  python3 -c "import json,sys; s=json.load(open(sys.argv[1])); print(f\"probe: sent={s['sent']} ok={s['ok']} failed={s['failed']}\")" "$out/$mode-c-probe.json" | tee -a "$out/summary.txt"
done

echo "== restoring manifest configuration" | tee -a "$out/summary.txt"
k apply -f "$K8S_DIR/service-endpoints.yaml" >/dev/null
k scale deployment discovery --replicas="$original_discovery" >/dev/null
k scale deployment gateway --replicas="$original_gateway" >/dev/null
k rollout restart deployment/gateway >/dev/null
k rollout status deployment/gateway --timeout=120s >/dev/null
echo "Saved $out"
