#!/bin/sh
# Shares the running Compose stack for a UAT session through a Cloudflare quick tunnel.
#
#   scripts/uat-tunnel.sh start    build the frontend, serve it, open the tunnel, print the link
#   scripts/uat-tunnel.sh status   show the link and whether everything is up
#   scripts/uat-tunnel.sh otp      follow Identity's log for sign-up OTP codes (SMS is not wired up)
#   scripts/uat-tunnel.sh stop     close the tunnel and point Profile back at localhost
#
# One public URL carries everything: `vite preview` serves the production build and forwards /api to
# the gateway and /profile-service to photo storage (see the frontend's vite.config.ts). Profile is
# restarted with that URL as its public storage address so signed photo uploads work on testers'
# devices. The link changes every time the tunnel starts. Needs cloudflared and a running stack.
set -eu
cd "$(dirname "$0")/.."
frontend=../cant-run-alone-frontend
state="$(pwd)/.uat"
port=4173
mkdir -p "$state"

running() { [ -f "$state/$1.pid" ] && kill -0 "$(cat "$state/$1.pid")" 2>/dev/null; }

restart_profile() {
  # Recreates only Profile; an empty value falls back to the localhost default in compose.yaml.
  PROFILE_PHOTO_PUBLIC_URL="$1" docker compose up -d --wait --no-deps profile >/dev/null 2>&1
}

start() {
  command -v cloudflared >/dev/null || { echo "Install cloudflared first: brew install cloudflared" >&2; exit 1; }
  if running tunnel; then echo "Already running: $(cat "$state/url")"; exit 0; fi
  docker compose ps --status running --services | grep -qx gateway || { echo "Start the stack first: docker compose up -d --wait" >&2; exit 1; }

  echo "Building the frontend..."
  (cd "$frontend" && npm run build >/dev/null)
  (cd "$frontend" && nohup npx vite preview --host 127.0.0.1 --port "$port" --strictPort >"$state/preview.log" 2>&1 & echo $! >"$state/preview.pid")

  echo "Opening the tunnel..."
  # An empty config of its own: a named tunnel in ~/.cloudflared/config.yml would otherwise lend this
  # quick tunnel its credentials, and Cloudflare would then answer 404 for the trycloudflare link.
  : >"$state/cloudflared.yml"
  nohup cloudflared --config "$state/cloudflared.yml" tunnel --no-autoupdate --url "http://127.0.0.1:$port" >"$state/tunnel.log" 2>&1 &
  echo $! >"$state/tunnel.pid"
  url=""
  for _ in $(seq 1 30); do
    url=$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$state/tunnel.log" | head -1 || true)
    [ -n "$url" ] && break
    sleep 1
  done
  [ -n "$url" ] || { echo "No tunnel URL after 30 s; see $state/tunnel.log" >&2; stop; exit 1; }
  # The link answers only once the edge connection is registered and the name resolves.
  for _ in $(seq 1 30); do
    curl -s -o /dev/null -w '%{http_code}' "$url/" | grep -qx 200 && break
    sleep 2
  done
  echo "$url" >"$state/url"

  echo "Pointing Profile's photo links at the tunnel..."
  restart_profile "$url"

  cat <<EOF

UAT link: $url

Demo sign-in: ray@example.com / runner123 (Mali: mali@example.com, same password).
New sign-ups need the OTP from Identity's log: scripts/uat-tunnel.sh otp
The link is public while the tunnel is open. Close it afterwards: scripts/uat-tunnel.sh stop
EOF
}

status() {
  if running tunnel; then echo "Tunnel: up  $(cat "$state/url")"; else echo "Tunnel: down"; fi
  if running preview; then echo "Frontend preview: up on 127.0.0.1:$port"; else echo "Frontend preview: down"; fi
  docker compose exec -T profile printenv OBJECT_STORAGE_PUBLIC_ENDPOINT 2>/dev/null | sed 's/^/Profile photo links: /'
}

stop() {
  for name in tunnel preview; do
    if running "$name"; then kill "$(cat "$state/$name.pid")" 2>/dev/null || true; fi
    rm -f "$state/$name.pid"
  done
  # vite preview runs under npx; make sure nothing is left holding the port.
  lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
  rm -f "$state/url"
  echo "Tunnel closed. Pointing Profile's photo links back at localhost..."
  restart_profile ""
}

otp() {
  echo "Waiting for sign-up OTP codes (Ctrl+C to stop)..."
  docker compose logs -f --since 1m identity | grep --line-buffered -E 'OTP|code='
}

case "${1:-}" in
  start) start ;;
  status) status ;;
  stop) stop ;;
  otp) otp ;;
  *) echo "Usage: $0 start|status|otp|stop" >&2; exit 2 ;;
esac
