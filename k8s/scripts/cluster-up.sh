#!/bin/sh
# Creates (or resumes) a dedicated Colima VM with k3s. The default Colima profile, which runs the
# Compose stack and holds its volumes, is never started, stopped or modified by this script.
. "$(dirname "$0")/env.sh"
CPUS="${CPUS:-6}"
MEMORY_GIB="${MEMORY_GIB:-6}"
previous_docker_context="$(docker context show)"
colima start --profile "$COLIMA_PROFILE" --vm-type vz --cpu "$CPUS" --memory "$MEMORY_GIB" --disk 60 --kubernetes
# colima switches the global Docker context to the new profile; restore the previous one.
docker context use "$previous_docker_context" >/dev/null
kubectl --context "$KUBE_CONTEXT" wait --for=condition=Ready node --all --timeout=180s
kubectl --context "$KUBE_CONTEXT" get nodes -o wide
