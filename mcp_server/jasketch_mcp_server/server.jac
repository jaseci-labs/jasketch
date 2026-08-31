"""JaSketch MCP Server - connects to infra relay as a controller.

Tool logic lives in canvas_tool_provider.jac (CanvasToolProvider).
This file owns relay connection, session resolution, and thin @mcp.tool() wrappers.
"""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import websockets;
import from mcp.server.fastmcp { FastMCP }
import from typing { Any }
# Absolute, not relative: `jac run jasketch_mcp_server/server.jac` from mcp_server/
# loads the file without a parent package, and a relative import dies there with
# "attempted relative import with no known parent package". Absolute resolves
# both that way and from inside the installed wheel.
import from jasketch_mcp_server.canvas_tools { CanvasToolProvider }

# The relay is an endpoint of the app itself now (infrastructure/relay.jac), not
# a separate server: one origin, one port, no bespoke ingress.
glob RELAY_URL: str = os.environ.get(
    "JASKETCH_RELAY_URL", "wss://jasketch.jaseci.org/ws/function/jasketch_relay"
);
glob REQUEST_TIMEOUT: float = 40.0;

# HTTP transport config (used when JASKETCH_MCP_TRANSPORT=streamable-http)
glob MCP_TRANSPORT: str = os.environ.get("JASKETCH_MCP_TRANSPORT", "stdio");
glob MCP_PORT: int = int(os.environ.get("JASKETCH_MCP_PORT", "3003"));
glob MCP_HOST: str = os.environ.get("JASKETCH_MCP_HOST", "0.0.0.0");

# Thread-safe relay state
glob _lock = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _canvas_sessions: Any = set();
glob _pending: dict[str, tuple[Any, dict]] = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();
# Set when the socket is actually OPEN, which is a different moment from
# _relay_ready (that one only says the event loop exists). Without it the first
# tool call after startup races the handshake and fails with "Not connected".
glob _relay_connected: Any = threading.Event();
# How long a tool call waits for the relay before giving up. Generous: an
# assistant issuing its first command right after launch should wait, not fail.
glob CONNECT_WAIT_SECONDS: float = 15.0;

glob mcp: FastMCP = FastMCP("jasketch", host=MCP_HOST, port=MCP_PORT, streamable_http_path="/mcp/");


def log(msg: str) -> None {
    print(f"[jasketch-mcp] {msg}", file=sys.stderr, flush=True);
}


# ── Relay connection ──────────────────────────────────────────────────────────

async def _connect_to_relay() -> None {

    while True {
        try {
            async with websockets.connect(RELAY_URL, compression=None) as ws {
                _ws = ws;
                _connected = True;
                _relay_connected.set();
                log(f"Connected to relay at {RELAY_URL}");

                # websockets' ClientConnection IS async-iterable; the bundled stub
                # does not model __aiter__.
                async for raw in ws {  # jac:ignore[E1022]
                    try {
                        # The relay is a broadcast endpoint: it wraps each yielded
                        # envelope as {ok, type:"chunk", data}, and every client
                        # sees every envelope. Ours are the responses whose
                        # request_id is in _pending.
                        envelope: dict = json.loads(str(raw));
                        if envelope.get("type") != "chunk" {
                            continue;
                        }
                        msg: dict = envelope.get("data") or {};
                        if msg.get("kind") != "response" {
                            continue;
                        }

                        request_id: str = msg.get("request_id", "");
                        entry: tuple[Any, dict] | None = None;
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
                    } except Exception as error {
                        log(f"Bad message: {error}");
                    }
                }
            }
        } except Exception as error {
            log(f"Relay connection error: {error}");
        }

        _ws = None;
        _connected = False;
        _relay_connected.clear();
        log("Disconnected from relay, reconnecting in 3s...");
        await asyncio.sleep(3);
    }
}


def _start_relay_thread() -> None {
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();
    _relay_loop.run_until_complete(_connect_to_relay());
}


"""Resolve the target canvas. Explicit param first, then $JASKETCH_SESSION_ID.

The old relay tracked which canvases were online and auto-picked when there was
exactly one. A broadcast endpoint has no such registry, so the session has to be
named: copy it from the browser tab (sessionStorage `jasketch_session_id`)."""
def _resolve_session(session_id: str = "") -> str {
    sid: str = session_id or os.environ.get("JASKETCH_SESSION_ID", "");
    if sid { return sid; }
    raise Exception(
        "No canvas selected. Set JASKETCH_SESSION_ID to the tab's session id "
        "(sessionStorage key 'jasketch_session_id' in the JaSketch browser tab)."
    );
}


"""Send a command to the canvas via relay (blocking, thread-safe)."""
def _send_command(action: str, data: dict | None = None, session_id: str = "", timeout: float | None = None) -> Any {
    # Wait for the handshake rather than failing on it: the first tool call
    # typically arrives within a second of launch, before the socket is open.
    if not _relay_connected.wait(timeout=CONNECT_WAIT_SECONDS) {
        raise Exception(
            f"Not connected to relay after {CONNECT_WAIT_SECONDS:.0f}s. "
            f"Check JASKETCH_RELAY_URL ({RELAY_URL}) and that JaSketch is reachable."
        );
    }
    if _ws is None {
        raise Exception("Relay socket went away mid-call; retry.");
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
        "kind": "command",
        "request_id": request_id,
        "session_id": session_id,
        "action": action,
        "data": data if data is not None else {}
    });

    try {
        future: Any = asyncio.run_coroutine_threadsafe(_ws.send(payload), _relay_loop);
        future.result(timeout=5);
    } except Exception as error {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Failed to send command: {error}");
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


# ── MCP tool dispatch helper ──────────────────────────────────────────────────

"""Create a session-bound CanvasToolProvider and execute the named tool."""
async def _run_mcp_tool(tool_name: str, args: dict, session_id: str | None) -> str {
    sid: str = _resolve_session(session_id or "");
    provider: CanvasToolProvider = CanvasToolProvider(
        send_fn=lambda (action: str, data: dict | None) -> any { _send_command(action, data, sid); }
    );
    return await asyncio.to_thread(provider.call_tool, tool_name, args);
}


# ── MCP Tools ─────────────────────────────────────────────────────────────────

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
    params: dict = {
        "type": type, "x": x, "y": y, "width": width, "height": height,
        "x1": x1, "y1": y1, "x2": x2, "y2": y2, "bendX": bendX, "bendY": bendY,
        "color": color, "strokeWidth": strokeWidth, "fillColor": fillColor,
        "lineStyle": lineStyle, "opacity": opacity, "text": text,
        "fontSize": fontSize, "fontFamily": fontFamily, "shapeText": shapeText,
        "shapeTextColor": shapeTextColor, "shapeTextFontSize": shapeTextFontSize,
        "shapeTextFontFamily": shapeTextFontFamily, "groupId": groupId, "points": points
    };
    args: dict = {k: v for (k, v) in params.items() if v is not None};
    return await _run_mcp_tool("create_element", args, session_id);
}


"""Batch create multiple elements on the JaSketch canvas. More efficient for diagrams."""
@mcp.tool()
async def create_elements(elements: list[dict], session_id: str | None = None) -> str {
    return await _run_mcp_tool("create_elements", {"elements": elements}, session_id);
}


"""Connect two canvas shapes by index with an arrow/line. Auto-selects nearest edges."""
@mcp.tool()
async def draw_connector(
    from_index: int,
    to_index: int,
    type: str = "arrow",
    label: str | None = None,
    color: str = "#1e1e1e",
    line_style: str = "solid",
    session_id: str | None = None
) -> str {
    args: dict = {
        "from_index": from_index, "to_index": to_index,
        "type": type, "color": color, "line_style": line_style
    };
    if label is not None { args["label"] = label; }
    return await _run_mcp_tool("draw_connector", args, session_id);
}


"""Create an auto-sized shape with a centered label. Width is calculated from label length."""
@mcp.tool()
async def draw_labeled_shape(
    shape: str,
    label: str,
    x: float,
    y: float,
    color: str = "#1e1e1e",
    fill_color: str = "transparent",
    width: float | None = None,
    height: float | None = None,
    session_id: str | None = None
) -> str {
    args: dict = {
        "shape": shape, "label": label, "x": x, "y": y,
        "color": color, "fill_color": fill_color
    };
    if width is not None { args["width"] = width; }
    if height is not None { args["height"] = height; }
    return await _run_mcp_tool("draw_labeled_shape", args, session_id);
}


"""Add a large title text element at the specified position."""
@mcp.tool()
async def add_title(
    text: str,
    x: float = 100,
    y: float = 40,
    session_id: str | None = None
) -> str {
    return await _run_mcp_tool("add_title", {"text": text, "x": x, "y": y}, session_id);
}


"""Query elements currently on the JaSketch canvas. Optionally filter by type or index."""
@mcp.tool()
async def query_elements(
    type: str | None = None,
    index: int | None = None,
    session_id: str | None = None
) -> str {
    args: dict = {};
    if type is not None { args["type"] = type; }
    if index is not None { args["index"] = index; }
    return await _run_mcp_tool("query_elements", args, session_id);
}


"""Update properties of an existing element by index."""
@mcp.tool()
async def update_element(index: int, changes: dict, session_id: str | None = None) -> str {
    return await _run_mcp_tool("update_element", {"index": index, "changes": changes}, session_id);
}


"""Delete element(s) by index or array of indices."""
@mcp.tool()
async def delete_element(
    index: int | None = None,
    indices: list[int] | None = None,
    session_id: str | None = None
) -> str {
    args: dict = {};
    if indices is not None { args["indices"] = indices; }
    if index is not None { args["index"] = index; }
    return await _run_mcp_tool("delete_element", args, session_id);
}


"""Clear all elements from the JaSketch canvas."""
@mcp.tool()
async def clear_canvas(session_id: str | None = None) -> str {
    return await _run_mcp_tool("clear_canvas", {}, session_id);
}


"""Get the current viewport state: zoom level, pan offset, canvas dimensions, and visible area."""
@mcp.tool()
async def get_viewport(session_id: str | None = None) -> str {
    return await _run_mcp_tool("get_viewport", {}, session_id);
}


"""Get a JPEG screenshot of the current canvas as a base64 data URL. Use to visually verify what has been drawn."""
@mcp.tool()
async def get_canvas_snapshot(session_id: str | None = None) -> str {
    return await _run_mcp_tool("get_canvas_snapshot", {}, session_id);
}


"""Get the bounding box of all elements on the canvas. Useful for layout planning and finding free space."""
@mcp.tool()
async def get_bounding_box(session_id: str | None = None) -> str {
    return await _run_mcp_tool("get_bounding_box", {}, session_id);
}


"""Fetch all canvas elements with defaults stripped for token efficiency. Non-default visual properties are preserved."""
@mcp.tool()
async def get_canvas_elements(session_id: str | None = None) -> str {
    return await _run_mcp_tool("get_canvas_elements", {}, session_id);
}


"""Atomically replace canvas content with a complete elements array. Clears existing, applies defaults, renders, and auto-fits viewport."""
@mcp.tool()
async def render_elements(elements: list[dict], session_id: str | None = None) -> str {
    return await _run_mcp_tool("render_elements", {"elements": elements}, session_id);
}


"""Get a JSON schema guide for element types, defaults, layout rules, colors, and rendering format."""
@mcp.tool()
async def get_drawing_guide(session_id: str | None = None) -> str {
    return await _run_mcp_tool("get_drawing_guide", {}, session_id);
}


# ── Start server ──────────────────────────────────────────────────────────────

"""Console-script entry point (`jasketch-mcp-server`), and what `jac run` calls.

Deliberately NOT a bare `with entry`: that runs on every IMPORT of the module,
so the packaged console script would start a relay thread and seize stdio the
moment anything imported it."""
def main() -> None {
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


with entry:__main__ {
    main();
}
