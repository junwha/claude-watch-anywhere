# AGENTS.md — handoff for the Mac session

This file is the pickup point for continuing **claude-watch-anywhere** on a Mac.
It was authored on a Linux box (no Xcode/macOS), so **everything Swift- or
tunnel-related is implemented but not yet run.** Your job on the Mac is to
build, run, and debug. Read this top-to-bottom before touching code.

## What this project is

Control a local Claude Code session from an Apple Watch. The original
(`shobhit99/claude-watch`) only worked on the **same Wi-Fi** via Bonjour/mDNS.
This fork adds two things:

1. **Anywhere access** — a cloudflared tunnel puts the bridge on a public HTTPS
   URL, so the watch no longer needs the same network.
2. **Official Channels integration** — a Claude Code *channel* MCP server
   (`channel.js`) injects watch prompts into the live session and sends replies
   back, using the sanctioned API instead of only hook interception.

Why not just use Claude Code's built-in Remote Control? Because its only client
surfaces are the web (`claude.ai/code`) and the first-party iOS/Android app —
**no watchOS**, no public client API, and reusing the OAuth token in a custom
client violates Anthropic's ToS. So the watch must ride Claude Code's *extension*
surfaces (hooks + channels), which is what this repo does.

## Architecture (hybrid — important)

```
            ┌─────────── Mac ───────────┐
 Apple      │  server.js (bridge)        │
 Watch ──── │   • HTTP + SSE to watch    │ ── hooks ──┐
 (+iPhone)  │   • /channel/inbox (LP)    │            ▼
   ▲        │   • /channel/reply         │      Claude Code session
   │        │            ▲  │            │            ▲
   │ HTTPS  │            │  │ localhost  │            │ stdio (MCP)
   └─tunnel─┤        channel.js ─────────┼────────────┘
            └────────────────────────────┘
```

- **hooks** (`setup-hooks.sh`) → live tool output + permission relay. *Unchanged,
  already working upstream.* This is the only source of live terminal output;
  channels cannot provide it.
- **channel.js** → NEW. Inbound prompt injection (watch voice → live session) +
  `watch_reply` tool (Claude → watch). Talks to the bridge over localhost.
- **tunnel** (`run.sh`) → NEW. cloudflared quick tunnel for anywhere access.

The two paths are decoupled: if the channel isn't running, voice commands fall
back to the original `claude -p --continue` behavior in `handleCommand`.

## What changed in this branch

| File | Change | Tested here? |
|------|--------|------|
| `build.sh` | NEW — Mac setup/build (deps, xcodegen, optional xcodebuild) | shellcheck `bash -n` only |
| `skill/bridge/run.sh` | NEW — start bridge + cloudflared, print tunnel URL | `bash -n` only |
| `skill/bridge/channel.js` | NEW — Channel MCP server | `node --check` only |
| `skill/setup-channel.sh` | NEW — register channel in `~/.claude.json` | `bash -n` only |
| `skill/bridge/server.js` | `/channel/inbox` (long-poll) + `/channel/reply`; route prompts to channel when live | `node --check` only |
| `skill/bridge/package.json` | added `@modelcontextprotocol/sdk` | — |
| `ios/.../watchOS/Views/OnboardingView.swift` | manual entry accepts a full URL / DNS host (tunnel), not just a bare IP | **NOT compiled** |

Nothing in the iOS/watchOS app was compiled. The Swift change is small and
self-contained (see `connectManual` + new `directBaseURL`/`probe` helpers) but
**verify it builds first.**

## Entry points: build.sh vs install.sh (two separate machines)

The watch app and the Claude-side plugin are **decoupled** on purpose.

- **`./build.sh`** — run on a **Mac** (needs Xcode). One command: toolchain →
  deploy the Cloudflare relay (`wrangler login` is the only stop) → inject the
  relay `*.workers.dev` URL into `WatchBridgeClient.relayURLString` → `xcodegen`
  → open/▶ Xcode. Stops only for `wrangler login` and Apple signing.
  `--no-relay` skips the relay; `RELAY_URL=… ./build.sh` reuses one.
- **`./install.sh`** — run on **whatever machine runs Claude Code** (may be
  Windows/Linux, not the Mac). Installs the plugin (`claude plugin marketplace
  add . && claude plugin install claude-watch-anywhere@claude-watch`), scaffolds
  `skill/bridge/.env`, and adds a `cw` shell alias (`--alias-claude` to override
  plain `claude`, `--no-alias` to skip).

Why separate: building the watch app has nothing to do with installing the
plugin, and they usually run on different machines.

## The plugin (global, not project-dependent)

Repo root **is** the plugin and a one-plugin marketplace:
- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`
- `hooks/hooks.json` — the http hooks (output + permission relay), now global via
  the plugin instead of `setup-hooks.sh`.
- `.mcp.json` — registers the channel (`${CLAUDE_PLUGIN_ROOT}/skill/bridge/channel.js`).
- `monitors/monitors.json` → Claude Code auto-runs `node skill/bridge/server.js`
  in the background when the plugin is active; the bridge banner (pairing code)
  streams to Claude as a notification to relay. Deterministic — no skill / no
  model reasoning, and no detached-process hacks. (The earlier `skills/claude-watch`
  SKILL.md and a `launch.js`/SessionStart approach were removed for this.)
- `skill/bridge/server.js` self-loads `skill/bridge/.env` and honors
  `CLAUDE_WATCH_QUIET=1` (only the pairing line + warnings) and
  `CLAUDE_WATCH_SINGLE=1` (exit if a bridge is already on 7860) so the monitor is
  quiet and idempotent across sessions.

**Channel caveat (unchanged by plugin):** prompt-injection still needs the
research-preview launch flag, so the session must start via the `cw` alias =
`claude --dangerously-load-development-channels plugin:claude-watch-anywhere@claude-watch`.
Output/pairing work without it.

**Verified here:** all JSON valid, bash `-n` clean. **NOT verified:** actual
`claude plugin install` / plugin load / hooks firing / channel-as-plugin — needs
a real Claude Code on the target machine. The old `setup-hooks.sh` /
`setup-channel.sh` / `run.sh` still work for non-plugin/manual use.

On the watch: enter just the 6-digit code (relay resolves the URL). If no relay,
tap "Enter URL manually" for a LAN IP / tunnel URL.

## Debug checklist (most-likely-broken first)

1. **Swift compile.** The watch target may not build — check `connectManual()` in
   `OnboardingView.swift`. `URLSession.shared` on watchOS is fine; the helpers are
   `static` to avoid capturing `self` in the `Task`.
2. **SSE over the tunnel.** The watch consumes `/events` (SSE) — confirm
   cloudflared streams it without buffering. Test:
   `curl -N <tunnel>/events -H "Authorization: Bearer <token>"`.
   If buffered, switch the watch to the existing `/status` polling path, or use a
   named tunnel.
3. **`PORT` parsing in run.sh.** It greps the bridge banner for `Port:`. If the
   banner format changes, the grep breaks — check `server.js` around line ~1585.
4. **Channel registration.** `claude --dangerously-load-development-channels
   server:claudewatch` must show the channel registered (dim notice under the
   banner). If "blocked by org policy," channels are disabled for the org.
5. **`channelConnected()` window.** The bridge only routes prompts to the channel
   if `/channel/inbox` was polled within 60s. If channel.js dies, prompts silently
   fall back to `claude -p`. Watch the bridge log.
6. **MCP SDK version.** `@modelcontextprotocol/sdk` is pinned `^1.0.0`; if the
   `Server`/notification API differs, channel.js needs adjusting to the installed
   version. `cd skill/bridge && npm ls @modelcontextprotocol/sdk`.

## Digits-only pairing (relay)

So the watch can pair from ANY network by typing only the 6-digit code (no URL),
there's a free Cloudflare Worker rendezvous relay in `relay/`.

Flow: bridge registers `code -> current tunnel URL` with the relay; watch sends
the code to the relay (its URL is baked into the app, fixed forever) and gets the
tunnel URL back, then pairs normally. The session token never touches the relay.

- `relay/src/worker.js` — Worker. `/register` (bridge, secret-gated), `/resolve`
  (watch, rate-limited), `/health`. **Verified**: `cd relay && npm test` → 8/8.
- `skill/bridge/relay.js` — bridge side: spawns cloudflared (or uses
  `CLAUDE_WATCH_TUNNEL_URL`) and registers the code. **Verified** end-to-end
  against a fake relay (registers `{code,url}` + `Bearer` auth). cloudflared spawn
  itself is syntax-checked only.
- `WatchBridgeClient.resolve(code:)` + digits-first `OnboardingView` — **NOT
  compiled** (no Xcode).

**To enable (after deploying the Worker — see `relay/README.md`):**
1. Deploy: `cd relay && wrangler kv namespace create PAIRINGS` (paste id into
   `wrangler.toml`), `wrangler secret put RELAY_SECRET`, `wrangler deploy`.
2. Bridge env (Windows): `CLAUDE_WATCH_RELAY`, `CLAUDE_WATCH_RELAY_SECRET`,
   `CLAUDE_WATCH_TUNNEL=1`, then `node server.js`.
3. Watch: set `WatchBridgeClient.relayURLString` to your `*.workers.dev` URL,
   rebuild. (Empty string = relay disabled, LAN/manual only.)

Without any of this, pairing still works on LAN (Bonjour, digits-only) and via
manual URL entry — the relay is purely the "anywhere + digits-only" upgrade.

## Known gaps / next steps

- **Ephemeral tunnel URL.** cloudflared quick tunnels get a new URL each run, so
  you must re-enter it on the watch. For a stable URL set up a *named* tunnel and
  export `TUNNEL_URL` (then teach `run.sh`/the watch to reuse it). See
  <https://developers.cloudflare.com/cloudflare-tunnel/>.
- **No auth on `/channel/*`.** Like `/hooks/*`, these are localhost-only and
  unauthenticated. Fine because they're not exposed through the tunnel — but if
  you ever tunnel the whole host, gate them.
- **Permission relay still on hooks.** Moving it to the channel's
  `claude/channel/permission` capability would unify the path but risks
  double-prompting; left as a follow-up.
- **Branding.** README/strings say "claude-watch-anywhere"; bundle IDs are still
  `com.shobhit.claudewatch` to avoid breaking signing. Rename later if desired.

## Reference

- Channels reference (the contract `channel.js` implements):
  <https://code.claude.com/docs/en/channels-reference>
- Remote Control (why the watch can't use it directly):
  <https://code.claude.com/docs/en/remote-control>
