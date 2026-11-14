#!/bin/sh
# Starts the demo from a clean slate: discards every local database, queue and stored photo, then
# starts the stack with team Identity and seeds it again. Run it after rehearsing, so rehearsal
# requests, runs, ratings and sign-ups are gone. Never use it on data you want to keep.
set -eu
cd "$(dirname "$0")/.."
docker compose -f compose.yaml -f compose.team-identity.yaml down -v --remove-orphans
sh scripts/start-team-identity.sh
