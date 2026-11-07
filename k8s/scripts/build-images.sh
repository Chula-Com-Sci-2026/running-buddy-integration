#!/bin/sh
# Builds every image into the k3s VM's Docker daemon. k3s uses that daemon as its container
# runtime, so no registry push or image import is needed (manifests use imagePullPolicy: Never).
# Usage: build-images.sh [name ...]   e.g. build-images.sh gateway tools
. "$(dirname "$0")/env.sh"
cd "$WORKSPACE_DIR"

build() {
  name="$1" context="$2" dockerfile="$3"
  revision="$(git -C "$context" rev-parse --short HEAD 2>/dev/null || echo none)"
  git -C "$context" diff --quiet HEAD 2>/dev/null || revision="$revision-dirty"
  echo "==> cra/$name:local from $context ($revision)"
  d build -t "cra/$name:local" -f "$context/$dockerfile" --label "cra.revision=$revision" "$context"
}

all="identity profile conditions scheduling notification gateway discovery reputation tools"
for name in ${*:-$all}; do
  case "$name" in
    # Team Identity (PR branch adopted for Deliverable 4); see k8s/README.md "Identity choice".
    identity) build identity team-identity-service Dockerfile ;;
    profile) build profile profile-service Dockerfile ;;
    conditions) build conditions run-conditions-service Dockerfile ;;
    scheduling) build scheduling run-scheduling-service Dockerfile ;;
    notification) build notification notification-service Dockerfile ;;
    gateway) build gateway api-gateway Dockerfile ;;
    # Same development images Compose uses; the production Dockerfiles need Rails master keys
    # and extra cache/queue databases that this stack does not provision.
    discovery) build discovery buddy-discovery-service Dockerfile.dev ;;
    reputation) build reputation reputation-service Dockerfile.dev ;;
    tools) build tools running-buddy-integration k8s/tools/Dockerfile ;;
    *) echo "Unknown image: $name" >&2; exit 1 ;;
  esac
done
d images --filter reference='cra/*' --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}'
