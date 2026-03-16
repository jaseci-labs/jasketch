#!/usr/bin/env node

/**
 * JaSketch WebSocket Relay Server
 *
 * Pairs MCP controllers with browser canvas clients.
 * Both connect as WebSocket clients to this relay.
 *
 * Protocol:
 *   On connect, client sends: {"role": "controller"} or {"role": "canvas"}
 *   Controller sends commands -> relay forwards to canvas
 *   Canvas sends responses -> relay forwards to controller
 */

import { WebSocketServer } from "ws";

const PORT = parseInt(process.env.JASKETCH_RELAY_PORT || "9601");

const wss = new WebSocketServer({ port: PORT });

// Simple pairing: one controller <-> one canvas (extend later for multi-session)
let controller = null;
let canvas = null;

wss.on("connection", (ws) => {
  let role = null;

  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());

      // Registration message
      if (msg.role && !role) {
        role = msg.role;
        if (role === "controller") {
          controller = ws;
          console.log("[relay] Controller connected");
          ws.send(JSON.stringify({ type: "registered", role: "controller", canvasConnected: canvas !== null }));
        } else if (role === "canvas") {
          canvas = ws;
          console.log("[relay] Canvas connected");
          ws.send(JSON.stringify({ type: "registered", role: "canvas" }));
          // Notify controller that canvas is available
          if (controller && controller.readyState === 1) {
            controller.send(JSON.stringify({ type: "canvasConnected" }));
          }
        }
        return;
      }

      // Relay messages between controller and canvas
      if (role === "controller" && canvas && canvas.readyState === 1) {
        canvas.send(data.toString());
      } else if (role === "canvas" && controller && controller.readyState === 1) {
        controller.send(data.toString());
      } else if (role === "controller" && (!canvas || canvas.readyState !== 1)) {
        // Canvas not connected, send error back
        if (msg.requestId) {
          ws.send(JSON.stringify({
            requestId: msg.requestId,
            success: false,
            error: "No canvas connected. Open jasketch.jaseci.org in a browser."
          }));
        }
      }
    } catch (e) {
      console.error("[relay] Bad message:", e.message);
    }
  });

  ws.on("close", () => {
    if (ws === controller) {
      controller = null;
      console.log("[relay] Controller disconnected");
    } else if (ws === canvas) {
      canvas = null;
      console.log("[relay] Canvas disconnected");
      // Notify controller
      if (controller && controller.readyState === 1) {
        controller.send(JSON.stringify({ type: "canvasDisconnected" }));
      }
    }
  });
});

console.log(`[relay] WebSocket relay running on port ${PORT}`);
