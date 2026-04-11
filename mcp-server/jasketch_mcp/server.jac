"""JaSketch MCP Server - connects to infra relay as a controller."""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import websockets;
import from mcp.server.fastmcp { FastMCP }
import from typing { Any }

glob RELAY_URL: str = os.environ.get("JASKETCH_RELAY_URL", "ws://localhost:9601");
glob REQUEST_TIMEOUT: float = 40.0;

# HTTP transport config (used when JASKETCH_MCP_TRANSPORT=streamable-http)
glob MCP_TRANSPORT: str = os.environ.get("JASKETCH_MCP_TRANSPORT", "stdio");
glob MCP_PORT: int = int(os.environ.get("JASKETCH_MCP_PORT", "3003"));
glob MCP_HOST: str = os.environ.get("JASKETCH_MCP_HOST", "0.0.0.0");

# Thread-safe state
glob _lock = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _canvas_sessions: Any = set();
glob _pending: dict = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();

glob mcp: FastMCP = FastMCP("jasketch", host=MCP_HOST, port=MCP_PORT, streamable_http_path="/mcp/");


"""Log to stderr (stdout is reserved for MCP stdio transport)."""
def log(msg: str) -> None {
    print(f"[jasketch-mcp] {msg}", file=sys.stderr, flush=True);
}


# --- MCP controller WebSocket connection ---

"""Connect to relay as controller, handle responses."""
async def _connect_to_relay() -> None {
    global _ws, _connected, _canvas_sessions;

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
                            existing: list = msg.get("connectedSessions", []);
                            count: int = 0;
                            with _lock {
                                for sid in existing { _canvas_sessions.add(sid); }
                                count = len(_canvas_sessions);
                            }
                            log(f"Registered as controller, {count} canvas(es) connected");
                            continue;
                        }
                        if msg_type == "canvasConnected" {
                            session_id: Any = msg.get("sessionId");
                            if not isinstance(session_id, str) or not session_id {
                                log(f"Ignoring canvasConnected: invalid sessionId (expected non-empty string, got {type(session_id).__name__})");
                                continue;
                            }
                            count: int = 0;
                            with _lock {
                                _canvas_sessions.add(session_id);
                                count = len(_canvas_sessions);
                            }
                            log(f"Canvas connected: {count} total");
                            continue;
                        }
                        if msg_type == "canvasDisconnected" {
                            session_id: Any = msg.get("sessionId");
                            if not isinstance(session_id, str) or not session_id {
                                log(f"Ignoring canvasDisconnected: invalid sessionId (expected non-empty string, got {type(session_id).__name__})");
                                continue;
                            }
                            count: int = 0;
                            with _lock {
                                _canvas_sessions.discard(session_id);
                                count = len(_canvas_sessions);
                            }
                            log(f"Canvas disconnected: {count} remaining");
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
        with _lock {
            _canvas_sessions.clear();
        }
        log("Disconnected from relay, reconnecting in 3s...");
        await asyncio.sleep(3);
    }
}


"""Run relay connection in a dedicated thread."""
def _start_relay_thread() -> None {
    global _relay_loop;
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();
    _relay_loop.run_until_complete(_connect_to_relay());
}


"""Resolve session ID — use explicit param, env var, or auto-select if only one canvas."""
def _resolve_session(session_id: str = "") -> str {
    sid: str = session_id or os.environ.get("JASKETCH_SESSION_ID", "");
    if sid { return sid; }
    with _lock {
        session_count: int = len(_canvas_sessions);
        if session_count == 1 { return next(iter(_canvas_sessions)); }
        if session_count == 0 { raise Exception("No canvas connected. Open JaSketch in browser."); }
    }
    raise Exception(f"Multiple canvases open. Set JASKETCH_SESSION_ID env var to select one.");
}


"""Send a command to the canvas via relay (blocking, thread-safe)."""
def _send_command(action: str, data: dict | None = None, session_id: str = "", timeout: float | None = None) -> Any {
    if (not _connected) or (_ws is None) {
        raise Exception(
            f"Not connected to relay. Ensure the relay is running at {RELAY_URL}"
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
        "sessionId": session_id,
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

    effective_timeout: float = timeout if timeout is not None else REQUEST_TIMEOUT;
    if not evt.wait(timeout=effective_timeout) {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Request timed out ({effective_timeout}s)");
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
    points: list[dict] | None = None,
    session_id: str | None = None
) -> str {
    sid: str = _resolve_session(session_id or "");
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
    result: Any = await asyncio.to_thread(_send_command, "addElement", element, sid);
    return json.dumps(result);
}


"""Batch create multiple elements on the JaSketch canvas. More efficient for diagrams."""
@mcp.tool()
async def create_elements(elements: list[dict], session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    processed: list = [_apply_defaults(dict(el)) for el in elements];
    result: Any = await asyncio.to_thread(
        _send_command, "addMultipleElements", {"elements": processed}, sid
    );
    return json.dumps(result);
}


"""Query elements currently on the JaSketch canvas. Optionally filter by type or index."""
@mcp.tool()
async def query_elements(
    type: str | None = None,
    index: int | None = None,
    session_id: str | None = None
) -> str {
    sid: str = _resolve_session(session_id or "");
    params: dict = {};
    if type is not None {
        params["type"] = type;
    }
    if index is not None {
        params["index"] = index;
    }
    result: Any = await asyncio.to_thread(_send_command, "getElements", params, sid);
    return json.dumps(result);
}


"""Update properties of an existing element by index."""
@mcp.tool()
async def update_element(index: int, changes: dict, session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = await asyncio.to_thread(
        _send_command, "updateElement", {"index": index, "changes": changes}, sid
    );
    return json.dumps(result);
}


"""Delete element(s) by index or array of indices."""
@mcp.tool()
async def delete_element(
    index: int | None = None,
    indices: list[int] | None = None,
    session_id: str | None = None
) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = None;
    if indices is not None and len(indices) > 0 {
        result = await asyncio.to_thread(
            _send_command, "removeMultipleElements", {"indices": indices}, sid
        );
    } elif index is not None {
        result = await asyncio.to_thread(
            _send_command, "removeElement", {"index": index}, sid
        );
    } else {
        return "Error: Provide index or indices";
    }
    return json.dumps(result);
}


"""Clear all elements from the JaSketch canvas."""
@mcp.tool()
async def clear_canvas(session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = await asyncio.to_thread(_send_command, "clearElements", None, sid);
    return json.dumps(result);
}


"""Get the current viewport state: zoom level, pan offset, canvas dimensions, and visible area in world coordinates."""
@mcp.tool()
async def get_viewport(session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = await asyncio.to_thread(_send_command, "getViewport", None, sid);
    return json.dumps(result);
}


"""Get a JPEG screenshot of the current canvas as a base64 data URL. Use this to visually verify what has been drawn."""
@mcp.tool()
async def get_canvas_snapshot(session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = await asyncio.to_thread(_send_command, "getCanvasSnapshot", None, sid, 40);
    return json.dumps(result);
}


"""Get the bounding box of all elements on the canvas. Useful for layout planning and finding free space."""
@mcp.tool()
async def get_bounding_box(session_id: str | None = None) -> str {
    sid: str = _resolve_session(session_id or "");
    result: Any = await asyncio.to_thread(_send_command, "getBoundingBox", None, sid);
    return json.dumps(result);
}


# --- Start server ---

with entry {
    log(f"Starting MCP server, relay at {RELAY_URL}");

    relay_thread: Any = threading.Thread(target=_start_relay_thread, daemon=True);
    relay_thread.start();

    # Give relay connection a moment to start before MCP begins accepting tools
    _relay_ready.wait(timeout=5);

    if MCP_TRANSPORT == "streamable-http" {
        log(f"Running MCP server with streamable-http transport on port {MCP_PORT}");
        mcp.run(transport="streamable-http");
    } else {
        mcp.run(transport="stdio");
    }
}
