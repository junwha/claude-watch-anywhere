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

## Build & run on the Mac

```bash
# 0. clone, then:
./build.sh --open            # installs deps, generates ClaudeWatch.xcodeproj, opens Xcode
# In Xcode: set Development Team on BOTH targets (ClaudeWatch + ClaudeWatchWatch), Run.

# 1. bridge + tunnel (anywhere access)
./skill/bridge/run.sh        # prints a 6-digit pairing code AND an https://...trycloudflare.com URL

# 2. hooks (output + permission relay)
./skill/setup-hooks.sh

# 3. (optional, Stage 2) channels
./skill/setup-channel.sh
claude --dangerously-load-development-channels server:claudewatch
```

On the watch: when auto-discovery fails, tap into the manual field and paste the
**tunnel URL** (or a LAN IP), then enter the pairing code.

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
