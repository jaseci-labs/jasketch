"""JaSketch WebSocket Relay Server - session-isolated, multi-controller.

Each browser tab registers as a canvas with a unique sessionId.
Controllers (AI agents, MCP tools) are global — they can target any session.
Commands are routed to the correct canvas via sessionId in each message.
Responses route back to the originating controller via requestId tracking.

Protocol:
  Canvas:     {"role": "canvas",      "sessionId": "<uuid>"}
  Controller: {"role": "controller"}
  Command:    {"requestId": "r1", "sessionId": "<uuid>", "action": "...", "data": {...}}
  Response:   {"requestId": "r1", "success": true, "data": {...}}

State:
  _canvases[sessionId]    = ws                              (one canvas per tab)
  _controllers            = [ws, ...]                       (all agents, global)
  _request_map[requestId] = {"ctrl": ws, "session_id": str} (response routing)
"""

import asyncio;
import json;
import os;
import re;
import sys;
import threading;

import websockets;
import from typing { Any }

glob PORT: int = int(os.environ.get("JASKETCH_RELAY_PORT", "9601"));

glob _canvases: dict = {};      # sessionId -> ws
glob _controllers: Any = [];    # [ws, ...]
glob _request_map: dict = {};   # requestId -> {"ctrl": ws, "session_id": str}


def log(msg: str) -> None {
    print(f"[relay] {msg}", file=sys.stderr, flush=True);
}

def _valid_session_id(sid: str) -> bool {
    if not sid or len(sid) > 128 { return False; }
    return bool(re.match(r'^[a-zA-Z0-9_\-]+$', sid));
}


async def handler(ws: Any) -> None {
    role: str | None = None;
    session_id: str = "";

    try {
        async for raw in ws {
            try {
                msg: dict = json.loads(raw);

                # ── Registration (first message only) ────────────────────────
                if msg.get("role") is not None and role is None {
                    role = msg["role"];

                    if role == "controller" {
                        _controllers.append(ws);
                        log(f"Controller connected ({len(_controllers)} total)");
                        sessions: Any = list(_canvases.keys());
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "controller",
                            "connectedSessions": sessions
                        }));

                    } elif role == "canvas" {
                        sid: str = msg.get("sessionId", "");
                        if not _valid_session_id(sid) {
                            await ws.send(json.dumps({
                                "type": "error",
                                "message": "Invalid or missing sessionId. Must be alphanumeric/hyphens, max 128 chars."
                            }));
                            return;
                        }
                        session_id = sid;
                        _canvases[session_id] = ws;
                        log(f"Canvas connected: session={session_id}");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "canvas",
                            "sessionId": session_id
                        }));
                        # Notify all controllers that this canvas is ready
                        dead_ctrls: list = [];
                        for ctrl in _controllers {
                            try { await ctrl.send(json.dumps({"type": "canvasConnected", "sessionId": session_id})); }
                            except Exception { dead_ctrls.append(ctrl); }
                        }
                        # Prune dead controllers
                        for ctrl in dead_ctrls {
                            if ctrl in _controllers { _controllers.remove(ctrl); }
                            dead_reqs: list = [rid for (rid, e) in list(_request_map.items()) if e["ctrl"] is ctrl];
                            for rid in dead_reqs { _request_map.pop(rid, None); }
                        }
                    }
                    continue;
                }

                # ── Controller → Canvas ───────────────────────────────────────
                if role == "controller" {
                    rid: str = msg.get("requestId", "");
                    target_sid: str = msg.get("sessionId", "");

                    if not _valid_session_id(target_sid) {
                        if rid {
                            await ws.send(json.dumps({
                                "requestId": rid, "success": False,
                                "error": "Command missing valid sessionId."
                            }));
                        }
                        continue;
                    }

                    if rid { _request_map[rid] = {"ctrl": ws, "session_id": target_sid}; }

                    canvas_ws: Any = _canvases.get(target_sid);
                    if canvas_ws is not None {
                        try { await canvas_ws.send(raw); }
                        except Exception {
                            if rid {
                                _request_map.pop(rid, None);
                                await ws.send(json.dumps({
                                    "requestId": rid, "success": False, "error": "Canvas send failed."
                                }));
                            }
                        }
                    } elif rid {
                        _request_map.pop(rid, None);
                        await ws.send(json.dumps({
                            "requestId": rid, "success": False,
                            "error": f"No canvas for session '{target_sid}'. Open JaSketch in browser."
                        }));
                    }

                # ── Canvas → Controller (response keyed by requestId) ─────────
                } elif role == "canvas" {
                    rid: str = msg.get("requestId", "");
                    if rid {
                        entry: Any = _request_map.pop(rid, None);
                        if entry is not None {
                            ctrl_ws: Any = entry["ctrl"];
                            try { await ctrl_ws.send(raw); }
                            except Exception { _ = 0; }
                        }
                    }
                }

            } except Exception as e { log(f"Bad message: {e}"); }
        }
    } except Exception { _ = 0; }

    # ── Cleanup on disconnect ─────────────────────────────────────────────────
    if role == "canvas" and session_id and _canvases.get(session_id) is ws {
        _canvases.pop(session_id, None);
        log(f"Canvas disconnected: session={session_id}");

        # Actively fail all pending requests targeting this session
        dead: Any = [];
        items: Any = list(_request_map.items());
        for (rid_key, entry_val) in items {
            ev: Any = entry_val;
            if ev["session_id"] == session_id { dead.append(rid_key); }
        }
        for dead_rid in dead {
            dead_entry: Any = _request_map.pop(dead_rid, None);
            if dead_entry is not None {
                ctrl_ws: Any = dead_entry["ctrl"];
                try {
                    await ctrl_ws.send(json.dumps({
                        "requestId": dead_rid, "success": False,
                        "error": "Canvas disconnected."
                    }));
                } except Exception { _ = 0; }
            }
        }

        # Notify all controllers, prune dead ones
        dead_ctrls: list = [];
        for ctrl in _controllers {
            try { await ctrl.send(json.dumps({"type": "canvasDisconnected", "sessionId": session_id})); }
            except Exception { dead_ctrls.append(ctrl); }
        }
        for ctrl in dead_ctrls {
            if ctrl in _controllers { _controllers.remove(ctrl); }
            dead_reqs: list = [rid for (rid, e) in list(_request_map.items()) if e["ctrl"] is ctrl];
            for rid in dead_reqs { _request_map.pop(rid, None); }
        }

    } elif role == "controller" {
        if ws in _controllers { _controllers.remove(ws); }
        log(f"Controller disconnected ({len(_controllers)} remaining)");

        # Release pending requests from this controller (no error response needed — controller is gone)
        dead: Any = [];
        items: Any = list(_request_map.items());
        for (rid_key, entry_val) in items {
            ev: Any = entry_val;
            if ev["ctrl"] is ws { dead.append(rid_key); }
        }
        for dead_rid in dead { _request_map.pop(dead_rid, None); }
    }
}


"""Start relay in a background daemon thread. Blocks until the port is listening."""
def start_relay_server() -> None {
    ready: Any = threading.Event();

    def _thread() -> None {
        loop: Any = asyncio.new_event_loop();
        asyncio.set_event_loop(loop);
        async def _start() {
            _srv: Any = await websockets.serve(handler, "0.0.0.0", PORT);
            log(f"WebSocket relay running on port {PORT}");
            ready.set();
            await asyncio.Future();
        }
        loop.run_until_complete(_start());
    }

    threading.Thread(target=_thread, daemon=True).start();
    ready.wait(timeout=5);
}


