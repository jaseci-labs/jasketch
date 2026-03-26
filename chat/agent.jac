"""JaSketch Chat Agent - LLM-powered canvas assistant with dynamic tools."""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import websockets;
import litellm;
import from typing { Any }


# ============================================================
# Config
# ============================================================

glob RELAY_URL: str = os.environ.get("JASKETCH_RELAY_URL", "ws://localhost:9601");
glob CHAT_PORT: int = int(os.environ.get("JASKETCH_CHAT_PORT", "9602"));
glob REQUEST_TIMEOUT: float = 30.0;
glob MAX_TOOL_ITERATIONS: int = 10;


def _log(msg: str) -> None {
    print(f"[jasketch-chat] {msg}", file=sys.stderr, flush=True);
}


# ============================================================
# Relay connection (background thread)
# ============================================================

glob _lock: Any = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _canvas_connected: bool = False;
glob _pending: dict = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();


async def _connect_to_relay() -> None {
    global _ws, _connected, _canvas_connected;
    while True {
        try {
            async with websockets.connect(RELAY_URL, compression=None) as ws {
                _ws = ws;
                _connected = True;
                _log(f"Connected to relay at {RELAY_URL}");
                await ws.send(json.dumps({"role": "controller"}));
                async for raw in ws {
                    try {
                        msg: dict = json.loads(raw);
                        mt: str = msg.get("type", "");
                        if mt == "registered" { _canvas_connected = bool(msg.get("canvasConnected", False)); continue; }
                        if mt == "canvasConnected" { _canvas_connected = True; continue; }
                        if mt == "canvasDisconnected" { _canvas_connected = False; continue; }
                        rid: str = msg.get("requestId", "");
                        entry: Any = None;
                        with _lock { entry = _pending.pop(rid, None); }
                        if entry is not None {
                            (evt, res) = entry;
                            if msg.get("success") { res["data"] = msg.get("data"); }
                            else { res["error"] = msg.get("error", "Unknown error"); }
                            evt.set();
                        }
                    } except Exception as e { _log(f"Relay msg err: {e}"); }
                }
            }
        } except Exception as e { _log(f"Relay err: {e}"); }
        _ws = None;
        _connected = False;
        _canvas_connected = False;
        await asyncio.sleep(3);
    }
}


def _start_relay_thread() -> None {
    global _relay_loop;
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();
    _relay_loop.run_until_complete(_connect_to_relay());
}


def _send_command(action: str, data: dict | None = None) -> Any {
    if (not _connected) or (_ws is None) { raise Exception("Not connected to relay."); }
    if not _canvas_connected { raise Exception("No canvas connected. Open JaSketch in a browser."); }
    _relay_ready.wait(timeout=5);
    request_id: str = str(uuid.uuid4());
    evt: Any = threading.Event();
    res: dict = {};
    with _lock { _pending[request_id] = (evt, res); }
    payload: str = json.dumps({"requestId": request_id, "action": action, "data": data if data is not None else {}});
    try {
        future: Any = asyncio.run_coroutine_threadsafe(_ws.send(payload), _relay_loop);
        future.result(timeout=5);
    } except Exception as e {
        with _lock { _pending.pop(request_id, None); }
        raise Exception(f"Send failed: {e}");
    }
    if not evt.wait(timeout=REQUEST_TIMEOUT) {
        with _lock { _pending.pop(request_id, None); }
        raise Exception("Request timed out");
    }
    if "error" in res { raise Exception(res["error"]); }
    return res.get("data");
}


# ============================================================
# Dynamic tool builder
# ============================================================

"""Build a single property schema."""
def _prop(ptype: str, desc: str, **kwargs: Any) -> dict {
    p: dict = {"type": ptype, "description": desc};
    if "enum" in kwargs { p["enum"] = kwargs["enum"]; }
    if "items" in kwargs { p["items"] = kwargs["items"]; }
    if "minimum" in kwargs { p["minimum"] = kwargs["minimum"]; }
    if "maximum" in kwargs { p["maximum"] = kwargs["maximum"]; }
    return p;
}


"""Build an OpenAI function-calling tool schema."""
def _tool(name: str, desc: str, props: dict, required: list | None = None) -> dict {
    params: dict = {"type": "object", "properties": props};
    if required { params["required"] = required; }
    return {"type": "function", "function": {"name": name, "description": desc, "parameters": params}};
}


# ============================================================
# Tool definitions (generated dynamically)
# ============================================================

"""Build all tool schemas."""
def _build_tools() -> list {
    tools: list = [];

    # -- Primitive canvas tools --

    tools.append(_tool(
        "create_elements",
        "Batch create multiple elements at once. ALWAYS prefer this over single creation."
        "\nEach element: {type, x, y, width, height, color, fillColor, shapeText, ...}"
        "\nTypes: rectangle, circle, diamond (shapes with x,y,width,height + shapeText for labels)"
        "\n       line, arrow (x1,y1 to x2,y2, arrow has arrowhead at x2,y2, bendX/bendY for curves)"
        "\n       text (x,y,text,fontSize,fontFamily)",
        {
            "elements": _prop("array", "Array of element objects", items={"type": "object"})
        },
        required=["elements"]
    ));

    tools.append(_tool(
        "create_element",
        "Create a single element. Use create_elements for 2+ elements.",
        {
            "type": _prop("string", "Element type", enum=["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand"]),
            "x": _prop("number", "Left position (shapes/text)"),
            "y": _prop("number", "Top position (shapes/text)"),
            "width": _prop("number", "Width (shapes). Min 140 for labeled shapes"),
            "height": _prop("number", "Height (shapes). Min 60 for labeled shapes"),
            "x1": _prop("number", "Start X (lines/arrows)"),
            "y1": _prop("number", "Start Y (lines/arrows)"),
            "x2": _prop("number", "End X (lines/arrows)"),
            "y2": _prop("number", "End Y (lines/arrows)"),
            "bendX": _prop("number", "Curve control point X for curved lines/arrows"),
            "bendY": _prop("number", "Curve control point Y for curved lines/arrows"),
            "text": _prop("string", "Text content. Use \\n for multi-line"),
            "color": _prop("string", "Stroke color hex (#1971c2 blue, #1e1e1e black, #e03131 red, #2b8a3e green, #f08c00 amber, #0c8599 teal, #9c36b5 purple, #868e96 gray)"),
            "fillColor": _prop("string", "Fill color hex or 'transparent'. Pastels: #e7f5ff blue, #fff3bf yellow, #f3f0ff purple, #ebfbee green"),
            "strokeWidth": _prop("number", "Line thickness (default 2)"),
            "lineStyle": _prop("string", "Line style", enum=["solid", "dashed", "dotted"]),
            "opacity": _prop("number", "0.0-1.0", minimum=0, maximum=1),
            "fontSize": _prop("number", "Font size: 14 small, 18 label, 24 normal, 32 heading, 48 title"),
            "fontFamily": _prop("string", "Font: Virgil (hand-drawn), Inter (sans), Georgia (serif), Courier New (mono)"),
            "shapeText": _prop("string", "Label centered inside shape (rectangle/circle/diamond only)"),
            "shapeTextColor": _prop("string", "Shape label color hex"),
            "shapeTextFontSize": _prop("number", "Shape label font size (14-18)"),
            "groupId": _prop("string", "Group ID - elements with same ID move together"),
            "points": _prop("array", "Freehand points [{x,y}, ...]", items={"type": "object"})
        },
        required=["type"]
    ));

    # -- Smart/compound tools --

    tools.append(_tool(
        "draw_connector",
        "Draw a smart arrow/line between two shapes by their indices. Automatically connects to the nearest edges."
        "\nMuch better than manually calculating x1,y1,x2,y2 - handles edge-to-edge connection for you.",
        {
            "from_index": _prop("integer", "Index of the source shape"),
            "to_index": _prop("integer", "Index of the target shape"),
            "type": _prop("string", "Connector type", enum=["arrow", "line"]),
            "label": _prop("string", "Optional label text on the connector"),
            "color": _prop("string", "Line color hex"),
            "lineStyle": _prop("string", "Line style", enum=["solid", "dashed", "dotted"])
        },
        required=["from_index", "to_index"]
    ));

    tools.append(_tool(
        "draw_labeled_shape",
        "Create a properly sized shape with a label inside. Automatically calculates width/height to fit the text."
        "\nReturns the created element's index so you can reference it in draw_connector.",
        {
            "shape": _prop("string", "Shape type", enum=["rectangle", "circle", "diamond"]),
            "label": _prop("string", "Text to display inside the shape"),
            "x": _prop("number", "X position"),
            "y": _prop("number", "Y position"),
            "color": _prop("string", "Stroke color hex"),
            "fillColor": _prop("string", "Fill color hex or 'transparent'"),
            "width": _prop("number", "Override auto width"),
            "height": _prop("number", "Override auto height")
        },
        required=["shape", "label", "x", "y"]
    ));

    tools.append(_tool(
        "add_title",
        "Add a title text element at the top of the diagram.",
        {
            "text": _prop("string", "Title text"),
            "x": _prop("number", "X position (default 100)"),
            "y": _prop("number", "Y position (default 40)")
        },
        required=["text"]
    ));

    # -- Query/modify tools --

    tools.append(_tool(
        "query_elements",
        "Query elements on the canvas. Returns element data with indices. Use to understand existing content.",
        {
            "type": _prop("string", "Filter by type (rectangle, text, arrow, etc)"),
            "index": _prop("integer", "Get specific element by index")
        }
    ));

    tools.append(_tool(
        "update_element",
        "Update properties of an existing element by index.",
        {
            "index": _prop("integer", "Element index"),
            "changes": _prop("object", "Properties to change: {color, shapeText, fillColor, ...}")
        },
        required=["index", "changes"]
    ));

    tools.append(_tool(
        "delete_element",
        "Delete one or more elements by index.",
        {
            "index": _prop("integer", "Single element index"),
            "indices": _prop("array", "Multiple indices", items={"type": "integer"})
        }
    ));

    tools.append(_tool("clear_canvas", "Delete ALL elements.", {}));
    tools.append(_tool("get_viewport", "Get viewport: zoom, pan, visible area. Use to place elements in view.", {}));
    tools.append(_tool("get_bounding_box", "Get bounding box of all elements. Use to find free space.", {}));

    return tools;
}


glob TOOLS: list = _build_tools();


# ============================================================
# System prompt
# ============================================================

glob SYSTEM_PROMPT: str = """You are an AI sketch assistant in JaSketch, a hand-drawn style whiteboard.

CANVAS: (0,0) top-left, X right, Y down, ~2000x1500 visible. Start at (100,100).

RULES:
- ALWAYS use create_elements for batch creation (2+ items)
- Use draw_labeled_shape for shapes with text (auto-sizes properly)
- Use draw_connector to connect shapes (auto-calculates edge positions)
- Use add_title for diagram titles
- Use get_bounding_box before adding to existing content

LAYOUT:
- Min shape size: 140x60 (labeled), 180x70 (long text)
- Spacing: 200px horizontal, 150px vertical
- Arrow connection: draw_connector handles edge-to-edge automatically

COLORS:
#1971c2 blue | #1e1e1e black | #e03131 red | #2b8a3e green
#f08c00 amber | #0c8599 teal | #9c36b5 purple | #868e96 gray
Fills: #e7f5ff light-blue | #fff3bf light-yellow | #f3f0ff light-purple | #ebfbee light-green

Keep responses brief - just say what you drew.""";


# ============================================================
# Element helpers
# ============================================================

def _apply_defaults(el: dict) -> dict {
    for (k, v) in {"color": "#1e1e1e", "strokeWidth": 2, "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0}.items() {
        el.setdefault(k, v);
    }
    if el.get("type") in ("rectangle", "circle", "diamond") { el.setdefault("width", 140); el.setdefault("height", 60); }
    if el.get("type") == "text" { el.setdefault("fontSize", 24); el.setdefault("fontFamily", "Virgil"); }
    return el;
}


"""Calculate edge midpoints for a shape element."""
def _get_shape_edges(el: dict) -> dict {
    t: str = el.get("type", "");
    if t in ("rectangle", "circle", "diamond", "image") {
        x: Any = el.get("x", 0);
        y: Any = el.get("y", 0);
        w: Any = el.get("width", 100);
        h: Any = el.get("height", 60);
        cx: Any = x + w / 2;
        cy: Any = y + h / 2;
        return {
            "top": {"x": cx, "y": y},
            "bottom": {"x": cx, "y": y + h},
            "left": {"x": x, "y": cy},
            "right": {"x": x + w, "y": cy},
            "center": {"x": cx, "y": cy}
        };
    }
    if t == "text" {
        tx: Any = el.get("x", 0);
        ty: Any = el.get("y", 0);
        return {"top": {"x": tx, "y": ty}, "bottom": {"x": tx, "y": ty + 30}, "left": {"x": tx, "y": ty + 15}, "right": {"x": tx + 100, "y": ty + 15}, "center": {"x": tx + 50, "y": ty + 15}};
    }
    return {"center": {"x": el.get("x", el.get("x1", 0)), "y": el.get("y", el.get("y1", 0))}};
}


"""Find the best pair of edge points to connect two shapes."""
def _best_connection(from_edges: dict, to_edges: dict) -> tuple {
    import math;
    best_dist: float = 999999.0;
    best_from: str = "bottom";
    best_to: str = "top";
    sides: list = ["top", "bottom", "left", "right"];
    for fs in sides {
        if fs not in from_edges { continue; }
        fp: dict = from_edges[fs];
        for ts in sides {
            if ts not in to_edges { continue; }
            tp: dict = to_edges[ts];
            d: float = math.sqrt((fp["x"] - tp["x"]) ** 2 + (fp["y"] - tp["y"]) ** 2);
            if d < best_dist {
                best_dist = d;
                best_from = fs;
                best_to = ts;
            }
        }
    }
    return (from_edges.get(best_from, from_edges.get("center")), to_edges.get(best_to, to_edges.get("center")));
}


"""Rough estimate of text width in pixels."""
def _estimate_text_width(text: str, font_size: int) -> int {
    return int(len(text) * font_size * 0.55) + 40;
}


# ============================================================
# Tool executor
# ============================================================

def _execute_tool(name: str, args: dict) -> str {
    try {
        # -- Primitives --

        if name == "create_element" {
            el: dict = {"type": args.get("type", "rectangle")};
            for (k, v) in args.items() {
                if k != "type" and v is not None { el[k] = v; }
            }
            return json.dumps(_send_command("addElement", _apply_defaults(el)));
        }

        if name == "create_elements" {
            processed: list = [_apply_defaults(dict(e)) for e in args.get("elements", [])];
            return json.dumps(_send_command("addMultipleElements", {"elements": processed}));
        }

        if name == "query_elements" {
            params: dict = {};
            if args.get("type") is not None { params["type"] = args["type"]; }
            if args.get("index") is not None { params["index"] = args["index"]; }
            return json.dumps(_send_command("getElements", params));
        }

        if name == "update_element" {
            return json.dumps(_send_command("updateElement", {"index": args["index"], "changes": args.get("changes", {})}));
        }

        if name == "delete_element" {
            indices_val: Any = args.get("indices");
            idx_val: Any = args.get("index");
            if indices_val is not None and len(indices_val) > 0 {
                return json.dumps(_send_command("removeMultipleElements", {"indices": indices_val}));
            } elif idx_val is not None {
                return json.dumps(_send_command("removeElement", {"index": idx_val}));
            }
            return json.dumps({"error": "Provide index or indices"});
        }

        if name == "clear_canvas" { return json.dumps(_send_command("clearElements")); }
        if name == "get_viewport" { return json.dumps(_send_command("getViewport")); }
        if name == "get_bounding_box" { return json.dumps(_send_command("getBoundingBox")); }

        # -- Smart tools --

        if name == "draw_connector" {
            from_idx: int = args["from_index"];
            to_idx: int = args["to_index"];

            # Query both shapes
            from_result: Any = _send_command("getElements", {"index": from_idx});
            to_result: Any = _send_command("getElements", {"index": to_idx});
            from_els: list = from_result.get("elements", []);
            to_els: list = to_result.get("elements", []);
            if not from_els or not to_els {
                return json.dumps({"error": "Shape not found at given index"});
            }
            from_el: dict = from_els[0]["element"];
            to_el: dict = to_els[0]["element"];

            # Calculate best edge connection
            (fp, tp) = _best_connection(_get_shape_edges(from_el), _get_shape_edges(to_el));

            connector: dict = {
                "type": args.get("type", "arrow"),
                "x1": fp["x"], "y1": fp["y"],
                "x2": tp["x"], "y2": tp["y"],
                "color": args.get("color", "#1e1e1e"),
                "strokeWidth": 2,
                "lineStyle": args.get("lineStyle", "solid"),
                "opacity": 1.0
            };
            result: Any = _send_command("addElement", connector);

            # Add label if provided
            if args.get("label") {
                mid_x: float = (fp["x"] + tp["x"]) / 2;
                mid_y: float = (fp["y"] + tp["y"]) / 2 - 12;
                label_el: dict = {
                    "type": "text", "x": mid_x, "y": mid_y,
                    "text": args["label"], "fontSize": 12, "fontFamily": "Virgil",
                    "color": "#868e96", "strokeWidth": 1, "fillColor": "transparent",
                    "lineStyle": "solid", "opacity": 1.0
                };
                _send_command("addElement", label_el);
            }
            return json.dumps(result);
        }

        if name == "draw_labeled_shape" {
            label: str = args.get("label", "");
            shape_type: str = args.get("shape", "rectangle");
            font_size: int = 16;
            w: int = args.get("width", 0) or max(140, _estimate_text_width(label, font_size));
            h: int = args.get("height", 0) or (80 if shape_type == "diamond" else 60);
            if shape_type == "circle" { h = max(h, int(w * 0.6)); }

            el: dict = _apply_defaults({
                "type": shape_type,
                "x": args.get("x", 100), "y": args.get("y", 100),
                "width": w, "height": h,
                "shapeText": label, "shapeTextFontSize": font_size,
                "color": args.get("color", "#1e1e1e"),
                "fillColor": args.get("fillColor", "transparent")
            });
            return json.dumps(_send_command("addElement", el));
        }

        if name == "add_title" {
            title_el: dict = {
                "type": "text",
                "x": args.get("x", 100), "y": args.get("y", 40),
                "text": args["text"], "fontSize": 32, "fontFamily": "Virgil",
                "color": "#1e1e1e", "strokeWidth": 1, "fillColor": "transparent",
                "lineStyle": "solid", "opacity": 1.0
            };
            return json.dumps(_send_command("addElement", title_el));
        }

        return json.dumps({"error": f"Unknown tool: {name}"});
    } except Exception as e {
        return json.dumps({"error": str(e)});
    }
}


# ============================================================
# WebSocket chat handler
# ============================================================

async def _ws_send(ws: Any, msg_type: str, **kwargs: Any) -> None {
    kwargs["type"] = msg_type;
    await ws.send(json.dumps(kwargs));
}


async def _accumulate_tool_call(acc: dict, tc: Any) -> None {
    tc_idx: Any = getattr(tc, "index", 0);
    if tc_idx not in acc { acc[tc_idx] = {"id": "", "name": "", "arguments": ""}; }
    tc_id: Any = getattr(tc, "id", None);
    if tc_id { acc[tc_idx]["id"] = tc_id; }
    tc_fn: Any = getattr(tc, "function", None);
    if tc_fn is not None {
        fn_name: Any = getattr(tc_fn, "name", None);
        fn_args: Any = getattr(tc_fn, "arguments", None);
        if fn_name { acc[tc_idx]["name"] = fn_name; }
        if fn_args { acc[tc_idx]["arguments"] = acc[tc_idx]["arguments"] + fn_args; }
    }
}


"""Run the LLM tool loop: stream tokens, execute tool calls, repeat."""
async def _stream_response(ws: Any, api_key: str, model: str, messages: list) -> None {
    iteration: int = 0;

    while iteration < MAX_TOOL_ITERATIONS {
        iteration = iteration + 1;

        response: Any = await litellm.acompletion(
            model=model, messages=messages, tools=TOOLS, api_key=api_key, stream=True
        );

        full_content: str = "";
        tc_acc: dict = {};

        async for chunk in response {
            choices: Any = getattr(chunk, "choices", None);
            if not choices or len(choices) == 0 { continue; }
            delta: Any = getattr(choices[0], "delta", None);
            if delta is None { continue; }

            content: Any = getattr(delta, "content", None);
            if content {
                full_content = full_content + content;
                await _ws_send(ws, "token", content=content);
            }

            tc_list: Any = getattr(delta, "tool_calls", None);
            if tc_list is not None {
                for tc in tc_list { await _accumulate_tool_call(tc_acc, tc); }
            }
        }

        if len(tc_acc) == 0 {
            await _ws_send(ws, "done");
            return;
        }

        # Build tool calls list
        tool_calls: list = [];
        for (_, td) in sorted(tc_acc.items()) {
            tool_calls.append({"id": td["id"], "type": "function", "function": {"name": td["name"], "arguments": td["arguments"]}});
        }

        assistant_msg: dict = {"role": "assistant", "tool_calls": tool_calls};
        if full_content { assistant_msg["content"] = full_content; }
        messages.append(assistant_msg);

        # Execute each tool
        for tc_info in tool_calls {
            t_name: str = tc_info["function"]["name"];
            t_args_str: str = tc_info["function"]["arguments"];
            await _ws_send(ws, "tool_call", name=t_name, arguments=t_args_str);

            try { t_args: dict = json.loads(t_args_str); }
            except Exception { t_args = {}; }

            t_result: str = await asyncio.to_thread(_execute_tool, t_name, t_args);
            await _ws_send(ws, "tool_result", name=t_name, result=t_result);
            messages.append({"role": "tool", "tool_call_id": tc_info["id"], "content": t_result});
        }
    }

    await _ws_send(ws, "error", message="Max tool iterations reached.");
    await _ws_send(ws, "done");
}


"""Handle a chat WebSocket connection from the browser."""
async def _chat_ws_handler(ws: Any) -> None {
    _log("Chat client connected");
    try {
        async for raw in ws {
            try {
                msg: dict = json.loads(raw);
                if msg.get("type") != "chat" { continue; }

                api_key: str = msg.get("apiKey", "");
                model: str = msg.get("model", "gpt-4o-mini");
                user_msg: str = msg.get("message", "");
                history: list = msg.get("history", []);

                if not api_key { await _ws_send(ws, "error", message="API key required."); continue; }
                if not user_msg { continue; }

                _log(f"Chat: model={model}, msg={user_msg[:80]}");
                messages: list = [{"role": "system", "content": SYSTEM_PROMPT}];
                for h in history { messages.append({"role": h.get("role", "user"), "content": h.get("content", "")}); }
                messages.append({"role": "user", "content": user_msg});

                try { await _stream_response(ws, api_key, model, messages); }
                except Exception as e {
                    _log(f"LLM error: {e}");
                    await _ws_send(ws, "error", message=str(e));
                }
            } except Exception as e {
                _log(f"Msg error: {e}");
                try { await _ws_send(ws, "error", message=str(e)); }
                except Exception { _ = 0; }
            }
        }
    } except websockets.ConnectionClosed { _ = 0; }
    _log("Chat client disconnected");
}


# ============================================================
# Boot (runs when module is imported)
# ============================================================

def _boot_all() -> None {
    _log("Starting relay connection...");
    relay_t: Any = threading.Thread(target=_start_relay_thread, daemon=True);
    relay_t.start();

    def _run_chat_ws() -> None {
        loop: Any = asyncio.new_event_loop();
        asyncio.set_event_loop(loop);
        async def _serve() -> None {
            async with websockets.serve(_chat_ws_handler, "0.0.0.0", CHAT_PORT) {
                _log(f"Chat WebSocket on port {CHAT_PORT}");
                await asyncio.Future();
            }
        }
        loop.run_until_complete(_serve());
    }

    chat_t: Any = threading.Thread(target=_run_chat_ws, daemon=True);
    chat_t.start();
}

glob _booted: Any = _boot_all();
