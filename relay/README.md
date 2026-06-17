# claude-watch-anywhere — rendezvous relay

A tiny **free** Cloudflare Worker that lets the watch pair from any network by
typing **only the 6-digit code** (no URL). It maps `code -> bridge tunnel URL`.
The session token never passes through it (the watch still calls `<url>/pair`).

```
Bridge (Windows) ──register: code → tunnelURL──▶ [ Worker + KV ] ◀── resolve: code ── Watch
```

## Deploy (one-time, free tier)

Wrangler ships on npm (Homebrew disabled its formula), so use `npx wrangler` —
`npm install` here pulls it in as a devDependency, no global install needed.

```bash
cd relay
npm install                                 # installs wrangler locally
npx wrangler login
npx wrangler kv namespace create PAIRINGS   # copy the printed id into wrangler.toml
npx wrangler secret put RELAY_SECRET        # enter any random string; remember it
npx wrangler deploy                         # prints https://claude-watch-relay.<you>.workers.dev
```

(Or just run `./build.sh` from the repo root, which does all of this and injects
the resulting URL into the watch app.)

## Wire it up

**Bridge (Windows, PowerShell/cmd)** — set env before starting, then run:

```bat
set CLAUDE_WATCH_RELAY=https://claude-watch-relay.<you>.workers.dev
set CLAUDE_WATCH_RELAY_SECRET=<the same secret>
set CLAUDE_WATCH_TUNNEL=1
node server.js
```

The bridge will spawn a cloudflared quick tunnel, register `code -> url` with the
relay, and re-register whenever the code rotates. (Needs `cloudflared` on PATH:
`winget install Cloudflare.cloudflared` or `scoop install cloudflared`.)

**Watch app** — set the relay URL once and rebuild (on a Mac):
`ios/ClaudeWatch/ClaudeWatch watchOS/Services/WatchBridgeClient.swift` →
`relayURLString`.

## Endpoints

| Method | Path | Caller | Body | Returns |
|---|---|---|---|---|
| POST | `/register` | bridge | `{code, url}` + `Authorization: Bearer <secret>` | `{ok:true}` |
| POST | `/resolve` | watch | `{code}` | `{url}` (404 if unknown) |
| GET  | `/health` | — | — | `{ok:true}` |

Security: `/register` requires the secret; `/resolve` is rate-limited per IP and
entries expire in ~10 min. A resolved URL is still useless without the single-use
pairing code, which is validated by the bridge, not the relay.

## Test the logic locally (no Cloudflare needed)

```bash
cd relay && npm test
```
