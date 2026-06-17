// claude-watch-anywhere — bridge side of the rendezvous relay.
//
// When enabled via env, this:
//   1. obtains a public URL (spawns a cloudflared quick tunnel, or uses a
//      provided CLAUDE_WATCH_TUNNEL_URL for a named/stable tunnel), and
//   2. registers `code -> url` with the relay Worker so the watch can pair with
//      only the 6-digit code, and keeps it fresh as the code rotates.
//
// Env:
//   CLAUDE_WATCH_RELAY         relay base URL (e.g. https://...workers.dev)
//   CLAUDE_WATCH_RELAY_SECRET  shared secret for /register (optional)
//   CLAUDE_WATCH_TUNNEL=1      spawn a cloudflared quick tunnel
//   CLAUDE_WATCH_TUNNEL_URL    use this public URL instead of spawning one
//
// All of this is opt-in: if no relevant env is set, initRelay() returns null and
// the bridge stays LAN/Bonjour only.

import { spawn } from "node:child_process";

const TRYCLOUDFLARE_RE = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/;

export async function initRelay({ port, log }) {
  const RELAY = (process.env.CLAUDE_WATCH_RELAY || "").replace(/\/$/, "");
  const SECRET = process.env.CLAUDE_WATCH_RELAY_SECRET || "";
  const TUNNEL_URL_ENV = process.env.CLAUDE_WATCH_TUNNEL_URL || "";
  const WANT_TUNNEL = process.env.CLAUDE_WATCH_TUNNEL === "1" || !!TUNNEL_URL_ENV;

  if (!RELAY && !WANT_TUNNEL) return null; // nothing requested

  let publicUrl = TUNNEL_URL_ENV || null;
  let cfProc = null;
  if (!publicUrl) {
    const r = await spawnCloudflared(port, log);
    publicUrl = r.url;
    cfProc = r.proc;
  }

  let currentCode = null;
  async function register(code) {
    if (code) currentCode = code;
    if (!RELAY || !currentCode || !publicUrl) return;
    try {
      const res = await fetch(`${RELAY}/register`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(SECRET ? { Authorization: `Bearer ${SECRET}` } : {}),
        },
        body: JSON.stringify({ code: currentCode, url: publicUrl }),
      });
      if (res.ok) log("info", `Relay: registered code ${currentCode}`);
      else log("warn", `Relay register failed: HTTP ${res.status}`);
    } catch (err) {
      log("warn", `Relay register error: ${err.message}`);
    }
  }

  // Keep the registration alive while waiting to pair (relay TTL ~10 min).
  const refresh = setInterval(() => register(), 4 * 60 * 1000);
  if (refresh.unref) refresh.unref();

  function stop() {
    clearInterval(refresh);
    if (cfProc) {
      try {
        cfProc.kill();
      } catch {
        /* ignore */
      }
    }
  }

  return { publicUrl, hasRelay: !!RELAY, register, stop };
}

function spawnCloudflared(port, log) {
  return new Promise((resolve, reject) => {
    let proc;
    try {
      proc = spawn("cloudflared", ["tunnel", "--url", `http://localhost:${port}`, "--no-autoupdate"], {
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (err) {
      return reject(err);
    }
    let done = false;
    const scan = (buf) => {
      const m = buf.toString().match(TRYCLOUDFLARE_RE);
      if (m && !done) {
        done = true;
        log("info", `Tunnel up: ${m[0]}`);
        resolve({ url: m[0], proc });
      }
    };
    proc.stdout.on("data", scan);
    proc.stderr.on("data", scan);
    proc.on("error", (err) => {
      if (!done) {
        done = true;
        reject(new Error(`cloudflared failed to start (${err.message}). Install it or set CLAUDE_WATCH_TUNNEL_URL.`));
      }
    });
    setTimeout(() => {
      if (!done) {
        done = true;
        reject(new Error("cloudflared did not report a URL within 30s"));
      }
    }, 30_000);
  });
}
