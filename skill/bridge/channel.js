#!/usr/bin/env node
// claude-watch-anywhere — official Channels integration.
//
// This is a Claude Code *channel*: an MCP server that Claude Code spawns over
// stdio. It is the sanctioned, supported way to push messages INTO a live
// session and let Claude reply back out — the piece the hook bridge could not
// do cleanly (hooks are one-way observability).
//
// Responsibility split (hybrid design — see AGENTS.md):
//   • hooks      → live tool output + permission relay  (already working)
//   • channel.js → inject voice/remote prompts into the live session + replies
//
// It talks to the long-running bridge (server.js) over localhost HTTP:
//   GET  /channel/inbox  (long-poll) → prompts the watch queued via /command
//   POST /channel/reply               → Claude's reply, forwarded to the watch
//
// Register it in MCP config (see setup-hooks.sh) and start Claude with:
//   claude --dangerously-load-development-channels server:claudewatch
// (Custom channels need that flag during the research preview.)

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { ListToolsRequestSchema, CallToolRequestSchema } from "@modelcontextprotocol/sdk/types.js";

const BRIDGE = process.env.CLAUDE_WATCH_BRIDGE || "http://127.0.0.1:7860";

// stderr only — stdout is the MCP stdio transport and must stay clean.
const log = (...a) => process.stderr.write(`[channel] ${a.join(" ")}\n`);

const mcp = new Server(
  { name: "claudewatch", version: "1.0.0" },
  {
    capabilities: {
      experimental: { "claude/channel": {} }, // registers the channel listener
      tools: {}, // for the reply tool
    },
    instructions:
      'Messages from the Claude Watch app arrive as <channel source="claudewatch">. ' +
      "Treat each as a user instruction and act on it in this session. " +
      "When you finish or need to tell the user something, call the watch_reply tool " +
      "so your message reaches their wrist.",
  },
);

// --- reply tool: Claude → watch --------------------------------------------
mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "watch_reply",
      description: "Send a short status message back to the Claude Watch app.",
      inputSchema: {
        type: "object",
        properties: { text: { type: "string", description: "Message for the watch" } },
        required: ["text"],
      },
    },
  ],
}));

mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name === "watch_reply") {
    const { text } = req.params.arguments ?? {};
    try {
      await fetch(`${BRIDGE}/channel/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });
      return { content: [{ type: "text", text: "sent to watch" }] };
    } catch (err) {
      return { content: [{ type: "text", text: `watch unreachable: ${err.message}` }], isError: true };
    }
  }
  throw new Error(`unknown tool: ${req.params.name}`);
});

await mcp.connect(new StdioServerTransport());
log(`connected. bridge=${BRIDGE}`);

// --- inbound: watch → Claude (long-poll the bridge) ------------------------
let stopped = false;
async function pump() {
  while (!stopped) {
    try {
      const r = await fetch(`${BRIDGE}/channel/inbox`, { method: "GET" });
      if (!r.ok) {
        await sleep(2000);
        continue;
      }
      const { prompts = [] } = await r.json();
      for (const p of prompts) {
        const text = (p?.text ?? "").toString().trim();
        if (!text) continue;
        await mcp.notification({
          method: "notifications/claude/channel",
          params: { content: text, meta: { source: "claudewatch" } },
        });
        log(`injected: ${text.slice(0, 60)}`);
      }
    } catch (err) {
      // bridge not up yet, or long-poll timed out — back off briefly and retry
      await sleep(1500);
    }
  }
}

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
process.on("SIGINT", () => { stopped = true; process.exit(0); });
process.on("SIGTERM", () => { stopped = true; process.exit(0); });
pump();
