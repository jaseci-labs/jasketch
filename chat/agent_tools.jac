"""@tool decorator + all tool definitions. Import get_tools/execute from here."""

import json;
import math;
import threading;
import from typing { Any }


# ============================================================
# @tool decorator + registry
# ============================================================

glob _registry: list = [];
glob _executors: dict = {};
glob _local: Any = threading.local();  # thread-local storage for send_fn


def _send(action: str, data: dict | None = None) -> Any {
    fn: Any = getattr(_local, "send_fn", None);
    if fn is None { raise Exception("No session send_fn. Tool called outside of execute()."); }
    return fn(action, data);
}


def prop(ptype: str, desc: str, **kw: Any) -> dict {
    p: dict = {"type": ptype, "description": desc};
    if "enum" in kw { p["enum"] = kw["enum"]; }
    if "items" in kw { p["items"] = kw["items"]; }
    return p;
}


"""Decorator - registers a function as an LLM tool."""
def tool(description: str, props: dict | None = None, required: list | None = None) -> Any {
    def _dec(func: Any) -> Any {
        name: str = getattr(func, "__name__", "unknown");
        params: dict = {"type": "object", "properties": props if props is not None else {}};
        if required is not None { params["required"] = required; }
        _registry.append({"type": "function", "function": {"name": name, "description": description, "parameters": params}});
        _executors[name] = func;
        return func;
    }
    return _dec;
}


def get_tools() -> list { return _registry; }


def execute(name: str, args: dict, send_fn: Any) -> str {
    # Set send_fn in THIS worker thread so _send() calls route to the right canvas.
    # threading.local ensures concurrent users never share state.
    _local.send_fn = send_fn;
    fn: Any = _executors.get(name);
    if fn is not None {
        try { return fn(args); }
        except Exception as e { return json.dumps({"error": str(e)}); }
    }
    return json.dumps({"error": f"Unknown tool: {name}"});
}


# ============================================================
# Helpers
# ============================================================

def _defaults(el: dict) -> dict {
    for (k, v) in {"color": "#1e1e1e", "strokeWidth": 2, "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0}.items() {
        el.setdefault(k, v);
    }
    if el.get("type") in ("rectangle", "circle", "diamond") { el.setdefault("width", 140); el.setdefault("height", 60); }
    if el.get("type") == "text" { el.setdefault("fontSize", 24); el.setdefault("fontFamily", "Virgil"); }
    return el;
}

def _edges(el: dict) -> dict {
    t: str = el.get("type", "");
    if t in ("rectangle", "circle", "diamond", "image") {
        x: Any = el.get("x", 0); y: Any = el.get("y", 0);
        w: Any = el.get("width", 100); h: Any = el.get("height", 60);
        return {"top": {"x": x+w/2, "y": y}, "bottom": {"x": x+w/2, "y": y+h}, "left": {"x": x, "y": y+h/2}, "right": {"x": x+w, "y": y+h/2}};
    }
    return {"top": {"x": el.get("x", 0), "y": el.get("y", 0)}, "bottom": {"x": el.get("x", 0), "y": el.get("y", 0)+30}};
}

def _nearest(a: dict, b: dict) -> tuple {
    ea: dict = _edges(a); eb: dict = _edges(b);
    best: float = 999999.0; fp: dict = {}; tp: dict = {};
    for fs in ["top", "bottom", "left", "right"] {
        if fs not in ea { continue; }
        for ts in ["top", "bottom", "left", "right"] {
            if ts not in eb { continue; }
            d: float = math.sqrt((ea[fs]["x"]-eb[ts]["x"])**2 + (ea[fs]["y"]-eb[ts]["y"])**2);
            if d < best { best = d; fp = ea[fs]; tp = eb[ts]; }
        }
    }
    return (fp, tp);
}


# ============================================================
# Tool definitions — each @tool auto-registers
# ============================================================

@tool(
    "Batch create elements. ALWAYS prefer for 2+ items."
    "\nEach: {type, x, y, width, height, color, fillColor, shapeText, ...}"
    "\nTypes: rectangle/circle/diamond (x,y,w,h+shapeText), line/arrow (x1,y1,x2,y2+bendX,bendY), text (x,y,text,fontSize)",
    {"elements": prop("array", "Element objects", items={"type": "object"})},
    required=["elements"]
)
def create_elements(args: dict) -> str {
    return json.dumps(_send("addMultipleElements", {"elements": [_defaults(dict(e)) for e in args.get("elements", [])]}));
}

@tool("Create single element.", {
    "type": prop("string", "Type", enum=["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand"]),
    "x": prop("number", "Left"), "y": prop("number", "Top"),
    "width": prop("number", "Width min 140"), "height": prop("number", "Height min 60"),
    "x1": prop("number", "Start X"), "y1": prop("number", "Start Y"),
    "x2": prop("number", "End X"), "y2": prop("number", "End Y"),
    "bendX": prop("number", "Curve X"), "bendY": prop("number", "Curve Y"),
    "text": prop("string", "Text"), "color": prop("string", "Stroke hex"),
    "fillColor": prop("string", "Fill hex or transparent"),
    "strokeWidth": prop("number", "Thickness"), "lineStyle": prop("string", "Style", enum=["solid", "dashed", "dotted"]),
    "opacity": prop("number", "0-1"), "fontSize": prop("number", "14/18/24/32/48"),
    "fontFamily": prop("string", "Virgil/Inter/Georgia/Courier New"),
    "shapeText": prop("string", "Label inside shape"), "shapeTextColor": prop("string", "Label color"),
    "shapeTextFontSize": prop("number", "Label size 14-18"), "groupId": prop("string", "Group ID"),
    "points": prop("array", "Freehand [{x,y}]", items={"type": "object"})
}, required=["type"])
def create_element(args: dict) -> str {
    el: dict = {"type": args.get("type", "rectangle")};
    for (k, v) in args.items() { if k != "type" and v is not None { el[k] = v; } }
    return json.dumps(_send("addElement", _defaults(el)));
}

@tool("Smart arrow between two shapes by index. Auto-connects nearest edges.", {
    "from_index": prop("integer", "Source"), "to_index": prop("integer", "Target"),
    "type": prop("string", "arrow or line", enum=["arrow", "line"]),
    "label": prop("string", "Label"), "color": prop("string", "Color"),
    "lineStyle": prop("string", "Style", enum=["solid", "dashed", "dotted"])
}, required=["from_index", "to_index"])
def draw_connector(args: dict) -> str {
    fr: Any = _send("getElements", {"index": args["from_index"]});
    tr: Any = _send("getElements", {"index": args["to_index"]});
    if not fr.get("elements") or not tr.get("elements") { return json.dumps({"error": "Shape not found"}); }
    (fp, tp) = _nearest(fr["elements"][0]["element"], tr["elements"][0]["element"]);
    result: Any = _send("addElement", _defaults({"type": args.get("type", "arrow"), "x1": fp["x"], "y1": fp["y"], "x2": tp["x"], "y2": tp["y"], "color": args.get("color", "#1e1e1e"), "lineStyle": args.get("lineStyle", "solid")}));
    if args.get("label") {
        _send("addElement", {"type": "text", "x": (fp["x"]+tp["x"])/2, "y": (fp["y"]+tp["y"])/2-12, "text": args["label"], "fontSize": 12, "fontFamily": "Virgil", "color": "#868e96", "strokeWidth": 1, "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0});
    }
    return json.dumps(result);
}

@tool("Create auto-sized shape with centered label.", {
    "shape": prop("string", "Type", enum=["rectangle", "circle", "diamond"]),
    "label": prop("string", "Text inside"), "x": prop("number", "X"), "y": prop("number", "Y"),
    "color": prop("string", "Stroke"), "fillColor": prop("string", "Fill"),
    "width": prop("number", "Override width"), "height": prop("number", "Override height")
}, required=["shape", "label", "x", "y"])
def draw_labeled_shape(args: dict) -> str {
    label: str = args.get("label", "");
    shape: str = args.get("shape", "rectangle");
    w: int = args.get("width", 0) or max(140, int(len(label) * 16 * 0.55) + 40);
    h: int = args.get("height", 0) or (80 if shape == "diamond" else 60);
    if shape == "circle" { h = max(h, int(w * 0.6)); }
    return json.dumps(_send("addElement", _defaults({"type": shape, "x": args.get("x", 100), "y": args.get("y", 100), "width": w, "height": h, "shapeText": label, "shapeTextFontSize": 16, "color": args.get("color", "#1e1e1e"), "fillColor": args.get("fillColor", "transparent")})));
}

@tool("Add title text.", {"text": prop("string", "Title"), "x": prop("number", "X"), "y": prop("number", "Y")}, required=["text"])
def add_title(args: dict) -> str {
    return json.dumps(_send("addElement", {"type": "text", "x": args.get("x", 100), "y": args.get("y", 40), "text": args["text"], "fontSize": 32, "fontFamily": "Virgil", "color": "#1e1e1e", "strokeWidth": 1, "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0}));
}

@tool("Query canvas elements.", {"type": prop("string", "Filter type"), "index": prop("integer", "Get by index")})
def query_elements(args: dict) -> str {
    p: dict = {};
    if args.get("type") is not None { p["type"] = args["type"]; }
    if args.get("index") is not None { p["index"] = args["index"]; }
    return json.dumps(_send("getElements", p));
}

@tool("Update element by index.", {"index": prop("integer", "Index"), "changes": prop("object", "Changes")}, required=["index", "changes"])
def update_element(args: dict) -> str {
    return json.dumps(_send("updateElement", {"index": args["index"], "changes": args.get("changes", {})}));
}

@tool("Delete element(s).", {"index": prop("integer", "Index"), "indices": prop("array", "Indices", items={"type": "integer"})})
def delete_element(args: dict) -> str {
    iv: Any = args.get("indices"); ix: Any = args.get("index");
    if iv is not None and len(iv) > 0 { return json.dumps(_send("removeMultipleElements", {"indices": iv})); }
    if ix is not None { return json.dumps(_send("removeElement", {"index": ix})); }
    return json.dumps({"error": "Provide index or indices"});
}

@tool("Clear ALL elements.", {})
def clear_canvas(args: dict) -> str { return json.dumps(_send("clearElements")); }

@tool("Get viewport state.", {})
def get_viewport(args: dict) -> str { return json.dumps(_send("getViewport")); }

@tool("Get bounding box of all elements.", {})
def get_bounding_box(args: dict) -> str { return json.dumps(_send("getBoundingBox")); }
