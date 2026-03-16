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

# Simple pairing: one controller <-> one canvas
glob controller: Any = None;
glob canvas: Any = None;


"""Log to stderr."""
def log(msg: str) -> None {
    print(f"[relay] {msg}", file=sys.stderr, flush=True);
}


"""Handle a single WebSocket connection."""
async def handler(ws: Any) -> None {
    global controller, canvas;
    role: str | None = None;

    try {
        async for raw in ws {
            try {
                msg: dict = json.loads(raw);

                # Registration message
                if msg.get("role") is not None and role is None {
                    role = msg["role"];

                    if role == "controller" {
                        controller = ws;
                        log("Controller connected");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "controller",
                            "canvasConnected": canvas is not None
                        }));
                    } elif role == "canvas" {
                        canvas = ws;
                        log("Canvas connected");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "canvas"
                        }));
                        # Notify controller that canvas is available
                        if controller is not None {
                            try {
                                await controller.send(json.dumps({
                                    "type": "canvasConnected"
                                }));
                            } except Exception {
                                _ = 0;
                            }
                        }
                    }
                    continue;
                }

                # Relay messages between controller and canvas
                if role == "controller" and canvas is not None {
                    try {
                        await canvas.send(raw);
                    } except Exception {
                        if msg.get("requestId") is not None {
                            await ws.send(json.dumps({
                                "requestId": msg["requestId"],
                                "success": False,
                                "error": "No canvas connected. Open jasketch in a browser."
                            }));
                        }
                    }
                } elif role == "canvas" and controller is not None {
                    try {
                        await controller.send(raw);
                    } except Exception {
                        _ = 0;
                    }
                } elif role == "controller" {
                    # Canvas not connected, send error back
                    if msg.get("requestId") is not None {
                        await ws.send(json.dumps({
                            "requestId": msg["requestId"],
                            "success": False,
                            "error": "No canvas connected. Open jasketch in a browser."
                        }));
                    }
                }
            } except Exception as e {
                log(f"Bad message: {e}");
            }
        }
    } except websockets.ConnectionClosed {
        _ = 0;
    }

    # Cleanup on disconnect
    if ws == controller {
        controller = None;
        log("Controller disconnected");
    } elif ws == canvas {
        canvas = None;
        log("Canvas disconnected");
        # Notify controller
        if controller is not None {
            try {
                await controller.send(json.dumps({
                    "type": "canvasDisconnected"
                }));
            } except Exception {
                _ = 0;
            }
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
