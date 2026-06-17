#!/usr/bin/env bash
# claude-watch-anywhere — build the WATCH APP end to end (run on a Mac).
#
# One command takes a fresh clone to an installable watch app. It only stops for
# things that genuinely need you: `wrangler login` (browser) and Apple signing.
#
#   ./build.sh                     # toolchain + relay deploy + inject URL + xcodegen + open Xcode
#   ./build.sh --archive           # ...and also do a CLI build (needs DEVELOPMENT_TEAM or simulator)
#   ./build.sh --no-relay          # skip the Cloudflare relay step (LAN/manual pairing only)
#   RELAY_URL=https://x.workers.dev ./build.sh   # reuse an already-deployed relay (no wrangler)
#
# NOTE: installing the Claude Code PLUGIN is a SEPARATE step — see ./install.sh.
# It runs on whatever machine you run Claude on (which may not be this Mac).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$ROOT/skill/bridge"
RELAY_DIR="$ROOT/relay"
IOS_DIR="$ROOT/ios/ClaudeWatch"
PROJ="$IOS_DIR/ClaudeWatch.xcodeproj"
SWIFT_CLIENT="$IOS_DIR/ClaudeWatch watchOS/Services/WatchBridgeClient.swift"

DO_RELAY=1; DO_OPEN=1; DO_ARCHIVE=0
for a in "$@"; do
  case "$a" in
    --no-relay) DO_RELAY=0 ;;
    --no-open)  DO_OPEN=0 ;;
    --archive|--build) DO_ARCHIVE=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $a" >&2; exit 1 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "build.sh builds the watch app and needs macOS + Xcode."

# ---------------------------------------------------------------------------
# 1. Toolchain
# ---------------------------------------------------------------------------
say "Phase 1/5 — toolchain"
ensure() { # ensure <cmd> <brew-formula>
  command -v "$1" >/dev/null 2>&1 && return 0
  command -v brew >/dev/null 2>&1 || die "$1 missing and Homebrew not installed (https://brew.sh)."
  say "Installing $2"; brew install "$2"
}
ensure node node
[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 18 ] || die "Node >=18 required."
ensure xcodegen xcodegen
command -v xcodebuild >/dev/null 2>&1 || die "Xcode not installed (App Store)."
# wrangler is run via `npx` (Homebrew disabled the formula; Cloudflare ships it on npm).
command -v npx >/dev/null 2>&1 || die "npx not found (comes with Node)."

# ---------------------------------------------------------------------------
# 2. Bridge deps
# ---------------------------------------------------------------------------
say "Phase 2/5 — bridge dependencies"
( cd "$BRIDGE" && npm install )

# ---------------------------------------------------------------------------
# 3. Relay deploy (Cloudflare Worker) -> RELAY_URL
# ---------------------------------------------------------------------------
RELAY_SECRET=""
if [ "$DO_RELAY" = 1 ] && [ -z "${RELAY_URL:-}" ]; then
  say "Phase 3/5 — deploying the rendezvous relay (Cloudflare)"
  ( cd "$RELAY_DIR" && npm install )   # pulls wrangler (devDependency)

  warn "A browser will open for 'wrangler login' if you're not logged in."
  ( cd "$RELAY_DIR" && npx wrangler whoami >/dev/null 2>&1 || npx wrangler login )

  # KV namespace (only if not yet wired into wrangler.toml)
  if grep -q "REPLACE_WITH_YOUR_KV_NAMESPACE_ID" "$RELAY_DIR/wrangler.toml"; then
    say "Creating KV namespace PAIRINGS"
    KV_OUT="$(cd "$RELAY_DIR" && npx wrangler kv namespace create PAIRINGS 2>&1)" || { echo "$KV_OUT"; die "KV create failed"; }
    KV_ID="$(printf '%s' "$KV_OUT" | grep -oE '[0-9a-f]{32}' | head -1)"
    [ -n "$KV_ID" ] || { echo "$KV_OUT"; die "Could not parse KV id — paste it into relay/wrangler.toml manually."; }
    sed -i '' "s/REPLACE_WITH_YOUR_KV_NAMESPACE_ID/$KV_ID/" "$RELAY_DIR/wrangler.toml"
    say "KV id wired: $KV_ID"
  fi

  # Shared secret (auto-generated, stored to bridge .env)
  RELAY_SECRET="$(openssl rand -hex 16)"
  say "Setting RELAY_SECRET"
  ( cd "$RELAY_DIR" && printf '%s' "$RELAY_SECRET" | npx wrangler secret put RELAY_SECRET >/dev/null )

  say "Deploying Worker"
  DEPLOY_OUT="$(cd "$RELAY_DIR" && npx wrangler deploy 2>&1)" || { echo "$DEPLOY_OUT"; die "wrangler deploy failed"; }
  RELAY_URL="$(printf '%s' "$DEPLOY_OUT" | grep -oE 'https://[a-z0-9.-]+\.workers\.dev' | head -1)"
  [ -n "$RELAY_URL" ] || { echo "$DEPLOY_OUT"; die "Could not parse the Worker URL from wrangler output."; }
  say "Relay live: $RELAY_URL"

  # Persist for the bridge (so 'node server.js' here is configured)
  {
    echo "CLAUDE_WATCH_RELAY=$RELAY_URL"
    echo "CLAUDE_WATCH_RELAY_SECRET=$RELAY_SECRET"
    echo "CLAUDE_WATCH_TUNNEL=1"
  } > "$BRIDGE/.env"
  say "Wrote $BRIDGE/.env"
elif [ "$DO_RELAY" = 0 ]; then
  say "Phase 3/5 — skipped (--no-relay): watch will pair via LAN/manual only"
else
  say "Phase 3/5 — using provided RELAY_URL=$RELAY_URL"
fi

# ---------------------------------------------------------------------------
# 4. Inject the relay URL into the watch app
# ---------------------------------------------------------------------------
say "Phase 4/5 — injecting relay URL into the watch app"
if [ -n "${RELAY_URL:-}" ]; then
  [ -f "$SWIFT_CLIENT" ] || die "Missing $SWIFT_CLIENT"
  # Replace the relayURLString literal (idempotent: matches any current value)
  sed -i '' -E "s#(static let relayURLString = )\"[^\"]*\"#\\1\"$RELAY_URL\"#" "$SWIFT_CLIENT"
  grep -q "relayURLString = \"$RELAY_URL\"" "$SWIFT_CLIENT" || die "Failed to inject relay URL into Swift."
  say "relayURLString set to $RELAY_URL"
else
  warn "No relay URL — leaving relayURLString empty (LAN/manual pairing only)."
fi

# ---------------------------------------------------------------------------
# 5. Xcode project + build
# ---------------------------------------------------------------------------
say "Phase 5/5 — generating Xcode project"
( cd "$IOS_DIR" && xcodegen generate )
[ -d "$PROJ" ] || die "xcodegen did not produce $PROJ"

if [ "$DO_ARCHIVE" = 1 ]; then
  if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    say "Building for device (team $DEVELOPMENT_TEAM)"
    xcodebuild -project "$PROJ" -scheme ClaudeWatch -destination 'generic/platform=iOS' \
      -configuration Debug build DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  else
    warn "DEVELOPMENT_TEAM not set — building for the simulator (no signing)."
    xcodebuild -project "$PROJ" -scheme ClaudeWatch -destination 'generic/platform=iOS Simulator' \
      -configuration Debug build CODE_SIGNING_ALLOWED=NO
  fi
fi

cat <<EOF

$(say "Watch app ready. Xcode is open — now install it on your watch:")
  Relay URL : ${RELAY_URL:-<none — LAN/manual only>}
$( [ -n "$RELAY_SECRET" ] && echo "  Relay secret (for the bridge .env on other machines): $RELAY_SECRET" )

  INSTALL ON THE WATCH  (full friendly guide: WATCH_INSTALL.md)
  1. Plug in your iPhone (it must be paired to the watch); tap Trust if asked.
  2. In Xcode left sidebar → ClaudeWatch project → for BOTH targets
     (ClaudeWatch + ClaudeWatchWatch): Signing & Capabilities →
     tick "Automatically manage signing" → set Team to your Apple ID.
  3. Top bar: scheme = ClaudeWatch (the iPhone app), destination = your iPhone.
  4. Press ▶ (Cmd+R). It installs on the phone and pushes the watch app over.
  5. If prompted on iPhone: Settings → General → VPN & Device Management → Trust.
  6. Watch app on iPhone → Available Apps → Install "Agent Watch" (if not automatic).
  7. Open it on the watch and type the 6-digit pairing code.

  Then, on the machine you run Claude:  ./install.sh
  Start the bridge + get the code:      inside Claude run /claude-watch-anywhere:claude-watch
  Stuck? See WATCH_INSTALL.md (signing errors, "won't appear on watch", 7-day free-account note).
EOF

[ "$DO_OPEN" = 1 ] && { say "Opening Xcode"; open "$PROJ"; }
