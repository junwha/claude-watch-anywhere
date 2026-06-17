// Local logic test for the relay Worker — no Cloudflare needed.
// Provides a fake KV (Map with TTL ignored) and drives the fetch handler.
import worker from "./src/worker.js";

function makeKV() {
  const m = new Map();
  return {
    async get(k) { return m.has(k) ? m.get(k) : null; },
    async put(k, v) { m.set(k, v); },
    _dump: m,
  };
}

const env = { PAIRINGS: makeKV(), RELAY_SECRET: "s3cret" };
const call = (path, { method = "POST", body, headers = {} } = {}) =>
  worker.fetch(
    new Request(`https://relay.test${path}`, {
      method,
      headers: { "Content-Type": "application/json", "CF-Connecting-IP": "1.2.3.4", ...headers },
      body: body ? JSON.stringify(body) : undefined,
    }),
    env,
  );

let pass = 0, fail = 0;
async function check(name, fn) {
  try { await fn(); console.log("  ok  -", name); pass++; }
  catch (e) { console.log("  FAIL-", name, "::", e.message); fail++; }
}
const eq = (a, b, m) => { if (a !== b) throw new Error(`${m}: ${a} !== ${b}`); };

await check("register without secret -> 401", async () => {
  const r = await call("/register", { body: { code: "123456", url: "https://x.trycloudflare.com" } });
  eq(r.status, 401, "status");
});

await check("register with secret -> 200", async () => {
  const r = await call("/register", {
    headers: { Authorization: "Bearer s3cret" },
    body: { code: "123456", url: "https://abc.trycloudflare.com" },
  });
  eq(r.status, 200, "status");
});

await check("register bad code -> 400", async () => {
  const r = await call("/register", {
    headers: { Authorization: "Bearer s3cret" },
    body: { code: "12", url: "https://abc.trycloudflare.com" },
  });
  eq(r.status, 400, "status");
});

await check("register bad url -> 400", async () => {
  const r = await call("/register", {
    headers: { Authorization: "Bearer s3cret" },
    body: { code: "123456", url: "ftp://nope" },
  });
  eq(r.status, 400, "status");
});

await check("resolve known code -> url", async () => {
  const r = await call("/resolve", { body: { code: "123456" } });
  eq(r.status, 200, "status");
  const j = await r.json();
  eq(j.url, "https://abc.trycloudflare.com", "url");
});

await check("resolve unknown code -> 404", async () => {
  const r = await call("/resolve", { body: { code: "999999" } });
  eq(r.status, 404, "status");
});

await check("resolve rate limit kicks in", async () => {
  let limited = false;
  for (let i = 0; i < 40; i++) {
    const r = await call("/resolve", { body: { code: "123456" } });
    if (r.status === 429) { limited = true; break; }
  }
  if (!limited) throw new Error("never hit 429");
});

await check("health -> 200", async () => {
  const r = await call("/health", { method: "GET" });
  eq(r.status, 200, "status");
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
