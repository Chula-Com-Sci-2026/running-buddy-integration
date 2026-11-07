#!/bin/sh
# Stable addressing during pod replacement. Runs TARGET at REPLICAS (default: profile x2), sends
# a fixed-rate probe through the gateway (gateway -> http://profile:8000 by DNS), deletes one pod,
# waits for its replacement to become Ready, then deletes the other. Records the per-second probe
# timeline, pod events, EndpointSlice addresses and DNS answers before/after.
# Usage: [TARGET=profile] [REPLICAS=2] [PROBE_RATE=20] k8s/scripts/replacement-demo.sh
. "$(dirname "$0")/env.sh"
TARGET="${TARGET:-profile}"
REPLICAS="${REPLICAS:-2}"
PROBE_RATE="${PROBE_RATE:-20}"
PROBE_DURATION="${PROBE_DURATION:-100}"
case "$TARGET" in
  scheduling) PROBE_PATH="${PROBE_PATH:-/api/v1/runs}" ;;
  discovery) PROBE_PATH="${PROBE_PATH:-/api/v1/buddy-requests}" ;;
  *) PROBE_PATH="${PROBE_PATH:-/api/v1/me/profile}" ;;
esac
out="$INTEGRATION_DIR/load-tests/results/$(date -u +%Y%m%dT%H%M%SZ)-replacement-$TARGET"
mkdir -p "$out"
stamp() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }
log() { echo "$(stamp) $*" | tee -a "$out/timeline.log"; }
ready_count() { k get deployment "$TARGET" -o jsonpath='{.status.readyReplicas}'; }
snapshot() {
  k get endpointslices -l "kubernetes.io/service-name=$TARGET" \
    -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} pod={.targetRef.name}{"\n"}{end}' >"$out/endpoints-$1.txt"
  # Address callers use: the Service name resolves to the same ClusterIP whatever the pods are.
  k exec deploy/gateway -- python -c "import socket; print('$TARGET ->', socket.gethostbyname('$TARGET'), '| $TARGET.$NAMESPACE.svc.cluster.local ->', socket.gethostbyname('$TARGET.$NAMESPACE.svc.cluster.local'))" >"$out/dns-$1.txt"
  k get pods -l "app=$TARGET" -o wide >"$out/pods-$1.txt"
}

original="$(k get deployment "$TARGET" -o jsonpath='{.spec.replicas}')"
log "scale $TARGET to $REPLICAS (was $original)"
k scale deployment "$TARGET" --replicas="$REPLICAS" >/dev/null
k rollout status "deployment/$TARGET" --timeout=180s >/dev/null
snapshot before
cat "$out/dns-before.txt" "$out/endpoints-before.txt"

k get pods -l "app=$TARGET" --watch-only --output-watch-events \
  -o custom-columns=EVENT:.type,POD:.object.metadata.name,PHASE:.object.status.phase,READY:.object.status.containerStatuses[0].ready,DELETING:.object.metadata.deletionTimestamp \
  2>/dev/null | while read -r line; do echo "$(stamp) $line"; done >"$out/pod-events.log" &
watcher=$!

log "probe start: $PROBE_RATE req/s to gateway $PROBE_PATH for ${PROBE_DURATION}s"
TOOL_ENV="PROBE_PATH=$PROBE_PATH,PROBE_RATE=$PROBE_RATE,PROBE_DURATION=$PROBE_DURATION" \
  "$K8S_DIR/scripts/run-tool.sh" python availability_probe.py >"$out/probe.log" 2>&1 &
probe=$!
sleep 15

for round in 1 2; do
  # Delete the oldest pod each round, so the second round removes the remaining original pod.
  victim="$(k get pods -l "app=$TARGET" --sort-by=.metadata.creationTimestamp -o name | head -1)"
  log "round $round: delete $victim"
  k delete "$victim" --wait=false >/dev/null
  sleep 2
  until [ "$(ready_count)" = "$REPLICAS" ] && [ "$(k get pods -l "app=$TARGET" --no-headers | wc -l | tr -d ' ')" = "$REPLICAS" ]; do sleep 1; done
  log "round $round: $REPLICAS/$REPLICAS ready again"
  sleep 10
done

wait "$probe" || true
# Stop the kubectl watch itself; its pipeline subshell would otherwise wait for it forever.
pkill -f "app=$TARGET --watch-only" 2>/dev/null || true
{ kill "$watcher"; wait "$watcher"; } 2>/dev/null || true
snapshot after
log "probe finished"
if [ "$original" != "$REPLICAS" ] && [ "${KEEP_REPLICAS:-0}" != 1 ]; then
  k scale deployment "$TARGET" --replicas="$original" >/dev/null
  log "restored $TARGET to $original replica(s)"
fi

grep '^t+' "$out/probe.log" || true
grep PROBE_SUMMARY "$out/probe.log" | sed 's/^PROBE_SUMMARY //' >"$out/probe-summary.json"
python3 - "$out" <<'PY'
import json, sys, pathlib
out = pathlib.Path(sys.argv[1])
s = json.loads((out / 'probe-summary.json').read_text())
before = (out / 'dns-before.txt').read_text().strip(); after = (out / 'dns-after.txt').read_text().strip()
text = f"""# Pod replacement result

- Probe: {s['rate']} req/s for {s['durationSeconds']} s to `{s['target']}`
- Sent {s['sent']}, succeeded {s['ok']}, failed {s['failed']} (success rate {s['successRate']})
- Latency p50 {s['p50Ms']} ms, p95 {s['p95Ms']} ms, max {s['maxMs']} ms
- DNS before: `{before}`
- DNS after:  `{after}`
- Endpoints before: {', '.join(l.split()[0] for l in (out/'endpoints-before.txt').read_text().split(chr(10)) if l)}
- Endpoints after:  {', '.join(l.split()[0] for l in (out/'endpoints-after.txt').read_text().split(chr(10)) if l)}
- Failures: {json.dumps(s['failures']) if s['failures'] else 'none'}

See timeline.log, pod-events.log and probe.log for the per-second record.
"""
(out / 'summary.md').write_text(text)
print(text)
PY
echo "Saved $out"
