#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { randomUUID } from "crypto";
import { z } from "zod";
import WebSocket from "ws";
import https from "https";
import http from "http";

const RELAY_URL = process.env.JASKETCH_RELAY_URL || "ws://localhost:9601";

// Force HTTP/1.1 for ALB compatibility (ALB doesn't support WebSocket over HTTP/2)
const wsAgent = RELAY_URL.startsWith("wss")
  ? new https.Agent({ ALPNProtocols: ["http/1.1"] })
  : new http.Agent();
const REQUEST_TIMEOUT = 10000;

// --- State ---
let ws = null;
let connected = false;
let canvasConnected = false;
const pendingRequests = new Map();

// --- Connect to relay as controller ---
function connectToRelay() {
  try {
    ws = new WebSocket(RELAY_URL, { agent: wsAgent, perMessageDeflate: false });
  } catch (e) {
    process.stderr.write(`[jasketch-mcp] Failed to create WebSocket: ${e.message}\n`);
    scheduleReconnect();
    return;
  }

  ws.on("open", () => {
    connected = true;
    process.stderr.write(`[jasketch-mcp] Connected to relay at ${RELAY_URL}\n`);
    ws.send(JSON.stringify({ role: "controller" }));
  });

  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());

      // Relay control messages
      if (msg.type === "registered") {
        canvasConnected = msg.canvasConnected || false;
        process.stderr.write(`[jasketch-mcp] Registered as controller, canvas: ${canvasConnected}\n`);
        return;
      }
      if (msg.type === "canvasConnected") {
        canvasConnected = true;
        process.stderr.write(`[jasketch-mcp] Canvas connected\n`);
        return;
      }
      if (msg.type === "canvasDisconnected") {
        canvasConnected = false;
        process.stderr.write(`[jasketch-mcp] Canvas disconnected\n`);
        return;
      }

      // Response from canvas via relay
      const pending = pendingRequests.get(msg.requestId);
      if (pending) {
        clearTimeout(pending.timeout);
        pendingRequests.delete(msg.requestId);
        if (msg.success) {
          pending.resolve(msg.data);
        } else {
          pending.reject(new Error(msg.error || "Unknown error from jasketch"));
        }
      }
    } catch (e) {
      process.stderr.write(`[jasketch-mcp] Bad message: ${e.message}\n`);
    }
  });

  ws.on("close", () => {
    connected = false;
    canvasConnected = false;
    process.stderr.write(`[jasketch-mcp] Disconnected from relay\n`);
    scheduleReconnect();
  });

  ws.on("error", () => {
    // onclose will handle reconnect
  });
}

function scheduleReconnect() {
  setTimeout(() => connectToRelay(), 3000);
}

function sendCommand(action, data = {}) {
  return new Promise((resolve, reject) => {
    if (!connected || !ws || ws.readyState !== WebSocket.OPEN) {
      reject(new Error(
        `Not connected to relay. Ensure the relay is running at ${RELAY_URL}`
      ));
      return;
    }
    if (!canvasConnected) {
      reject(new Error(
        "No canvas connected. Open jasketch.jaseci.org in a browser."
      ));
      return;
    }
    const requestId = randomUUID();
    const timeout = setTimeout(() => {
      pendingRequests.delete(requestId);
      reject(new Error("Request timed out (10s)"));
    }, REQUEST_TIMEOUT);

    pendingRequests.set(requestId, { resolve, reject, timeout });
    ws.send(JSON.stringify({ requestId, action, data }));
  });
}

// --- Element defaults ---
function applyDefaults(el) {
  const defaults = {
    color: "#000000",
    strokeWidth: 2,
    fillColor: "transparent",
    lineStyle: "solid",
    opacity: 1.0,
  };
  if (["rectangle", "circle", "diamond"].includes(el.type)) {
    el.width = el.width ?? 100;
    el.height = el.height ?? 100;
  }
  if (el.type === "text") {
    el.fontSize = el.fontSize ?? 24;
    el.fontFamily = el.fontFamily ?? "Virgil";
  }
  for (const [k, v] of Object.entries(defaults)) {
    if (el[k] === undefined) el[k] = v;
  }
  return el;
}

// --- MCP Server ---
const server = new McpServer({
  name: "jasketch",
  version: "1.0.0",
});

server.tool(
  "create_element",
  "Create a single element on the JaSketch canvas. Types: rectangle, circle, diamond, line, arrow, text, freehand.",
  {
    type: z.enum(["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand"]).describe("Element type"),
    x: z.number().optional().describe("X position (shapes/text) or x1 (lines/arrows)"),
    y: z.number().optional().describe("Y position (shapes/text) or y1 (lines/arrows)"),
    width: z.number().optional().describe("Width (shapes)"),
    height: z.number().optional().describe("Height (shapes)"),
    x1: z.number().optional().describe("Start X (lines/arrows)"),
    y1: z.number().optional().describe("Start Y (lines/arrows)"),
    x2: z.number().optional().describe("End X (lines/arrows)"),
    y2: z.number().optional().describe("End Y (lines/arrows)"),
    bendX: z.number().optional().describe("Bend control point X (lines/arrows)"),
    bendY: z.number().optional().describe("Bend control point Y (lines/arrows)"),
    color: z.string().optional().describe("Stroke color hex"),
    strokeWidth: z.number().optional().describe("Stroke width"),
    fillColor: z.string().optional().describe("Fill color hex or 'transparent'"),
    lineStyle: z.enum(["solid", "dashed", "dotted"]).optional().describe("Line style"),
    opacity: z.number().optional().describe("Opacity 0-1"),
    text: z.string().optional().describe("Text content (text elements)"),
    fontSize: z.number().optional().describe("Font size (text elements)"),
    fontFamily: z.string().optional().describe("Font family (text elements)"),
    shapeText: z.string().optional().describe("Text label inside shape"),
    shapeTextColor: z.string().optional().describe("Shape text color"),
    shapeTextFontSize: z.number().optional().describe("Shape text font size"),
    shapeTextFontFamily: z.string().optional().describe("Shape text font family"),
    groupId: z.string().optional().describe("Group ID for grouping elements"),
    points: z.array(z.object({ x: z.number(), y: z.number() })).optional().describe("Points array (freehand)"),
  },
  async (params) => {
    try {
      const element = applyDefaults({ ...params });
      const result = await sendCommand("addElement", element);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "create_elements",
  "Batch create multiple elements on the JaSketch canvas. More efficient for diagrams.",
  {
    elements: z.array(z.record(z.any())).describe("Array of element objects (same schema as create_element)"),
  },
  async ({ elements }) => {
    try {
      const processed = elements.map((el) => applyDefaults({ ...el }));
      const result = await sendCommand("addMultipleElements", { elements: processed });
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "query_elements",
  "Query elements currently on the JaSketch canvas. Optionally filter by type or index.",
  {
    type: z.enum(["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand", "image"]).optional().describe("Filter by element type"),
    index: z.number().optional().describe("Get specific element by index"),
  },
  async (params) => {
    try {
      const result = await sendCommand("getElements", params);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "update_element",
  "Update properties of an existing element by index.",
  {
    index: z.number().describe("Element index to update"),
    changes: z.record(z.any()).describe("Properties to change (e.g. {color: '#ff0000', width: 200})"),
  },
  async ({ index, changes }) => {
    try {
      const result = await sendCommand("updateElement", { index, changes });
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "delete_element",
  "Delete element(s) by index or array of indices.",
  {
    index: z.number().optional().describe("Single element index to delete"),
    indices: z.array(z.number()).optional().describe("Multiple element indices to delete"),
  },
  async ({ index, indices }) => {
    try {
      if (indices && indices.length > 0) {
        const result = await sendCommand("removeMultipleElements", { indices });
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      } else if (index !== undefined) {
        const result = await sendCommand("removeElement", { index });
        return { content: [{ type: "text", text: JSON.stringify(result) }] };
      }
      return { content: [{ type: "text", text: "Provide index or indices" }], isError: true };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

server.tool(
  "clear_canvas",
  "Clear all elements from the JaSketch canvas.",
  {},
  async () => {
    try {
      const result = await sendCommand("clearElements");
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    } catch (e) {
      return { content: [{ type: "text", text: `Error: ${e.message}` }], isError: true };
    }
  }
);

// --- Start ---
connectToRelay();
const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write(`[jasketch-mcp] MCP server running, connecting to relay at ${RELAY_URL}\n`);
