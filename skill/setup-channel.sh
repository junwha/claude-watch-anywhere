#!/usr/bin/env bash
# claude-watch-anywhere — register the official Channel MCP server (channel.js)
# with Claude Code. This is the Stage-2 / "Channels" piece; it is OPTIONAL and
# independent of the hooks (setup-hooks.sh). Hooks alone already stream output
# and relay permissions; the channel adds sanctioned prompt injection + replies.
#
#   ./setup-channel.sh            # add "claudewatch" MCP server to ~/.claude.json
#   ./setup-channel.sh --remove   # remove it
#
# After installing, start Claude with the research-preview flag:
#   claude --dangerously-load-development-channels server:claudewatch

set -e

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANNEL_JS="$HERE/bridge/channel.js"
CONFIG="$HOME/.claude.json"
BRIDGE_URL="http://127.0.0.1:${1:-7860}"
[ "${1:-}" = "--remove" ] && BRIDGE_URL="http://127.0.0.1:7860"

if [ "${1:-}" = "--remove" ]; then
  [ -f "$CONFIG" ] || { echo "No $CONFIG"; exit 0; }
  python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
servers = c.get('mcpServers', {})
if servers.pop('claudewatch', None) is not None:
    if not servers: c.pop('mcpServers', None)
    else: c['mcpServers'] = servers
    with open('$CONFIG','w') as f: json.dump(c, f, indent=2)
    print('Removed claudewatch channel from $CONFIG')
else:
    print('No claudewatch channel found.')
"
  exit 0
fi

[ -f "$CHANNEL_JS" ] || { echo "channel.js not found at $CHANNEL_JS"; exit 1; }
[ -f "$CONFIG" ] || echo '{}' > "$CONFIG"

python3 -c "
import json
with open('$CONFIG') as f: c = json.load(f)
c.setdefault('mcpServers', {})['claudewatch'] = {
    'command': 'node',
    'args': ['$CHANNEL_JS'],
    'env': {'CLAUDE_WATCH_BRIDGE': '$BRIDGE_URL'},
}
with open('$CONFIG','w') as f: json.dump(c, f, indent=2)
print('Registered claudewatch channel in $CONFIG')
"

cat <<EOF

Done. Start Claude Code with the channel enabled:

  claude --dangerously-load-development-channels server:claudewatch

(The dev flag is required while Channels are in research preview.)
Remove with: ./setup-channel.sh --remove
EOF
