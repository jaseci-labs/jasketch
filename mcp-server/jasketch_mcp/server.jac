"""JaSketch MCP Server - embeds relay + connects to canvas automatically."""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import websockets;
import from websockets { serve }
import from mcp.server.fastmcp { FastMCP }
import from typing { Any }

glob RELAY_PORT: int = int(os.environ.get("JASKETCH_RELAY_PORT", "9601"));
glob RELAY_URL: str = os.environ.get("JASKETCH_RELAY_URL", "wss://jasketch.jaseci.org/ws");
glob REQUEST_TIMEOUT: float = 40.0;
glob _is_remote_relay: bool = "localhost" not in RELAY_URL and "127.0.0.1" not in RELAY_URL;

# HTTP transport config (used when JASKETCH_MCP_TRANSPORT=streamable-http)
glob MCP_TRANSPORT: str = os.environ.get("JASKETCH_MCP_TRANSPORT", "stdio");
glob MCP_PORT: int = int(os.environ.get("JASKETCH_MCP_PORT", "3003"));
glob MCP_HOST: str = os.environ.get("JASKETCH_MCP_HOST", "0.0.0.0");

# Thread-safe state
glob _lock: Any = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _canvas_connected: bool = False;
glob _pending: dict = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();

# Relay state
glob _relay_controller: Any = None;
glob _relay_canvas: Any = None;

glob mcp: FastMCP = FastMCP("jasketch", host=MCP_HOST, port=MCP_PORT, streamable_http_path="/mcp/");


"""Log to stderr (stdout is reserved for MCP stdio transport)."""
def log(msg: str) -> None {
    print(f"[jasketch-mcp] {msg}", file=sys.stderr, flush=True);
}


# --- Embedded WebSocket relay ---

"""Handle a single WebSocket connection to the relay."""
async def _relay_handler(ws: Any) -> None {
    global _relay_controller, _relay_canvas;
    role: str | None = None;

    try {
        async for raw in ws {
            try {
                msg: dict = json.loads(raw);

                # Registration
                if msg.get("role") is not None and role is None {
                    role = msg["role"];

                    if role == "controller" {
                        _relay_controller = ws;
                        log("Relay: controller connected");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "controller",
                            "canvasConnected": _relay_canvas is not None
                        }));
                    } elif role == "canvas" {
                        _relay_canvas = ws;
                        log("Relay: canvas connected");
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "canvas"
                        }));
                        if _relay_controller is not None {
                            try {
                                await _relay_controller.send(json.dumps({
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
                if role == "controller" and _relay_canvas is not None {
                    try {
                        await _relay_canvas.send(raw);
                    } except Exception {
                        if msg.get("requestId") is not None {
                            await ws.send(json.dumps({
                                "requestId": msg["requestId"],
                                "success": False,
                                "error": "No canvas connected. Open jasketch in a browser."
                            }));
                        }
                    }
                } elif role == "canvas" and _relay_controller is not None {
                    try {
                        await _relay_controller.send(raw);
                    } except Exception {
                        _ = 0;
                    }
                } elif role == "controller" {
                    if msg.get("requestId") is not None {
                        await ws.send(json.dumps({
                            "requestId": msg["requestId"],
                            "success": False,
                            "error": "No canvas connected. Open jasketch in a browser."
                        }));
                    }
                }
            } except Exception as e {
                log(f"Relay: bad message: {e}");
            }
        }
    } except websockets.ConnectionClosed {
        _ = 0;
    }

    # Cleanup on disconnect
    if ws == _relay_controller {
        _relay_controller = None;
        log("Relay: controller disconnected");
    } elif ws == _relay_canvas {
        _relay_canvas = None;
        log("Relay: canvas disconnected");
        if _relay_controller is not None {
            try {
                await _relay_controller.send(json.dumps({
                    "type": "canvasDisconnected"
                }));
            } except Exception {
                _ = 0;
            }
        }
    }
}


# --- MCP controller WebSocket connection ---

"""Connect to relay as controller, handle responses."""
async def _connect_to_relay() -> None {
    global _ws, _connected, _canvas_connected;

    while True {
        try {
            async with websockets.connect(RELAY_URL, compression=None) as ws {
                _ws = ws;
                _connected = True;
                log(f"Connected to relay at {RELAY_URL}");
                await ws.send(json.dumps({"role": "controller"}));

                async for raw in ws {
                    try {
                        msg: dict = json.loads(raw);
                        msg_type: str = msg.get("type", "");

                        if msg_type == "registered" {
                            _canvas_connected = bool(msg.get("canvasConnected", False));
                            log(f"Registered as controller, canvas: {_canvas_connected}");
                            continue;
                        }
                        if msg_type == "canvasConnected" {
                            _canvas_connected = True;
                            log("Canvas connected");
                            continue;
                        }
                        if msg_type == "canvasDisconnected" {
                            _canvas_connected = False;
                            log("Canvas disconnected");
                            continue;
                        }

                        # Response from canvas
                        request_id: str = msg.get("requestId", "");
                        entry: Any = None;
                        with _lock {
                            entry = _pending.pop(request_id, None);
                        }
                        if entry is not None {
                            (evt, res) = entry;
                            if msg.get("success") {
                                res["data"] = msg.get("data");
                            } else {
                                res["error"] = msg.get("error", "Unknown error from jasketch");
                            }
                            evt.set();
                        }
                    } except Exception as e {
                        log(f"Bad message: {e}");
                    }
                }
            }
        } except Exception as e {
            log(f"Relay connection error: {e}");
        }

        _ws = None;
        _connected = False;
        _canvas_connected = False;
        log("Disconnected from relay, reconnecting in 3s...");
        await asyncio.sleep(3);
    }
}


"""Run embedded relay (if local) + controller connection in a dedicated thread."""
def _start_relay_thread() -> None {
    global _relay_loop;
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();

    async def _run_local() -> None {
        # Start embedded relay server, then connect as controller
        async with serve(_relay_handler, "0.0.0.0", RELAY_PORT) {
            log(f"Embedded relay running on port {RELAY_PORT}");
            await _connect_to_relay();
        }
    }

    if _is_remote_relay {
        log(f"Remote relay mode — connecting directly to {RELAY_URL}");
        _relay_loop.run_until_complete(_connect_to_relay());
    } else {
        _relay_loop.run_until_complete(_run_local());
    }
}


"""Send a command to the canvas via relay (blocking, thread-safe)."""
def _send_command(action: str, data: dict | None = None) -> Any {
    if (not _connected) or (_ws is None) {
        raise Exception(
            f"Not connected to relay. Ensure the relay is running at {RELAY_URL}"
        );
    }
    if not _canvas_connected {
        raise Exception(
            "No canvas connected. Open jasketch in a browser."
        );
    }
    if not _relay_ready.wait(timeout=5) {
        raise Exception("Relay event loop not ready");
    }

    request_id: str = str(uuid.uuid4());
    evt: Any = threading.Event();
    res: dict = {};

    with _lock {
        _pending[request_id] = (evt, res);
    }

    payload: str = json.dumps({
        "requestId": request_id,
        "action": action,
        "data": data if data is not None else {}
    });

    try {
        future: Any = asyncio.run_coroutine_threadsafe(_ws.send(payload), _relay_loop);
        future.result(timeout=5);
    } except Exception as e {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Failed to send command: {e}");
    }

    if not evt.wait(timeout=REQUEST_TIMEOUT) {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception("Request timed out (10s)");
    }

    if "error" in res {
        raise Exception(res["error"]);
    }
    return res.get("data");
}


# --- Element defaults ---

"""Apply default styling to an element."""
def _apply_defaults(el: dict) -> dict {
    defaults: dict = {
        "color": "#000000",
        "strokeWidth": 2,
        "fillColor": "transparent",
        "lineStyle": "solid",
        "opacity": 1.0
    };
    if el.get("type") in ("rectangle", "circle", "diamond") {
        el.setdefault("width", 100);
        el.setdefault("height", 100);
    }
    if el.get("type") == "text" {
        el.setdefault("fontSize", 24);
        el.setdefault("fontFamily", "Virgil");
    }
    for (k, v) in defaults.items() {
        el.setdefault(k, v);
    }
    return el;
}


# --- MCP Tools ---

"""Create a single element on the JaSketch canvas. Types: rectangle, circle, diamond, line, arrow, text, freehand."""
@mcp.tool()
async def create_element(
    type: str,
    x: float | None = None,
    y: float | None = None,
    width: float | None = None,
    height: float | None = None,
    x1: float | None = None,
    y1: float | None = None,
    x2: float | None = None,
    y2: float | None = None,
    bendX: float | None = None,
    bendY: float | None = None,
    color: str | None = None,
    strokeWidth: float | None = None,
    fillColor: str | None = None,
    lineStyle: str | None = None,
    opacity: float | None = None,
    text: str | None = None,
    fontSize: float | None = None,
    fontFamily: str | None = None,
    shapeText: str | None = None,
    shapeTextColor: str | None = None,
    shapeTextFontSize: float | None = None,
    shapeTextFontFamily: str | None = None,
    groupId: str | None = None,
    points: list[dict] | None = None
) -> str {
    element: dict = {"type": type};
    params: dict = {
        "x": x, "y": y, "width": width, "height": height,
        "x1": x1, "y1": y1, "x2": x2, "y2": y2,
        "bendX": bendX, "bendY": bendY,
        "color": color, "strokeWidth": strokeWidth,
        "fillColor": fillColor, "lineStyle": lineStyle, "opacity": opacity,
        "text": text, "fontSize": fontSize, "fontFamily": fontFamily,
        "shapeText": shapeText, "shapeTextColor": shapeTextColor,
        "shapeTextFontSize": shapeTextFontSize, "shapeTextFontFamily": shapeTextFontFamily,
        "groupId": groupId, "points": points
    };
    for (k, v) in params.items() {
        if v is not None {
            element[k] = v;
        }
    }
    element = _apply_defaults(element);
    result: Any = await asyncio.to_thread(_send_command, "addElement", element);
    return json.dumps(result);
}


"""Batch create multiple elements on the JaSketch canvas. More efficient for diagrams."""
@mcp.tool()
async def create_elements(elements: list[dict]) -> str {
    processed: list = [_apply_defaults(dict(el)) for el in elements];
    result: Any = await asyncio.to_thread(
        _send_command, "addMultipleElements", {"elements": processed}
    );
    return json.dumps(result);
}


"""Query elements currently on the JaSketch canvas. Optionally filter by type or index."""
@mcp.tool()
async def query_elements(
    type: str | None = None,
    index: int | None = None
) -> str {
    params: dict = {};
    if type is not None {
        params["type"] = type;
    }
    if index is not None {
        params["index"] = index;
    }
    result: Any = await asyncio.to_thread(_send_command, "getElements", params);
    return json.dumps(result);
}


"""Update properties of an existing element by index."""
@mcp.tool()
async def update_element(index: int, changes: dict) -> str {
    result: Any = await asyncio.to_thread(
        _send_command, "updateElement", {"index": index, "changes": changes}
    );
    return json.dumps(result);
}


"""Delete element(s) by index or array of indices."""
@mcp.tool()
async def delete_element(
    index: int | None = None,
    indices: list[int] | None = None
) -> str {
    result: Any = None;
    if indices is not None and len(indices) > 0 {
        result = await asyncio.to_thread(
            _send_command, "removeMultipleElements", {"indices": indices}
        );
    } elif index is not None {
        result = await asyncio.to_thread(
            _send_command, "removeElement", {"index": index}
        );
    } else {
        return "Error: Provide index or indices";
    }
    return json.dumps(result);
}


"""Clear all elements from the JaSketch canvas."""
@mcp.tool()
async def clear_canvas() -> str {
    result: Any = await asyncio.to_thread(_send_command, "clearElements");
    return json.dumps(result);
}


"""Get the current viewport state: zoom level, pan offset, canvas dimensions, and visible area in world coordinates."""
@mcp.tool()
async def get_viewport() -> str {
    result: Any = await asyncio.to_thread(_send_command, "getViewport");
    return json.dumps(result);
}


"""Get a PNG screenshot of the current canvas as a base64 data URL. Use this to visually verify what has been drawn."""
@mcp.tool()
async def get_canvas_snapshot() -> str {
    result: Any = await asyncio.to_thread(_send_command, "getCanvasSnapshot");
    return json.dumps(result);
}


"""Get the bounding box of all elements on the canvas. Useful for layout planning and finding free space."""
@mcp.tool()
async def get_bounding_box() -> str {
    result: Any = await asyncio.to_thread(_send_command, "getBoundingBox");
    return json.dumps(result);
}


# --- Start server ---

with entry {
    if _is_remote_relay {
        log(f"Starting MCP server (remote relay: {RELAY_URL})");
    } else {
        log(f"Starting MCP server with embedded relay on port {RELAY_PORT}");
    }

    relay_thread: Any = threading.Thread(target=_start_relay_thread, daemon=True);
    relay_thread.start();

    # Give relay/connection a moment to start before MCP begins accepting tools
    _relay_ready.wait(timeout=5);

    if MCP_TRANSPORT == "streamable-http" {
        log(f"Running MCP server with streamable-http transport on port {MCP_PORT}");
        mcp.run(transport="streamable-http");
    } else {
        mcp.run(transport="stdio");
    }
}
