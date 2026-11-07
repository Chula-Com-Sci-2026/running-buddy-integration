#!/bin/sh
# Runs one operator command from the cra/tools image (scripts/ at /checks) as a Kubernetes Job,
# streams its logs and exits with its status. Equivalent to `docker compose run --rm tools ...`.
# Service names match Compose, so the existing checks resolve gateway, postgres, redis, ... via
# cluster DNS without modification.
# Usage: run-tool.sh python check_flows.py
. "$(dirname "$0")/env.sh"
IMAGE="${TOOL_IMAGE:-cra/tools:local}"
[ "$#" -gt 0 ] || { echo "usage: $0 command [args...]" >&2; exit 2; }
command_json="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
# Optional TOOL_ENV="NAME=value,NAME=value" passes script parameters as extra env entries.
extra_env="$(python3 -c '
import json,sys
pairs=[item.split("=",1) for item in sys.argv[1].split(",") if item]
print("".join("            - "+json.dumps({"name":k,"value":v})+"\n" for k,v in pairs))
' "${TOOL_ENV:-}")"

manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT
cat >"$manifest" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  generateName: tool-
  labels: {app.kubernetes.io/component: tool}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: tool
          image: $IMAGE
          imagePullPolicy: Never
          command: $command_json
          envFrom:
            - configMapRef: {name: service-endpoints}
          env:
            - name: DB_PASSWORD
              valueFrom: {secretKeyRef: {name: cra-secrets, key: DB_PASSWORD}}
            - name: JWT_SECRET
              valueFrom: {secretKeyRef: {name: cra-secrets, key: JWT_SECRET}}
            - name: BROKER_PASSWORD
              valueFrom: {secretKeyRef: {name: cra-secrets, key: BROKER_PASSWORD}}
            - {name: AMQP_URL, value: "amqp://cra:\$(BROKER_PASSWORD)@rabbitmq:5672/%2F"}
            # Direct gRPC target for checks; the gateway's own target comes from the ConfigMap.
            - {name: DISCOVERY_TARGET, value: "discovery:50051"}
            - {name: IDENTITY_BACKEND, value: team}
$extra_env
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits: {cpu: "1", memory: 512Mi}
EOF
job="$(k create -o name -f "$manifest")"
echo "==> $job: $*" >&2
pod=""
until [ -n "$pod" ]; do
  pod="$(k get pods -l "job-name=${job#job.batch/}" -o name 2>/dev/null | head -1)"
  [ -n "$pod" ] || sleep 1
done
k wait --for=condition=Ready "$pod" --timeout=120s >/dev/null 2>&1 || true
k logs -f "$pod" || true
while :; do
  succeeded="$(k get "$job" -o jsonpath='{.status.succeeded}')"
  failed="$(k get "$job" -o jsonpath='{.status.failed}')"
  [ "${succeeded:-0}" -ge 1 ] && exit 0
  [ "${failed:-0}" -ge 1 ] && { echo "==> $job failed" >&2; exit 1; }
  sleep 1
done
