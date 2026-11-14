#!/bin/sh
# Live terminal feed for the load-test demo, run beside demo-live.sh: every request the gateway answers
# (method, path, status, colour by status), Profile and gateway pods coming and going, and node CPU every
# 10 s. Ctrl-C stops it.
set -eu

CONTEXT="${CONTEXT:-colima-cra-k8s}"
NAMESPACE="${NAMESPACE:-cra}"
command -v kubectl >/dev/null || { echo 'kubectl is not on PATH; the feed cannot start.' >&2; exit 1; }
k() { kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }
stamp() { while IFS= read -r line; do printf '%s %s\n' "$(date +%H:%M:%S)" "$line"; done; }

trap 'kill 0 2>/dev/null' EXIT INT TERM

printf '\033[1m== Live gateway requests, pods and node CPU (Ctrl-C to stop) ==\033[0m\n'

# Uvicorn access lines look like: [pod/gateway-abc/gateway] INFO: 10.42.0.9:5123 - "GET /api/v1/runners?x=1 HTTP/1.1" 200 OK
k logs -f -l app=gateway --prefix --tail=0 --max-log-requests=10 2>/dev/null |
  grep --line-buffered '" [0-9][0-9][0-9]' | grep --line-buffered -v -e ' /up ' -e ' /ready ' |
  awk '{
    pod=$1; sub(/^\[pod\//,"",pod); sub(/\/.*/,"",pod)
    match($0,/"[A-Z]+ [^ ]+ HTTP/); req=substr($0,RSTART+1,RLENGTH-6); sub(/\?.*/,"",req)
    match($0,/" [0-9][0-9][0-9]/); status=substr($0,RSTART+2,3)
    colour=status<400?"\033[32m":status<500?"\033[33m":"\033[31m"
    printf "%s%s\033[0m  %-40s  %s\n", colour, status, req, pod; fflush()
  }' | stamp &

k get pods -l 'app in (profile,gateway)' -w --no-headers 2>/dev/null |
  awk '{ printf "\033[36m[pods]\033[0m %-40s %-8s %s\n", $1, $2, $3; fflush() }' | stamp &

while :; do
  k top node --no-headers 2>/dev/null | awk '{ printf "\033[35m[node]\033[0m CPU %s (%s)  memory %s\n", $2, $3, $4 }' | stamp
  sleep 10
done
