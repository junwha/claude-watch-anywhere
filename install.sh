#!/usr/bin/env bash
# claude-watch-anywhere — install the plugin on THIS machine (where you run
# Claude Code). Separate from build.sh (which builds the watch app on a Mac).
#
#   ./install.sh                 # add marketplace, install plugin, add `cw` alias
#   ./install.sh --alias-claude  # also make plain `claude` always load the channel
#   ./install.sh --no-alias      # skip the shell alias
#
# What it does (global, not project-dependent):
#   1. npm install for the bridge
#   2. scaffold skill/bridge/.env (relay/tunnel config) if missing
#   3. claude plugin marketplace add . && claude plugin install ...
#   4. add a `cw` shell alias that launches Claude with the watch channel

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$ROOT/skill/bridge"
PLUGIN="claude-watch-anywhere"
MARKET="claude-watch"
ALIAS_CMD="claude --dangerously-load-development-channels plugin:${PLUGIN}@${MARKET}"

ALIAS_MODE="cw"        # cw | claude | none
for a in "$@"; do
  case "$a" in
    --alias-claude) ALIAS_MODE="claude" ;;
    --no-alias)     ALIAS_MODE="none" ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $a" >&2; exit 1 ;;
  esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

command -v node >/dev/null 2>&1 || { echo "Node >=18 required."; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "Claude Code CLI ('claude') not found on PATH."; exit 1; }

# 1. bridge deps
say "Installing bridge dependencies"
( cd "$BRIDGE" && npm install )

# 2. .env scaffold
if [ ! -f "$BRIDGE/.env" ]; then
  say "Creating $BRIDGE/.env (fill in your relay values for anywhere/digits-only)"
  cp "$BRIDGE/.env.example" "$BRIDGE/.env"
  warn "Edit skill/bridge/.env: set CLAUDE_WATCH_RELAY + CLAUDE_WATCH_RELAY_SECRET (from build.sh / relay deploy). Leave blank for LAN-only."
fi

# 3. plugin install (global)
say "Registering marketplace + installing plugin"
claude plugin marketplace add "$ROOT" 2>&1 || warn "marketplace add returned nonzero (already added?)"
claude plugin install "${PLUGIN}@${MARKET}" 2>&1 || warn "plugin install returned nonzero (already installed?)"

# 4. shell alias
if [ "$ALIAS_MODE" != "none" ]; then
  RC=""
  case "${SHELL:-}" in
    *zsh*) RC="$HOME/.zshrc" ;;
    *bash*) RC="$HOME/.bashrc" ;;
    *) [ -f "$HOME/.zshrc" ] && RC="$HOME/.zshrc" || RC="$HOME/.bashrc" ;;
  esac
  touch "$RC"
  # remove any previous block, then append a fresh one (idempotent)
  if grep -q "# >>> claude-watch-anywhere >>>" "$RC" 2>/dev/null; then
    tmp="$(mktemp)"; sed '/# >>> claude-watch-anywhere >>>/,/# <<< claude-watch-anywhere <<</d' "$RC" > "$tmp"; mv "$tmp" "$RC"
  fi
  {
    echo "# >>> claude-watch-anywhere >>>"
    if [ "$ALIAS_MODE" = "claude" ]; then
      echo "alias claude='$ALIAS_CMD'"
    else
      echo "alias cw='$ALIAS_CMD'"
    fi
    echo "# <<< claude-watch-anywhere <<<"
  } >> "$RC"
  say "Added alias to $RC ($([ "$ALIAS_MODE" = claude ] && echo 'claude' || echo 'cw'))"
fi

cat <<EOF

$(say "Plugin installed.")

Use it:
  1. Open a NEW shell (so the alias loads), then start a session:
       $([ "$ALIAS_MODE" = claude ] && echo 'claude' || echo 'cw')      # = $ALIAS_CMD
  2. The plugin's background monitor auto-starts the bridge and the session
     announces a 6-digit PAIRING CODE. (No skill, no manual command.)
  3. Enter that code on the watch. Done.

Relay (anywhere + digits-only): fill skill/bridge/.env, deploy relay/ via build.sh.
EOF
