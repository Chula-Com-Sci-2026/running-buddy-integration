#!/bin/sh
# Creates the cra-secrets Secret with fresh random values, once. Re-running keeps the existing
# Secret, because rotating DB_PASSWORD/JWT_SECRET under live data would lock services out.
# Values exist only inside the cluster; nothing is written to the repository.
. "$(dirname "$0")/env.sh"
kubectl --context "$KUBE_CONTEXT" apply -f "$K8S_DIR/namespace.yaml" >/dev/null
random() { openssl rand -hex 32; }
if k get secret cra-secrets >/dev/null 2>&1; then
  # Keys added after the Secret was first created are filled in; existing values are never rotated.
  if [ -z "$(k get secret cra-secrets -o jsonpath='{.data.PROFILE_STORAGE_SECRET}')" ]; then
    k patch secret cra-secrets --type merge -p "{\"stringData\":{\"PROFILE_STORAGE_SECRET\":\"$(random)\"}}" >/dev/null
    echo "Added PROFILE_STORAGE_SECRET to cra-secrets."
  fi
  echo "Secret cra-secrets already exists; preserved."
  exit 0
fi
k create secret generic cra-secrets \
  --from-literal=POSTGRES_PASSWORD="$(random)" \
  --from-literal=DB_PASSWORD="$(random)" \
  --from-literal=JWT_SECRET="$(random)" \
  --from-literal=BROKER_PASSWORD="$(random)" \
  --from-literal=TEAM_IDENTITY_REFRESH_SECRET="$(random)" \
  --from-literal=PROFILE_STORAGE_SECRET="$(random)"
echo "Created Secret cra-secrets (namespace $NAMESPACE)."
