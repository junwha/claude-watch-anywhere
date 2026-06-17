#!/usr/bin/env bash
# claude-watch-anywhere — start the bridge and expose it over a public HTTPS
# tunnel so the watch can connect from ANY network (no same-Wi-Fi / Bonjour).
#
#   ./run.sh                 # bridge + cloudflared quick tunnel
#   ./run.sh --no-tunnel     # bridge only (LAN/Bonjour, original behavior)
#
# The cloudflared quick tunnel needs no account but its URL changes every run.
# For a stable hostname, set up a named tunnel and export TUNNEL_URL to skip
# the quick tunnel (see AGENTS.md → "Stable tunnel").

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USE_TUNNEL=1
[ "${1:-}" = "--no-tunnel" ] && USE_TUNNEL=0

BRIDGE_LOG="$(mktemp -t cwa-bridge.XXXXXX)"
TUNNEL_LOG="$(mktemp -t cwa-tunnel.XXXXXX)"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -f "$BRIDGE_LOG" "$TUNNEL_LOG"
}
trap cleanup EXIT INT TERM

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- 1. start the bridge, capture its chosen port ---------------------------
say "Starting bridge…"
( cd "$HERE" && node server.js "$@" ) >"$BRIDGE_LOG" 2>&1 &
PIDS+=("$!")

PORT=""
for _ in $(seq 1 30); do
  # banner line looks like:  ║  Port:          7860  ║
  PORT="$(grep -oE 'Port:[[:space:]]+[0-9]+' "$BRIDGE_LOG" | grep -oE '[0-9]+' | head -1 || true)"
  [ -n "$PORT" ] && break
  sleep 0.3
done
[ -n "$PORT" ] || { echo "Bridge did not report a port. Log:"; cat "$BRIDGE_LOG"; exit 1; }

# Surface the bridge banner (pairing code etc.)
grep -E 'Pairing Code|Port:|IP Address|Agents:' "$BRIDGE_LOG" || true

if [ "$USE_TUNNEL" = "0" ]; then
  say "Tunnel disabled. Bridge on LAN port $PORT (use Bonjour or the LAN IP above)."
  wait "${PIDS[0]}"
  exit 0
fi

# --- 2. start cloudflared, capture the public URL ---------------------------
command -v cloudflared >/dev/null 2>&1 || {
  echo "cloudflared not found. Install it ('brew install cloudflared') or run with --no-tunnel."; exit 1; }

say "Opening public tunnel to localhost:$PORT…"
cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate >"$TUNNEL_LOG" 2>&1 &
PIDS+=("$!")

TUNNEL_URL=""
for _ in $(seq 1 40); do
  TUNNEL_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -1 || true)"
  [ -n "$TUNNEL_URL" ] && break
  sleep 0.5
done
[ -n "$TUNNEL_URL" ] || { echo "cloudflared did not report a URL. Log:"; cat "$TUNNEL_LOG"; exit 1; }

cat <<EOF

╔════════════════════════════════════════════════════════════════╗
   CLAUDE WATCH — ANYWHERE
   Tunnel URL : $TUNNEL_URL
   On the watch: tap "Enter URL" and paste the line above, then
   enter the 6-digit pairing code shown by the bridge.
╚════════════════════════════════════════════════════════════════╝

(Ctrl-C to stop both the bridge and the tunnel.)
EOF

wait "${PIDS[0]}"
