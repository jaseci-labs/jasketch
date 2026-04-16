"""Shared canvas tool provider — single source of truth for all canvas operations.

Used by:
  - MCP server wrappers (@mcp.tool() thin wrappers in server.jac)
  - Agent direct import (chat/agent.jac, no subprocess/HTTP needed)

Each caller injects a session-specific send_fn so tool logic is
relay-agnostic and thread-safe (new instance per request).
"""

import json;
import math;
import from typing { Any }


obj CanvasToolProvider {
    """
    All JaSketch canvas operations.

    send_fn: callable(action: str, data: dict | None) -> Any
             Caller injects a relay-bound, session-specific send function.
             The agent supplies its own send_command; the MCP server supplies
             a lambda over _send_command.
    """
    has send_fn: Any;

    # ── Schema ────────────────────────────────────────────────────────────────

    def list_tools() -> list[dict] {
        return [
            {
                "name": "create_elements",
                "description": "Batch create elements. ALWAYS prefer for 2+ items.\nShapes: {type, x, y, width, height, shapeText, color, fillColor, boundElements:[\"ar-id\"]}.\nArrows: {type:\"arrow\", curveStyle:\"elbow\", startBinding:{elementId,side}, endBinding:{elementId,side}} — NO x1/y1/x2/y2.\nServer resolves arrow coordinates from bindings automatically.\nText: {type:\"text\", x, y, text, fontSize}.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "elements": {"type": "array", "description": "List of element objects", "items": {"type": "object"}}
                    },
                    "required": ["elements"]
                }
            },
            {
                "name": "create_element",
                "description": "Create a single canvas element.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "enum": ["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand"], "description": "Element type"},
                        "x": {"type": "number", "description": "Left edge X position"},
                        "y": {"type": "number", "description": "Top edge Y position"},
                        "width": {"type": "number", "description": "Width (min 140 for shapes)"},
                        "height": {"type": "number", "description": "Height (min 60 for shapes)"},
                        "x1": {"type": "number", "description": "Line/arrow start X"},
                        "y1": {"type": "number", "description": "Line/arrow start Y"},
                        "x2": {"type": "number", "description": "Line/arrow end X"},
                        "y2": {"type": "number", "description": "Line/arrow end Y"},
                        "bendX": {"type": "number", "description": "Curve control point X"},
                        "bendY": {"type": "number", "description": "Curve control point Y"},
                        "text": {"type": "string", "description": "Text content (for text elements)"},
                        "color": {"type": "string", "description": "Stroke color hex"},
                        "fillColor": {"type": "string", "description": "Fill color hex or 'transparent'"},
                        "strokeWidth": {"type": "number", "description": "Stroke thickness"},
                        "lineStyle": {"type": "string", "enum": ["solid", "dashed", "dotted"]},
                        "opacity": {"type": "number", "description": "Opacity 0-1"},
                        "fontSize": {"type": "number", "description": "Font size (14/18/24/32/48)"},
                        "fontFamily": {"type": "string", "description": "Font family (Virgil/Inter/Georgia/Courier New)"},
                        "shapeText": {"type": "string", "description": "Label inside shape"},
                        "shapeTextColor": {"type": "string", "description": "Shape label color"},
                        "shapeTextFontSize": {"type": "number", "description": "Shape label font size"},
                        "shapeTextFontFamily": {"type": "string", "description": "Font family for shape label text (e.g. Virgil, Inter, Georgia, Courier New)"},
                        "groupId": {"type": "string", "description": "Group ID for grouping elements"},
                        "points": {"type": "array", "description": "Freehand points [{x,y}]", "items": {"type": "object"}}
                    },
                    "required": ["type"]
                }
            },
            {
                "name": "draw_connector",
                "description": "Smart arrow/line between two shapes by index. Auto-connects nearest edges.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "from_index": {"type": "integer", "description": "Source element index"},
                        "to_index": {"type": "integer", "description": "Target element index"},
                        "type": {"type": "string", "enum": ["arrow", "line"], "description": "Connector type"},
                        "label": {"type": "string", "description": "Optional label on the connector"},
                        "color": {"type": "string", "description": "Connector color hex"},
                        "line_style": {"type": "string", "enum": ["solid", "dashed", "dotted"]}
                    },
                    "required": ["from_index", "to_index"]
                }
            },
            {
                "name": "draw_labeled_shape",
                "description": "Create an auto-sized shape with a centered label. Width auto-calculated from label length.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "shape": {"type": "string", "enum": ["rectangle", "circle", "diamond"], "description": "Shape type"},
                        "label": {"type": "string", "description": "Text label inside shape"},
                        "x": {"type": "number", "description": "X position"},
                        "y": {"type": "number", "description": "Y position"},
                        "color": {"type": "string", "description": "Stroke color hex"},
                        "fill_color": {"type": "string", "description": "Fill color hex or 'transparent'"},
                        "width": {"type": "number", "description": "Override auto-width"},
                        "height": {"type": "number", "description": "Override auto-height"}
                    },
                    "required": ["shape", "label", "x", "y"]
                }
            },
            {
                "name": "add_title",
                "description": "Add a large title text element at the specified position.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "text": {"type": "string", "description": "Title text"},
                        "x": {"type": "number", "description": "X position"},
                        "y": {"type": "number", "description": "Y position"}
                    },
                    "required": ["text"]
                }
            },
            {
                "name": "query_elements",
                "description": "Query canvas elements. Optionally filter by type or get by index.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "type": {"type": "string", "description": "Filter by element type"},
                        "index": {"type": "integer", "description": "Get element by index"}
                    }
                }
            },
            {
                "name": "update_element",
                "description": "Update properties of an existing canvas element by index.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer", "description": "Element index to update"},
                        "changes": {"type": "object", "description": "Property changes to apply"}
                    },
                    "required": ["index", "changes"]
                }
            },
            {
                "name": "delete_element",
                "description": "Delete element(s) by index or array of indices.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer", "description": "Single element index to delete"},
                        "indices": {"type": "array", "description": "Multiple indices to delete", "items": {"type": "integer"}}
                    }
                }
            },
            {
                "name": "clear_canvas",
                "description": "Clear ALL elements from the canvas.",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "get_viewport",
                "description": "Get current viewport state: zoom level, pan offset, canvas dimensions, and visible area.",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "get_canvas_snapshot",
                "description": "Get a JPEG screenshot of the current canvas as a base64 data URL. Use to visually verify what has been drawn.",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "get_bounding_box",
                "description": "Get the bounding box of all elements on the canvas. Useful for layout planning and finding free space.",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "get_canvas_elements",
                "description": "Fetch all canvas elements with defaults stripped for token efficiency. Non-default visual properties are preserved.",
                "inputSchema": {"type": "object", "properties": {}}
            },
            {
                "name": "render_elements",
                "description": "Atomically replace canvas content with a complete elements array. Clears existing, applies defaults, renders new diagram, and auto-fits viewport.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "elements": {"type": "array", "description": "Complete list of element objects to render", "items": {"type": "object"}}
                    },
                    "required": ["elements"]
                }
            },
            {
                "name": "get_drawing_guide",
                "description": "Get a JSON schema guide for element types, required fields, defaults, layout rules, colors, and rendering format. Use before designing diagrams.",
                "inputSchema": {"type": "object", "properties": {}}
            },
        ];
    }

    # ── Dispatch ──────────────────────────────────────────────────────────────

    def call_tool(name: str, args: dict) -> str {
        dispatch: dict = {
            "create_elements":   self._create_elements,
            "create_element":    self._create_element,
            "draw_connector":    self._draw_connector,
            "draw_labeled_shape": self._draw_labeled_shape,
            "add_title":         self._add_title,
            "query_elements":    self._query_elements,
            "update_element":    self._update_element,
            "delete_element":    self._delete_element,
            "clear_canvas":      self._clear_canvas,
            "get_viewport":      self._get_viewport,
            "get_canvas_snapshot": self._get_canvas_snapshot,
            "get_bounding_box":  self._get_bounding_box,
            "get_canvas_elements": self._get_canvas_elements,
            "render_elements":   self._render_elements,
            "get_drawing_guide": self._get_drawing_guide,
        };
        tool_fn: Any = dispatch.get(name);
        if tool_fn is None {
            return json.dumps({"error": f"Unknown tool: {name}"});
        }
        try {
            return tool_fn(args);
        } except Exception as error {
            return json.dumps({"error": str(error)});
        }
    }

    # ── Internal relay helper ─────────────────────────────────────────────────

    def _send(action: str, data: dict | None = None) -> Any {
        return self.send_fn(action, data);
    }

    # ── Shared helpers ────────────────────────────────────────────────────────

    def _apply_defaults(el: dict) -> dict {
        for (key, val) in {
            "color": "#1e1e1e",
            "strokeWidth": 2,
            "fillColor": "transparent",
            "lineStyle": "solid",
            "opacity": 1.0
        }.items() {
            el.setdefault(key, val);
        }
        if el.get("type") in ("rectangle", "circle", "diamond") {
            el.setdefault("width", 140);
            el.setdefault("height", 60);
        }
        if el.get("type") == "text" {
            el.setdefault("fontSize", 24);
            el.setdefault("fontFamily", "Virgil");
        }
        return el;
    }

    def _compute_edges(el: dict) -> dict {
        el_type: str = el.get("type", "");
        if el_type in ("rectangle", "circle", "diamond", "image") {
            x: float = el.get("x", 0);
            y: float = el.get("y", 0);
            w: float = el.get("width", 100);
            h: float = el.get("height", 60);
            return {
                "top":    {"x": x + w / 2, "y": y},
                "bottom": {"x": x + w / 2, "y": y + h},
                "left":   {"x": x,         "y": y + h / 2},
                "right":  {"x": x + w,     "y": y + h / 2}
            };
        }
        return {
            "top":    {"x": el.get("x", 0), "y": el.get("y", 0)},
            "bottom": {"x": el.get("x", 0), "y": el.get("y", 0) + 30}
        };
    }

    def _nearest_edge_points(source: dict, target: dict) -> tuple {
        source_edges: dict = self._compute_edges(source);
        target_edges: dict = self._compute_edges(target);
        best_dist: float = 999999.0;
        from_point: dict = {};
        to_point: dict = {};
        for from_side in ["top", "bottom", "left", "right"] {
            if from_side not in source_edges { continue; }
            for to_side in ["top", "bottom", "left", "right"] {
                if to_side not in target_edges { continue; }
                dist: float = math.sqrt(
                    (source_edges[from_side]["x"] - target_edges[to_side]["x"]) ** 2 +
                    (source_edges[from_side]["y"] - target_edges[to_side]["y"]) ** 2
                );
                if dist < best_dist {
                    best_dist = dist;
                    from_point = source_edges[from_side];
                    to_point = target_edges[to_side];
                }
            }
        }
        return (from_point, to_point);
    }

    # ── Binding resolution ────────────────────────────────────────────────────

    """Resolve startBinding/endBinding on an arrow to concrete x1,y1,x2,y2 coordinates.

    id_map must be a dict of element_id -> element dict (shapes only).
    Mutates el in-place and returns it. No-ops if bindings are missing or
    the referenced shapes aren't in id_map (LLM may have provided coords directly).
    """
    def _resolve_arrow_bindings(el: dict, id_map: dict) -> dict {
        if el.get("type") not in ("arrow", "line") { return el; }
        start_b: Any = el.get("startBinding");
        end_b: Any = el.get("endBinding");
        if not (start_b and end_b) { return el; }
        start_id: str = (start_b.get("elementId") if isinstance(start_b, dict) else "") or "";
        end_id: str = (end_b.get("elementId") if isinstance(end_b, dict) else "") or "";
        start_el: Any = id_map.get(start_id);
        end_el: Any = id_map.get(end_id);
        if not (start_el and end_el) { return el; }
        start_edges: dict = self._compute_edges(start_el);
        end_edges: dict = self._compute_edges(end_el);
        start_side: str = (start_b.get("side") if isinstance(start_b, dict) else "") or "right";
        end_side: str = (end_b.get("side") if isinstance(end_b, dict) else "") or "left";
        # Fall back to the nearest valid side if the LLM specified a diagonal like "top-right"
        valid_sides: list = ["top", "bottom", "left", "right"];
        if start_side not in start_edges { start_side = "right" if "right" in start_edges else valid_sides[0]; }
        if end_side not in end_edges { end_side = "left" if "left" in end_edges else valid_sides[0]; }
        from_pt: dict = start_edges[start_side];
        to_pt: dict = end_edges[end_side];
        el["x1"] = from_pt["x"];
        el["y1"] = from_pt["y"];
        el["x2"] = to_pt["x"];
        el["y2"] = to_pt["y"];
        return el;
    }

    # ── Tool implementations ──────────────────────────────────────────────────

    def _create_elements(args: dict) -> str {
        raw: list = [self._apply_defaults(dict(el)) for el in args.get("elements", [])];
        # Build a shape id_map from this batch so arrows can reference them
        id_map: dict = {el["id"]: el for el in raw if el.get("id") and el.get("type") not in ("arrow", "line", "text")};
        elements: list = [self._resolve_arrow_bindings(el, id_map) for el in raw];
        return json.dumps(self._send("addMultipleElements", {"elements": elements}));
    }

    def _create_element(args: dict) -> str {
        el: dict = {"type": args.get("type", "rectangle")};
        for (k, v) in args.items() {
            if k != "type" and v is not None {
                el[k] = v;
            }
        }
        return json.dumps(self._send("addElement", self._apply_defaults(el)));
    }

    def _draw_connector(args: dict) -> str {
        # getElements only filters by type; index into the returned list directly
        all_result: Any = self._send("getElements", {});
        if not (all_result and all_result.get("elements")) {
            return json.dumps({"error": "No elements on canvas"});
        }
        all_elements: list = all_result["elements"];
        from_index: int = args["from_index"];
        to_index: int = args["to_index"];
        if from_index >= len(all_elements) {
            return json.dumps({"error": f"No element at index {from_index}"});
        }
        if to_index >= len(all_elements) {
            return json.dumps({"error": f"No element at index {to_index}"});
        }
        from_el: dict = dict(all_elements[from_index]["element"]);
        to_el: dict = dict(all_elements[to_index]["element"]);
        (from_point, to_point) = self._nearest_edge_points(from_el, to_el);
        connector: dict = self._apply_defaults({
            "type": args.get("type", "arrow"),
            "x1": from_point["x"], "y1": from_point["y"],
            "x2": to_point["x"],   "y2": to_point["y"],
            "color": args.get("color", "#1e1e1e"),
            "lineStyle": args.get("line_style", "solid")
        });
        result: Any = self._send("addElement", connector);
        if args.get("label") {
            mid_x: float = (from_point["x"] + to_point["x"]) / 2;
            mid_y: float = (from_point["y"] + to_point["y"]) / 2 - 12;
            self._send("addElement", {
                "type": "text", "x": mid_x, "y": mid_y,
                "text": args["label"],
                "fontSize": 12, "fontFamily": "Virgil",
                "color": "#868e96", "strokeWidth": 1,
                "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0
            });
        }
        return json.dumps(result);
    }

    def _draw_labeled_shape(args: dict) -> str {
        label: str = args.get("label", "");
        shape: str = args.get("shape", "rectangle");
        width: int = int(args.get("width", 0)) or max(140, int(len(label) * 16 * 0.55) + 40);
        height: int = int(args.get("height", 0)) or (80 if shape == "diamond" else 60);
        if shape == "circle" {
            height = max(height, int(width * 0.6));
        }
        el: dict = self._apply_defaults({
            "type": shape,
            "x": args.get("x", 100), "y": args.get("y", 100),
            "width": width, "height": height,
            "shapeText": label, "shapeTextFontSize": 16,
            "color": args.get("color", "#1e1e1e"),
            "fillColor": args.get("fill_color", "transparent")
        });
        return json.dumps(self._send("addElement", el));
    }

    def _add_title(args: dict) -> str {
        el: dict = {
            "type": "text",
            "x": args.get("x", 100), "y": args.get("y", 40),
            "text": args.get("text", ""),
            "fontSize": 32, "fontFamily": "Virgil",
            "color": "#1e1e1e", "strokeWidth": 1,
            "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0
        };
        return json.dumps(self._send("addElement", el));
    }

    def _query_elements(args: dict) -> str {
        params: dict = {};
        if args.get("type") is not None { params["type"] = args["type"]; }
        result: Any = self._send("getElements", params);
        # getElements ignores index server-side; filter by index here if requested
        req_index: Any = args.get("index");
        if req_index is not None and result and result.get("elements") {
            elements: list = result["elements"];
            if req_index < len(elements) {
                return json.dumps({"elements": [elements[req_index]], "total": 1});
            }
            return json.dumps({"elements": [], "total": 0});
        }
        return json.dumps(result);
    }

    def _update_element(args: dict) -> str {
        # Canvas uses id-based updates; resolve index → id first
        all_result: Any = self._send("getElements", {});
        if not (all_result and all_result.get("elements")) {
            return json.dumps({"error": "No elements on canvas"});
        }
        elements: list = all_result["elements"];
        index: int = args["index"];
        if index >= len(elements) {
            return json.dumps({"error": f"No element at index {index}"});
        }
        element_id: str = str(elements[index]["id"]);
        return json.dumps(self._send("updateElement", {
            "id": element_id,
            "changes": args.get("changes", {})
        }));
    }

    def _delete_element(args: dict) -> str {
        # Canvas uses id-based deletes; resolve indices → ids first
        all_result: Any = self._send("getElements", {});
        if not (all_result and all_result.get("elements")) {
            return json.dumps({"error": "No elements on canvas"});
        }
        elements: list = all_result["elements"];
        indices: Any = args.get("indices");
        index: Any = args.get("index");
        if indices is not None and len(indices) > 0 {
            ids: list = [str(elements[i]["id"]) for i in indices if i < len(elements)];
            if not ids {
                return json.dumps({"error": "No valid indices provided"});
            }
            return json.dumps(self._send("removeMultipleElements", {"ids": ids}));
        }
        if index is not None {
            if index >= len(elements) {
                return json.dumps({"error": f"No element at index {index}"});
            }
            element_id: str = str(elements[index]["id"]);
            return json.dumps(self._send("removeElement", {"id": element_id}));
        }
        return json.dumps({"error": "Provide index or indices"});
    }

    def _clear_canvas(args: dict) -> str {
        return json.dumps(self._send("clearElements"));
    }

    def _get_viewport(args: dict) -> str {
        return json.dumps(self._send("getViewport"));
    }

    def _get_canvas_snapshot(args: dict) -> str {
        return json.dumps(self._send("getCanvasSnapshot"));
    }

    def _get_bounding_box(args: dict) -> str {
        return json.dumps(self._send("getBoundingBox"));
    }

    # ── New methods for multi-agent system ────────────────────────────────────
    """Remove fields that exactly equal their default values to reduce token count."""
    def _strip_defaults(el: dict) -> dict {
        defaults: dict = {
            "color": "#1e1e1e",
            "strokeWidth": 2,
            "fillColor": "transparent",
            "lineStyle": "solid",
            "opacity": 1.0,
            "rotation": 0,
            "boundElements": [],
            "groupId": None
        };
        shape_defaults: dict = {"width": 140, "height": 60};
        text_defaults: dict = {"fontSize": 24, "fontFamily": "Virgil"};

        # Always keep: id, type, x, y, width, height (positional/identity fields)
        result: dict = {
            k: el[k] for k in ["id", "type", "x", "y"]
            if k in el
        };

        # Keep width/height if present (even if == default, since they're structural)
        if "width" in el { result["width"] = el["width"]; }
        if "height" in el { result["height"] = el["height"]; }

        # Keep non-default visual fields
        for (key, default_val) in defaults.items() {
            if key in el and el[key] != default_val {
                result[key] = el[key];
            }
        }

        # Keep shape-specific defaults if non-default
        if el.get("type") in ("rectangle", "circle", "diamond") {
            for (key, default_val) in shape_defaults.items() {
                if key in el and el[key] != default_val {
                    result[key] = el[key];
                }
            }
        }

        # Keep text-specific defaults if non-default
        if el.get("type") == "text" {
            for (key, default_val) in text_defaults.items() {
                if key in el and el[key] != default_val {
                    result[key] = el[key];
                }
            }
        }

        # Always keep shape/text content fields if present and non-null
        for key in ["shapeText", "shapeTextColor", "shapeTextFontSize", "shapeTextFontFamily",
                    "points", "text", "curveStyle", "startBinding", "endBinding", "x1", "y1", "x2", "y2"] {
            if key in el and el[key] is not None {
                result[key] = el[key];
            }
        }

        return result;
    }

    """Fetch all canvas elements with defaults stripped for token efficiency."""
    def _get_canvas_elements(args: dict) -> str {
        result: Any = self._send("getElements", {});
        if not result or "elements" not in result {
            return json.dumps({"elements": [], "total": 0}, separators=(',', ':'));
        }
        # Strip {id, element} wrapper → plain element objects
        clean: list = [entry["element"] for entry in result["elements"]];
        stripped: list = [self._strip_defaults(el) for el in clean];
        return json.dumps({"elements": stripped, "total": len(stripped)}, separators=(',', ':'));
    }

    """Atomically replace canvas with a new elements[] array and auto-fit viewport."""
    def _render_elements(args: dict) -> str {
        raw: list = [self._apply_defaults(dict(el)) for el in args.get("elements", [])];
        # Build a shape id_map so arrows with startBinding/endBinding get x1,y1,x2,y2 resolved
        id_map: dict = {el["id"]: el for el in raw if el.get("id") and el.get("type") not in ("arrow", "line", "text")};
        elements: list = [self._resolve_arrow_bindings(el, id_map) for el in raw];
        self._send("setElements", {"elements": elements});
        return json.dumps({"action": "rendered", "count": len(elements)});
    }

    """Return a static JSON guide with element schema, defaults, layout rules, and colors."""
    def _get_drawing_guide(args: dict) -> str {
        guide: dict = {
            "element_types": ["rectangle", "circle", "diamond", "line", "arrow", "text", "freehand", "image"],
            "coordinate_system": "top-left origin, X right, Y down, canvas ~2000x1500",
            "required_fields": {
                "rectangle": ["type", "x", "y", "width", "height"],
                "circle": ["type", "x", "y", "width", "height"],
                "diamond": ["type", "x", "y", "width", "height"],
                "line": ["type", "startBinding", "endBinding"],
                "arrow": ["type", "startBinding", "endBinding"],
                "text": ["type", "x", "y", "text"],
                "freehand": ["type", "x", "y", "points"]
            },
            "arrow_binding": {
                "note": "Do NOT set x1/y1/x2/y2 or points on arrows — the server computes coordinates from bindings.",
                "startBinding": {"elementId": "<source-shape-id>", "side": "right"},
                "endBinding": {"elementId": "<target-shape-id>", "side": "left"},
                "valid_sides": ["top", "bottom", "left", "right"],
                "shape_boundElements": "List every connected arrow ID as a flat string array: [\"ar1\", \"ar2\"]"
            },
            "defaults": {
                "color": "#1e1e1e",
                "strokeWidth": 2,
                "fillColor": "transparent",
                "lineStyle": "solid",
                "opacity": 1.0,
                "rotation": 0,
                "fontSize": 24,
                "fontFamily": "Virgil",
                "shape_width": 140,
                "shape_height": 60
            },
            "layout_rules": {
                "min_shape_width": 140,
                "min_shape_height": 60,
                "horizontal_gap": 200,
                "vertical_gap": 150,
                "start_position": {"x": 100, "y": 100},
                "padding": 60
            },
            "curve_styles": {
                "sharp":  "Straight lines with V-angle bends — best for simple left-to-right flows and state machines",
                "curved": "Smooth quadratic arcs — best for mindmaps and organic relational diagrams",
                "elbow":  "Right-angle L/Z routing — best for architecture, flowchart, ER, and sequence diagrams (RECOMMENDED DEFAULT)"
            },
            "line_styles": {
                "solid":  "Direct dependency, mandatory data flow (default)",
                "dashed": "Optional, asynchronous, or event-driven connection",
                "dotted": "Annotation, inheritance hint, or conceptual/weak link"
            },
            "fill_palette": {
                "user_facing":    {"color": "#1971c2", "fillColor": "#e7f5ff",  "note": "client, browser, mobile"},
                "processing":     {"color": "#2b8a3e", "fillColor": "#ebfbee",  "note": "service, microservice, handler"},
                "storage":        {"color": "#0c8599", "fillColor": "#e3fafc",  "note": "database, cache, queue"},
                "gateway_router": {"color": "#e8590c", "fillColor": "#fff4e6",  "note": "API gateway, load balancer, proxy"},
                "async_queue":    {"color": "#9c36b5", "fillColor": "#f8f0fc",  "note": "message queue, event bus, topic"},
                "external":       {"color": "#868e96", "fillColor": "#f1f3f5",  "note": "third-party, external system"},
                "decision":       {"color": "#f08c00", "fillColor": "#fff9db",  "note": "condition, branch — use diamond shape"},
                "error_warning":  {"color": "#e03131", "fillColor": "#fff5f5",  "note": "error handler, dead-letter, alert"}
            },
            "shape_semantics": {
                "rectangle": "Standard process, service, component, module",
                "diamond":   "Decision point, condition, branch",
                "circle":    "Start/end terminal, actor, external entity"
            },
            "shape_labels": {
                "field": "shapeText",
                "color_field": "shapeTextColor",
                "fontSize_field": "shapeTextFontSize",
                "fontFamily_field": "shapeTextFontFamily"
            },
            "render_elements_format": "Call render_elements(elements: list) to atomically clear and render a complete diagram. Includes auto-fit viewport with 60px padding, capped at 2x zoom."
        };
        return json.dumps(guide);
    }
}
