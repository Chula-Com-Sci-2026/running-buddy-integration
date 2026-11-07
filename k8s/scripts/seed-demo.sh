#!/bin/sh
# Seeds Ray, Mali, their profiles and the prepared past run into the cluster's databases, using
# the same scripts as Compose (team Identity seed, then scripts/seed.py). Inserts only; existing
# rows are preserved.
. "$(dirname "$0")/env.sh"
TOOL_IMAGE=cra/identity:local "$K8S_DIR/scripts/run-tool.sh" sh -c \
  'DATABASE_URL="postgresql://identity:$DB_PASSWORD@postgres:5432/identity_team" node scripts/seed-demo.js'
"$K8S_DIR/scripts/run-tool.sh" python seed.py
