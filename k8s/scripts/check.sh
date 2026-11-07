#!/bin/sh
# Runs the existing end-to-end checks against the Kubernetes deployment, unchanged:
# check_flows.py (gateway, gRPC, RabbitMQ, live weather + Redis, scheduling, reputation) and
# check_broker.py (duplicate delivery + dead-letter). Requires seed-demo.sh first.
. "$(dirname "$0")/env.sh"
"$K8S_DIR/scripts/run-tool.sh" python check_flows.py
"$K8S_DIR/scripts/run-tool.sh" python check_broker.py
