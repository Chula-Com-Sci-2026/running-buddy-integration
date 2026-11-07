#!/bin/sh
# Runs a k6 script as a Job inside the cluster (k6 -> http://gateway:8000, no host port-forward in
# the measurement path) and saves a reproducible result directory:
#   summary.txt      per-operation table and threshold verdicts
#   summary.json     full k6 end-of-test summary
#   k6.log           complete k6 output
#   environment.txt  host, VM, node capacity, replicas, pod limits, image revisions, dataset size
#   pod-usage.txt    `kubectl top pods` samples every 15 s during the run
# Usage: load-tests/run-k6.sh <script.js> [NAME=value ...]
#   e.g. load-tests/run-k6.sh running-buddy.js SCENARIO=ramp TARGET_VUS=500 LABEL=ramp-500
LOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$LOAD_DIR/../k8s/scripts/env.sh"
INTEGRATION_DIR="$(cd "$LOAD_DIR/.." && pwd)"
script="${1:?usage: run-k6.sh <script.js> [NAME=value ...]}"; shift
label="$(echo "${script%.js}" "$@" | tr ' =' '-_' | tr -cd 'A-Za-z0-9_.-' | cut -c1-80)"
for arg in "$@"; do case "$arg" in LABEL=*) label="${arg#LABEL=}" ;; esac; done
out="${RESULT_DIR:-$LOAD_DIR/results/$(date -u +%Y%m%dT%H%M%SZ)-$label}"
mkdir -p "$out"

k create configmap k6-scripts --from-file="$LOAD_DIR/k6/" --dry-run=client -o yaml | k apply -f - >/dev/null
env_yaml=""
for arg in "$@"; do
  env_yaml="$env_yaml
            - {name: \"${arg%%=*}\", value: \"${arg#*=}\"}"
done
job="k6-$(date +%s)"
manifest="$(mktemp)"; trap 'rm -f "$manifest"' EXIT
cat >"$manifest" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $job
  labels: {app.kubernetes.io/component: load-test}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels: {app.kubernetes.io/component: load-test}
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: $K6_IMAGE
          args: ["run", "--quiet", "--no-color", "/scripts/$script"]
          env:
            - {name: BASE_URL, value: "http://gateway:8000"}$env_yaml
          volumeMounts:
            - {name: scripts, mountPath: /scripts}
          # Fixed load-generator budget, identical across runs, so comparisons change only the SUT.
          resources:
            requests: {cpu: "1", memory: 512Mi}
            limits: {cpu: "2", memory: 2Gi}
      volumes:
        - name: scripts
          configMap: {name: k6-scripts}
EOF

environment() {
  echo "# Recorded $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "k6 image: $K6_IMAGE; script: $script; args: $*"
  echo "host: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m), $(sysctl -n hw.ncpu 2>/dev/null) CPUs, $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GiB RAM, $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
  echo "colima VMs (others running at the same time share the host CPU/RAM):"; colima list 2>/dev/null | sed 's/^/  /'
  echo "node:"; kubectl --context "$KUBE_CONTEXT" get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,RUNTIME:.status.nodeInfo.containerRuntimeVersion | sed 's/^/  /'
  echo "deployments (replicas ready/desired) and per-pod limits:"
  k get deployments -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory | sed 's/^/  /'
  echo "gateway gRPC: $(k get configmap service-endpoints -o jsonpath='DISCOVERY_TARGET={.data.DISCOVERY_TARGET} DISCOVERY_LB_POLICY={.data.DISCOVERY_LB_POLICY}')"
  echo "image revisions:"
  for image in $(k get pods -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' | grep '^cra/' | sort -u); do
    echo "  $image $(d image inspect "$image" --format '{{.Id}} rev={{index .Config.Labels "cra.revision"}}' 2>/dev/null)"
  done
  echo "dataset:"
  k exec postgres-0 -- sh -c "psql -U postgres -d profile -tAc \"select 'profiles_total='||count(*)||' profiles_loadtest='||count(*) filter (where bio='k6 load-test fixture') from profiles\";
    psql -U postgres -d identity_team -tAc \"select 'users_total='||count(*)||' users_loadtest='||count(*) filter (where email like '%@loadtest.example.com') from users\";
    psql -U postgres -d scheduling -tAc \"select 'upcoming_runs='||count(*) from runs where starts_at>now()\"" | sed 's/^/  /'
}
environment "$@" >"$out/environment.txt"

( while :; do echo "## $(date -u +%H:%M:%S)"; kubectl --context "$KUBE_CONTEXT" top node --no-headers 2>/dev/null | sed 's/^/NODE /'; kubectl --context "$KUBE_CONTEXT" top pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v -e '^tool-' ; sleep 15; done ) >"$out/pod-usage.txt" &
sampler=$!
stop_sampler() { { kill "$sampler" && wait "$sampler"; } 2>/dev/null || true; }
trap 'rm -f "$manifest"; stop_sampler' EXIT

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
k create -f "$manifest" >/dev/null
echo "==> job/$job $script $* (results: $out)"
until k logs "job/$job" >/dev/null 2>&1; do sleep 2; done
k logs -f "job/$job" >"$out/k6.log" 2>&1 || true
while :; do
  status="$(k get job "$job" -o jsonpath='{.status.succeeded}/{.status.failed}')"
  case "$status" in 1/*|*/1) break ;; esac
  sleep 2
done
k logs "job/$job" >"$out/k6.log" 2>&1
finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stop_sampler

sed '/===K6_SUMMARY_JSON_BEGIN===/,$d' "$out/k6.log" | grep -v '^time=' >"$out/summary.txt" || true
sed -n '/===K6_SUMMARY_JSON_BEGIN===/,/===K6_SUMMARY_JSON_END===/p' "$out/k6.log" | sed '1d;$d' >"$out/summary.json"
exit_code="$(k get pods -l "job-name=$job" -o jsonpath='{.items[0].status.containerStatuses[0].state.terminated.exitCode}')"
{ echo "started=$started finished=$finished k6_exit_code=$exit_code (0 = all thresholds passed, 99 = a threshold failed)"; } >>"$out/summary.txt"
cat "$out/summary.txt"
grep -E 'level=(warning|error)' "$out/k6.log" | sort | uniq -c | sort -rn | head -5 || true
echo "Saved $out"
