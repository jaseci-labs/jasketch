"""Hosted MCP: an assistant connects to a URL, with nothing to install.

The MCP server has always run on the user's own machine over stdio -- they had
to install a package, clone a repo, or both, and then paste a session id. This
serves the same tools over HTTP from the app itself:

    claude mcp add --transport http jasketch https://<host>/mcp

It is an endpoint of THIS app rather than a second deployment, because
`jac start --scale` exposes one container port and a FastMCP process would need
its own service, its own route and its own health checks to reach it.
`@restspec(envelope=False)` is what makes that possible: MCP clients need bare
JSON-RPC, and every other jac endpoint wraps its result in {ok, data, ...}.

Reaching the browser still goes through the relay, because that is the only
push channel to a canvas. The connection below is a loopback client to this same
app's relay endpoint -- the same role the standalone bridge plays, just running
in-process.

One hosted server serves everyone: there is no per-process JASKETCH_SESSION_ID
here, so every tool call carries the `session_id` of the canvas it targets.
"""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;
import from typing { Any }
import from http { HTTPMethod }

import from mcp_server.jasketch_mcp_server.canvas_tools { CanvasToolProvider }
import from infrastructure.relay { canvas_is_online, online_canvases }

glob MCP_PROTOCOL_VERSION: str = "2024-11-05";
glob SERVER_VERSION: str = "2.0.0";

# The relay endpoint of this very app. The port is the one the server binds, so
# it follows [serve] port / --port / container_port rather than being hardcoded.
glob LOOPBACK_WS: str = os.environ.get(
    "JASKETCH_LOOPBACK_WS",
    f"ws://127.0.0.1:{os.environ.get('PORT', '8000')}/ws/function/jasketch_relay"
);

# Comfortably inside a load balancer's idle timeout: a request that blocks
# past it comes back as a 502 with no explanation of what went wrong.
glob REQUEST_TIMEOUT: float = 25.0;
glob CONNECT_WAIT_SECONDS: float = 15.0;

glob _lock = threading.Lock();
glob _ws: Any = None;
glob _loop: Any = None;
glob _connected: Any = threading.Event();
glob _loop_ready: Any = threading.Event();
glob _pending: dict[str, tuple[Any, dict]] = {};
glob _started: bool = False;


def log(msg: str) -> None {
    print(f"[jasketch-mcp-http] {msg}", file=sys.stderr, flush=True);
}


# ── Loopback relay client ─────────────────────────────────────────────────────

async def _relay_loop() -> None {
    import websockets;

    while True {
        try {
            async with websockets.connect(LOOPBACK_WS, compression=None) as ws {
                _ws = ws;
                _connected.set();
                log(f"Connected to relay at {LOOPBACK_WS}");
                async for raw in ws {  # jac:ignore[E1022]
                    try {
                        envelope: dict = json.loads(str(raw));
                        if envelope.get("type") != "chunk" {
                            continue;
                        }
                        msg: dict = envelope.get("data") or {};
                        if msg.get("kind") != "response" {
                            continue;
                        }
                        entry: tuple[Any, dict] | None = None;
                        with _lock {
                            entry = _pending.pop(msg.get("request_id", ""), None);
                        }
                        if entry is not None {
                            (evt, res) = entry;
                            if msg.get("success") {
                                res["data"] = msg.get("data");
                            } else {
                                res["error"] = msg.get("error", "Unknown error from the canvas");
                            }
                            evt.set();
                        }
                    } except Exception as error {
                        log(f"Bad relay message: {error}");
                    }
                }
            }
        } except Exception as error {
            log(f"Relay connection error: {error}");
        }
        _ws = None;
        _connected.clear();
        await asyncio.sleep(3);
    }
}


def _run_relay_thread() -> None {
    _loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_loop);
    _loop_ready.set();
    _loop.run_until_complete(_relay_loop());
}


"""Start the loopback client once, lazily -- nothing connects until MCP is used."""
def _ensure_started() -> None {
    with _lock {
        if _started {
            return;
        }
        _started = True;
    }
    threading.Thread(target=_run_relay_thread, daemon=True).start();
    _loop_ready.wait(timeout=5);
}


"""Send one canvas command to `session_id` and block for its reply."""
def _send_command(action: str, data: dict | None, session_id: str) -> Any {
    _ensure_started();
    if not _connected.wait(timeout=CONNECT_WAIT_SECONDS) {
        raise Exception(f"Canvas relay unreachable at {LOOPBACK_WS}");
    }
    if _ws is None {
        raise Exception("Relay socket went away mid-call; retry.");
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
        future: Any = asyncio.run_coroutine_threadsafe(_ws.send(payload), _loop);
        future.result(timeout=5);
    } except Exception as error {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Failed to reach the canvas: {error}");
    }

    if not evt.wait(timeout=REQUEST_TIMEOUT) {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(
            f"The canvas did not answer in {REQUEST_TIMEOUT:.0f}s. Is the tab for "
            f"session '{session_id}' still open?"
        );
    }
    if "error" in res {
        raise Exception(res["error"]);
    }
    return res.get("data");
}


# ── JSON-RPC ──────────────────────────────────────────────────────────────────

"""The tool list, with session_id added to every tool's input schema.

A hosted server has no ambient notion of "the" canvas, so the caller names one
per call. Advertising it in the schema is what lets an assistant fill it in
without being told the convention separately."""
def _tool_list() -> list[dict] {
    provider: CanvasToolProvider = CanvasToolProvider(send_fn=lambda (a: str, d: dict | None) -> Any { None; });
    tools: list[dict] = [];
    for tool in provider.list_tools() {
        spec: dict = dict(tool);
        schema: dict = dict(spec.get("inputSchema") or {});
        props: dict = dict(schema.get("properties") or {});
        props["session_id"] = {
            "type": "string",
            "description": "Which JaSketch tab to draw on. Copy it from the "
                           "'Connect an AI assistant' panel in the app."
        };
        schema["properties"] = props;
        schema["required"] = list(schema.get("required") or []) + ["session_id"];
        spec["inputSchema"] = schema;
        tools.append(spec);
    }
    return tools;
}


def _ok(rid: Any, result: dict) -> dict {
    return {"jsonrpc": "2.0", "id": rid, "result": result};
}


def _err(rid: Any, code: int, message: str) -> dict {
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}};
}


"""MCP over HTTP. Point an assistant at POST /mcp -- nothing to install.

envelope=False because MCP clients parse bare JSON-RPC; every other endpoint
here wraps its result in {ok, data, ...}, which no MCP client understands."""
@restspec(method=HTTPMethod.POST, path="/mcp", envelope=False, produces="application/json")
def:pub mcp_rpc(
    method: str = "",
    id: Any = None,
    params: dict = {},
    jsonrpc: str = "2.0"
) -> dict | None {
    args: dict = params or {};

    if method == "initialize" {
        return _ok(id, {
            "protocolVersion": MCP_PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "jasketch", "version": SERVER_VERSION}
        });
    }

    # Notifications carry no id and expect no response body.
    if method.startswith("notifications/") {
        return None;
    }

    if method == "ping" {
        return _ok(id, {});
    }

    if method == "tools/list" {
        return _ok(id, {"tools": _tool_list()});
    }

    if method == "tools/call" {
        name: str = str(args.get("name", ""));
        call_args: dict = dict(args.get("arguments") or {});
        session_id: str = str(call_args.pop("session_id", "") or "");
        if not session_id {
            return _ok(id, {
                "isError": True,
                "content": [{"type": "text", "text": json.dumps({
                    "error": "session_id is required. Open JaSketch, use the "
                             "'Connect an AI assistant' panel, and pass the id it shows."
                })}]
            });
        }
        if not canvas_is_online(session_id) {
            live: list[str] = online_canvases();
            hint: str = (
                f" Canvases currently connected: {', '.join(live)}."
                if live
                else " No canvas is connected right now."
            );
            return _ok(id, {
                "isError": True,
                "content": [{"type": "text", "text": json.dumps({
                    "error": f"No canvas is connected with session id '{session_id}'.{hint} "
                             f"Open JaSketch and copy the id from the 'AI Assistant' tab "
                             f"of the share dialog -- it changes when the tab is closed."
                })}]
            });
        }
        provider: CanvasToolProvider = CanvasToolProvider(
            send_fn=lambda (action: str, data: dict | None) -> Any {
                return _send_command(action, data, session_id);
            }
        );
        try {
            text: str = provider.call_tool(name, call_args);
        } except Exception as e {
            return _ok(id, {
                "isError": True,
                "content": [{"type": "text", "text": json.dumps({"error": str(e)})}]
            });
        }
        return _ok(id, {"content": [{"type": "text", "text": text}]});
    }

    return _err(id, -32601, f"Method not found: {method}");
}
