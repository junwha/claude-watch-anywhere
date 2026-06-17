// claude-watch-anywhere — rendezvous relay (Cloudflare Worker).
//
// Maps a 6-digit pairing code -> the bridge's current public tunnel URL so the
// watch can pair from ANY network by typing ONLY the code. This is the tiny,
// free stand-in for the cloud routing that Anthropic's Remote Control does (and
// which the watch can't use).
//
// Security model (mirrors the bridge's own pairing):
//   • POST /register  (bridge -> relay)  stores code -> { url }, short TTL.
//        Requires `Authorization: Bearer <RELAY_SECRET>` when RELAY_SECRET is set.
//   • POST /resolve   (watch  -> relay)  returns { url } for a code, rate-limited.
//   The session TOKEN never touches the relay: the watch still calls <url>/pair
//   with the code to obtain its token directly from the bridge. So even a leaked
//   URL is useless without the (single-use, bridge-side) pairing code.

const CODE_RE = /^\d{6}$/;
const REGISTER_TTL = 600; // a registration lives ~10 min
const RESOLVE_WINDOW = 300; // rate-limit window (s); also KV min-TTL friendly
const RESOLVE_MAX = 30; // max resolve attempts per IP per window

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    };
    const json = (status, body) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json", ...cors },
      });

    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    if (url.pathname === "/health") return json(200, { ok: true });

    // --- bridge registers its current code -> public URL ---
    if (url.pathname === "/register" && request.method === "POST") {
      if (env.RELAY_SECRET) {
        const auth = request.headers.get("Authorization") || "";
        if (auth !== `Bearer ${env.RELAY_SECRET}`) return json(401, { error: "unauthorized" });
      }
      let body;
      try {
        body = await request.json();
      } catch {
        return json(400, { error: "bad json" });
      }
      const code = body && body.code;
      const target = body && body.url;
      if (!CODE_RE.test(code || "")) return json(400, { error: "bad code" });
      if (typeof target !== "string" || !/^https?:\/\//.test(target)) {
        return json(400, { error: "bad url" });
      }
      await env.PAIRINGS.put(`code:${code}`, JSON.stringify({ url: target }), {
        expirationTtl: REGISTER_TTL,
      });
      return json(200, { ok: true });
    }

    // --- watch resolves a code -> URL ---
    if (url.pathname === "/resolve" && request.method === "POST") {
      const ip = request.headers.get("CF-Connecting-IP") || "anon";
      const rlKey = `rl:${ip}`;
      const count = parseInt((await env.PAIRINGS.get(rlKey)) || "0", 10);
      if (count >= RESOLVE_MAX) return json(429, { error: "rate limited" });
      await env.PAIRINGS.put(rlKey, String(count + 1), { expirationTtl: RESOLVE_WINDOW });

      let body;
      try {
        body = await request.json();
      } catch {
        return json(400, { error: "bad json" });
      }
      const code = body && body.code;
      if (!CODE_RE.test(code || "")) return json(400, { error: "bad code" });
      const raw = await env.PAIRINGS.get(`code:${code}`);
      if (!raw) return json(404, { error: "not found" });
      return json(200, JSON.parse(raw));
    }

    return json(404, { error: "not found" });
  },
};
