---
name: claude-watch
description: Start the Claude Watch bridge on this machine and show the 6-digit pairing code.
disable-model-invocation: true
---

# Claude Watch — start the bridge

Start the local bridge so the Apple Watch can see this session's activity and
(via the channel) drive it. The plugin's hooks already stream output and relay
permissions globally; this just brings up the bridge those hooks talk to.

When invoked, do the following:

1. Resolve the bridge directory. It is `"$CLAUDE_PLUGIN_ROOT/skill/bridge"`.
   If `$CLAUDE_PLUGIN_ROOT` is not set in the shell, find it: it is the directory
   of this plugin (contains `.claude-plugin/plugin.json` and `skill/bridge`).
2. If `node_modules` is missing there, run `npm install` in that directory.
3. Start the bridge in the background (use run_in_background):
   `node "<bridge-dir>/server.js"`
   It auto-loads tunnel/relay settings from `<bridge-dir>/.env` if present
   (created by `install.sh`).
4. Wait ~3 seconds, read the background process output, and report to the user:
   - the **6-digit Pairing Code**, and
   - the **Public URL** / "Pair anywhere" line if shown.
5. Tell the user to enter that code on the watch.

Note: receiving output on the watch works through this plugin's hooks regardless.
Sending prompts *from the watch into this live session* additionally requires the
session to have been launched with the watch channel, i.e. via the `cw` alias
(`claude --dangerously-load-development-channels plugin:claude-watch-anywhere@claude-watch`)
that `install.sh` sets up. A skill cannot enable the channel mid-session.
