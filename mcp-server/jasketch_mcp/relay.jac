"""JaSketch WebSocket Relay Server.

Pairs MCP controllers with browser canvas clients.
Both connect as WebSocket clients to this relay.

Protocol:
  On connect, client sends: {"role": "controller"} or {"role": "canvas"}
  Controller sends commands -> relay forwards to canvas
  Canvas sends responses -> relay forwards to controller
"""

import asyncio;
import json;
import os;
import sys;

import websockets;
import from typing { Any }

glob PORT: int = int(os.environ.get("JASKETCH_RELAY_PORT", "9601"));

# Session-based pairing: session_id -> {"controller": ws, "canvas": ws}
glob sessions: dict = {};


"""Log to stderr."""
def log(msg: str) -> None {
    print(f"[relay] {msg}", file=sys.stderr, flush=True);
}


"""Handle a single WebSocket connection."""
async def handler(ws: Any) -> None {
    role: str | None = None;
    sid: str | None = None;

    try {
        async for raw in ws {
            try {
                msg: dict = json.loads(raw);

                # Registration message
                if msg.get("role") is not None and role is None {
                    role = msg["role"];
                    sid = str(msg.get("session_id", "default"));

                    if sid not in sessions {
                        sessions[sid] = {"controller": None, "canvas": None};
                    }

                    if role == "controller" {
                        sessions[sid]["controller"] = ws;
                        log(f"Controller connected (session={sid})");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "controller",
                            "session_id": sid,
                            "canvasConnected": sessions[sid]["canvas"] is not None
                        }));
                    } elif role == "canvas" {
                        sessions[sid]["canvas"] = ws;
                        log(f"Canvas connected (session={sid})");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "canvas",
                            "session_id": sid
                        }));
                        ctrl: Any = sessions[sid]["controller"];
                        if ctrl is not None {
                            try {
                                await ctrl.send(json.dumps({"type": "canvasConnected"}));
                            } except Exception {
                                _ = 0;
                            }
                        }
                    }
                    continue;
                }

                # Relay messages between roles
                if sid is None { continue; }
                session: Any = sessions[sid];

                if role == "controller" {
                    target: Any = session["canvas"];
                    if target is not None {
                        try {
                            await target.send(raw);
                        } except Exception {
                            if msg.get("requestId") is not None {
                                await ws.send(json.dumps({
                                    "requestId": msg["requestId"],
                                    "success": False,
                                    "error": "No canvas connected. Open jasketch in a browser."
                                }));
                            }
                        }
                    } elif msg.get("requestId") is not None {
                        await ws.send(json.dumps({
                            "requestId": msg["requestId"],
                            "success": False,
                            "error": "No canvas connected. Open jasketch in a browser."
                        }));
                    }
                } elif role == "canvas" {
                    ctrl2: Any = session["controller"];
                    if ctrl2 is not None {
                        try {
                            await ctrl2.send(raw);
                        } except Exception {
                            _ = 0;
                        }
                    }
                }
            } except Exception as e {
                log(f"Bad message: {e}");
            }
        }
    } except websockets.ConnectionClosed {
        _ = 0;
    }

    # Cleanup — only clear the slot this ws owns
    if sid is not None and sid in sessions {
        session2: Any = sessions[sid];
        if session2["controller"] == ws {
            session2["controller"] = None;
            log(f"Controller disconnected (session={sid})");
        } elif session2["canvas"] == ws {
            session2["canvas"] = None;
            log(f"Canvas disconnected (session={sid})");
            ctrl3: Any = session2["controller"];
            if ctrl3 is not None {
                try {
                    await ctrl3.send(json.dumps({"type": "canvasDisconnected"}));
                } except Exception {
                    _ = 0;
                }
            }
        }
        # Remove empty session
        if session2["controller"] is None and session2["canvas"] is None {
            del sessions[sid];
        }
    }
}


with entry {
    async def main() -> None {
        async with websockets.serve(handler, "0.0.0.0", PORT) {
            log(f"WebSocket relay running on port {PORT}");
            await asyncio.Future();
        }
    }

    asyncio.run(main());
}
