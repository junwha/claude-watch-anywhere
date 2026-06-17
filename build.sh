#!/usr/bin/env bash
# claude-watch-anywhere — one-shot Mac setup + build.
#
# After cloning the repo, run this on a Mac to get from zero to a buildable
# Xcode project and a ready-to-run bridge.
#
#   ./build.sh                 # install deps + generate Xcode project
#   ./build.sh --open          # ...and open the project in Xcode
#   DEVELOPMENT_TEAM=ABCDE12345 ./build.sh --archive   # ...and try a CLI build
#
# Requirements (auto-checked, installed via Homebrew when missing):
#   node >=18, xcodegen, cloudflared, Xcode (+ command line tools)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$ROOT/skill/bridge"
IOS_DIR="$ROOT/ios/ClaudeWatch"

OPEN=0
ARCHIVE=0
for arg in "$@"; do
  case "$arg" in
    --open) OPEN=1 ;;
    --archive|--build) ARCHIVE=1 ;;
    -h|--help)
      sed -n '2,13p' "$ROOT/build.sh"; exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "build.sh targets macOS. (The bridge alone runs anywhere: 'cd skill/bridge && npm install && node server.js'.)"

# ---------------------------------------------------------------------------
# 1. Toolchain
# ---------------------------------------------------------------------------
say "Checking toolchain"

if ! command -v brew >/dev/null 2>&1; then
  warn "Homebrew not found. Install from https://brew.sh, then re-run."
  warn "Continuing — will fail later if a required tool is missing."
fi

ensure() {  # ensure <command> <brew-formula>
  local cmd="$1" formula="$2"
  if command -v "$cmd" >/dev/null 2>&1; then return 0; fi
  if command -v brew >/dev/null 2>&1; then
    say "Installing $formula via Homebrew"
    brew install "$formula"
  else
    die "$cmd not found and Homebrew unavailable. Install $formula manually."
  fi
}

command -v node >/dev/null 2>&1 || ensure node node
node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
[ "$node_major" -ge 18 ] || die "Node >=18 required (found $(node -v 2>/dev/null || echo none))."
ensure xcodegen xcodegen
ensure cloudflared cloudflared      # used by skill/bridge/run.sh for the tunnel

command -v xcodebuild >/dev/null 2>&1 || warn "Xcode not detected. Install Xcode from the App Store for iOS/watchOS builds."

# ---------------------------------------------------------------------------
# 2. Bridge dependencies
# ---------------------------------------------------------------------------
say "Installing bridge dependencies (skill/bridge)"
( cd "$BRIDGE_DIR" && npm install )

# ---------------------------------------------------------------------------
# 3. Generate the Xcode project
# ---------------------------------------------------------------------------
say "Generating Xcode project (xcodegen)"
( cd "$IOS_DIR" && xcodegen generate )
PROJ="$IOS_DIR/ClaudeWatch.xcodeproj"
[ -d "$PROJ" ] || die "xcodegen did not produce $PROJ"

# ---------------------------------------------------------------------------
# 4. Optional CLI build
# ---------------------------------------------------------------------------
if [ "$ARCHIVE" = "1" ]; then
  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild unavailable; cannot --archive."
  if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    warn "DEVELOPMENT_TEAM not set — a device build needs signing. Building for the simulator instead."
    say "Building ClaudeWatch (iOS Simulator)"
    xcodebuild -project "$PROJ" -scheme ClaudeWatch \
      -destination 'generic/platform=iOS Simulator' \
      -configuration Debug build CODE_SIGNING_ALLOWED=NO
  else
    say "Building ClaudeWatch for device (team $DEVELOPMENT_TEAM)"
    xcodebuild -project "$PROJ" -scheme ClaudeWatch \
      -destination 'generic/platform=iOS' \
      -configuration Debug build DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------------
cat <<EOF

$(say "Setup complete.")

Next:
  1. Start the bridge + tunnel:   ./skill/bridge/run.sh
     (prints a 6-digit pairing code and a public https URL for the watch)
  2. Install Claude Code hooks:   ./skill/setup-hooks.sh
  3. In Xcode: set your Development Team on both targets, then Run.
     Open it now with:            ./build.sh --open

EOF

if [ "$OPEN" = "1" ]; then
  say "Opening Xcode"
  open "$PROJ"
fi
