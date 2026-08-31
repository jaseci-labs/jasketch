"""Turn a Mermaid flowchart into JaSketch elements.

Scope is FLOWCHARTS -- `graph` and `flowchart` -- because those map directly
onto what this canvas already draws: boxes, diamonds, circles and labelled
arrows. Sequence and class diagrams use a different layout model and are not
handled; `parse_mermaid` says so rather than producing something wrong.

Three stages, kept separate so each can be reasoned about on its own:

  parse_mermaid   text            -> {nodes, edges, direction}
  layout_graph    parsed          -> nodes gain x/y/width/height
  to_elements     laid-out graph  -> JaSketch elements ready for the canvas

The parser is deliberately forgiving. Mermaid that a human wrote by hand tends
to have stray whitespace, semicolons and blank lines, and refusing the whole
paste over one of those would be worse than ignoring the line.
"""

# Sizing. Nodes are made big enough for their label up front; the canvas will
# still grow a shape whose text does not fit, but starting close avoids every
# imported node visibly resizing itself on arrival.
glob MM_CHAR_WIDTH: float = 9.0;
glob MM_MIN_WIDTH: float = 120.0;
glob MM_MAX_WIDTH: float = 260.0;
glob MM_NODE_HEIGHT: float = 64.0;
glob MM_DIAMOND_PAD: float = 40.0;

# Spacing between layers, and between siblings within a layer.
glob MM_LAYER_GAP: float = 88.0;
glob MM_SIBLING_GAP: float = 48.0;


"""Strip a trailing comment and surrounding whitespace from one line."""
def _clean_line(raw: str) -> str {
    line = str(raw or "");
    hash_at = line.find("%%");
    if hash_at >= 0 {
        line = line[:hash_at];
    }
    return line.strip().rstrip(";");
}


"""The shape a Mermaid bracket pair asks for, and the label inside it.

Returns {"shape": str, "label": str} or None when the token carries no shape.
Order matters: `((round))` has to be tested before `(round)`, or the double
parens are read as a single pair wrapping a stray bracket."""
def _shape_from_token(token: str) -> any {
    t = str(token or "").strip();
    pairs = [
        ["((", "))", "circle"],
        ["([", "])", "rectangle"],
        ["[[", "]]", "rectangle"],
        ["{{", "}}", "diamond"],
        ["[/", "/]", "rectangle"],
        ["[\\", "\\]", "rectangle"],
        ["[", "]", "rectangle"],
        ["(", ")", "rectangle"],
        ["{", "}", "diamond"],
        [">", "]", "rectangle"]
    ];
    pi = 0;
    while pi < len(pairs) {
        opener = pairs[pi][0];
        closer = pairs[pi][1];
        if t.startswith(opener) and t.endswith(closer) and len(t) > len(opener) + len(closer) - 1 {
            inner = t[len(opener):len(t) - len(closer)];
            return {"shape": pairs[pi][2], "label": _unquote(inner)};
        }
        pi = pi + 1;
    }
    return None;
}


"""Mermaid allows quoting a label to protect punctuation; the quotes are not
part of the text."""
def _unquote(raw: str) -> str {
    s = str(raw or "").strip();
    if len(s) >= 2 {
        if (s.startswith("\"") and s.endswith("\"")) or (s.startswith("'") and s.endswith("'")) {
            return s[1:len(s) - 1].strip();
        }
    }
    return s;
}


"""Split one edge line into [left, connector, right], or None if it is not one.

Longest connectors first: `-->` contains `--`, so testing the short form first
would split every arrow in the wrong place and leave a stray `>` on the label."""
def _split_edge(line: str) -> any {
    connectors = [
        "==>", "-.->", "-.-", "--x", "--o", "-->", "---",
        "==", "-.", "--"
    ];
    ci = 0;
    while ci < len(connectors) {
        conn = connectors[ci];
        at = line.find(conn);
        if at > 0 {
            return [line[:at], conn, line[at + len(conn):]];
        }
        ci = ci + 1;
    }
    return None;
}


"""Pull an edge label out of either Mermaid spelling.

`A -->|yes| B` puts it after the connector; `A -- yes --> B` puts it before.
Returns {"label": str, "rest": str} where rest is the remaining right side."""
def _edge_label(right_side: str, left_side: str) -> any {
    right = str(right_side or "").strip();
    label = "";
    if right.startswith("|") {
        close_at = right.find("|", 1);
        if close_at > 0 {
            label = _unquote(right[1:close_at]);
            right = right[close_at + 1:].strip();
        }
    }
    return {"label": label, "rest": right};
}


"""Read a node reference: its id, and the shape/label if this is where it is
declared. `A[Start]` declares; a bare `A` later just refers to it."""
def _read_node(token: str) -> any {
    t = str(token or "").strip();
    if t == "" {
        return None;
    }
    # find where the shape bracket starts, if any
    open_at = -1;
    oi = 0;
    while oi < len(t) {
        ch = t[oi];
        if ch == "[" or ch == "(" or ch == "{" or ch == ">" {
            open_at = oi;
            oi = len(t);
        }
        oi = oi + 1;
    }
    if open_at <= 0 {
        return {"id": t, "shape": None, "label": None};
    }
    node_id = t[:open_at].strip();
    shaped = _shape_from_token(t[open_at:]);
    if not shaped {
        return {"id": t, "shape": None, "label": None};
    }
    return {"id": node_id, "shape": shaped["shape"], "label": shaped["label"]};
}



"""Read a Mermaid style declaration into the fields this canvas understands.

`fill:#bbf,stroke:#333,stroke-width:2px` becomes
{"fillColor": "#bbf", "color": "#333", "strokeWidth": 2}. Anything else in the
declaration is ignored rather than refused -- Mermaid styles carry plenty that
has no meaning on a hand-drawn canvas (font-weight, colour of the label, dash
arrays) and dropping those is better than dropping the whole line."""
def _parse_style(decl: str) -> any {
    out = {};
    pieces = str(decl or "").split(",");
    si = 0;
    while si < len(pieces) {
        bit = pieces[si].strip();
        colon = bit.find(":");
        if colon > 0 {
            key = bit[:colon].strip().lower();
            val = bit[colon + 1:].strip();
            if key == "fill" {
                out["fillColor"] = val;
            } elif key == "stroke" {
                out["color"] = val;
            } elif key == "stroke-width" {
                num = val.replace("px", "").strip();
                parsed_w = parseFloat(num);
                if parsed_w == parsed_w {
                    out["strokeWidth"] = parsed_w;
                }
            }
        }
        si = si + 1;
    }
    return out;
}


"""Parse Mermaid flowchart text.

Returns {"ok": bool, "error": str, "direction": str, "nodes": list, "edges": list}.
A diagram type we do not handle is reported as an error rather than parsed into
something plausible but wrong."""
def:pub parse_mermaid(source: str) -> any {
    text = str(source or "").strip();
    if text == "" {
        return {"ok": False, "error": "Nothing to import.", "direction": "TD", "nodes": [], "edges": []};
    }

    # Mermaid in the wild is often pasted inside a fenced code block.
    if text.startswith("```") {
        first_nl = text.find("\n");
        if first_nl > 0 {
            text = text[first_nl + 1:];
        }
        if text.rstrip().endswith("```") {
            text = text.rstrip()[:len(text.rstrip()) - 3];
        }
    }

    raw_lines = text.split("\n");
    direction = "TD";
    header_seen = False;
    node_order = [];
    node_map = {};
    edges = [];
    styles = {};       # node id -> style fields
    class_defs = {};   # class name -> style fields

    li = 0;
    while li < len(raw_lines) {
        line = _clean_line(raw_lines[li]);
        li = li + 1;
        if line == "" {
            continue;
        }

        lowered = line.lower();
        if not header_seen {
            if lowered.startswith("graph ") or lowered.startswith("flowchart ")
                or lowered == "graph" or lowered == "flowchart" {
                parts = line.split();
                if len(parts) > 1 {
                    direction = parts[1].strip().upper();
                }
                header_seen = True;
                continue;
            }
            # A diagram we do not draw. Say which, rather than guessing.
            known = ["sequencediagram", "classdiagram", "statediagram", "erdiagram",
                     "gantt", "pie", "journey", "mindmap", "timeline"];
            ki = 0;
            while ki < len(known) {
                if lowered.replace("-", "").startswith(known[ki]) {
                    return {
                        "ok": False,
                        "error": "Only flowcharts are supported so far. This looks like a " + parts_name(known[ki]) + ".",
                        "direction": "TD", "nodes": [], "edges": []
                    };
                }
                ki = ki + 1;
            }
        }

        # subgraph grouping is not drawn; its contents still are
        if lowered.startswith("subgraph") or lowered == "end" {
            continue;
        }
        # Styling. Mermaid carries colour three ways and all three are read:
        # a direct `style`, a named `classDef`, and `class` applying one.
        if lowered.startswith("style ") {
            body = line[6:].strip();
            gap = body.find(" ");
            if gap > 0 {
                styles[body[:gap].strip()] = _parse_style(body[gap + 1:]);
            }
            continue;
        }
        if lowered.startswith("classdef ") {
            body = line[9:].strip();
            gap = body.find(" ");
            if gap > 0 {
                class_defs[body[:gap].strip()] = _parse_style(body[gap + 1:]);
            }
            continue;
        }
        if lowered.startswith("class ") {
            body = line[6:].strip();
            gap = body.rfind(" ");
            if gap > 0 {
                cls = body[gap + 1:].strip();
                targets = body[:gap].split(",");
                ti = 0;
                while ti < len(targets) {
                    who = targets[ti].strip();
                    if who != "" and cls in class_defs {
                        styles[who] = class_defs[cls];
                    }
                    ti = ti + 1;
                }
            }
            continue;
        }
        if lowered.startswith("linkstyle ") or lowered.startswith("click ") {
            continue;
        }

        def remember(ref: any) -> None {
            if not ref or ref["id"] == "" {
                return;
            }
            if ref["id"] not in node_map {
                node_map[ref["id"]] = {
                    "id": ref["id"],
                    "label": ref["label"] or ref["id"],
                    "shape": ref["shape"] or "rectangle"
                };
                node_order.append(ref["id"]);
            } else {
                # A later declaration with a shape wins over an earlier bare
                # reference, which is how Mermaid itself behaves.
                if ref["shape"] {
                    node_map[ref["id"]]["shape"] = ref["shape"];
                }
                if ref["label"] {
                    node_map[ref["id"]]["label"] = ref["label"];
                }
            }
        }

        # An edge line may be a CHAIN: `A --> B --> C` declares two edges, and
        # taking only the first connector silently dropped everything past the
        # second node.
        chain_nodes = [];
        chain_conns = [];
        chain_labels = [];
        remaining = line;
        guard = 0;
        while guard < 40 {
            guard = guard + 1;
            step = _split_edge(remaining);
            if not step {
                chain_nodes.append(remaining);
                break;
            }
            left_part = step[0];
            conn = step[1];
            after = _edge_label(step[2], left_part);
            hop_label = after["label"];

            # `A -- yes --> B` puts the label before the connector instead
            if hop_label == "" {
                dash_at = left_part.find("--");
                if dash_at > 0 {
                    hop_label = _unquote(left_part[dash_at + 2:]);
                    left_part = left_part[:dash_at];
                }
            }
            chain_nodes.append(left_part);
            chain_conns.append(conn);
            chain_labels.append(hop_label);
            remaining = after["rest"];
        }

        if len(chain_conns) > 0 {
            refs = [];
            cni = 0;
            while cni < len(chain_nodes) {
                ref = _read_node(chain_nodes[cni]);
                refs.append(ref);
                remember(ref);
                cni = cni + 1;
            }
            hop = 0;
            while hop < len(chain_conns) {
                a_ref = refs[hop];
                b_ref = refs[hop + 1];
                if a_ref and b_ref and a_ref["id"] != "" and b_ref["id"] != "" {
                    conn = chain_conns[hop];
                    edges.append({
                        "from": a_ref["id"],
                        "to": b_ref["id"],
                        "label": chain_labels[hop],
                        "kind": (conn == "---" or conn == "--" or conn == "-.") and "line" or "arrow",
                        "style": (conn.find(".") >= 0) and "dashed" or "solid"
                    });
                }
                hop = hop + 1;
            }
            continue;
        }

        # a standalone declaration such as `A[Start]`
        solo = _read_node(line);
        if solo and solo["shape"] {
            remember(solo);
        }
    }

    if len(node_order) == 0 {
        return {"ok": False, "error": "No flowchart nodes found.", "direction": direction, "nodes": [], "edges": []};
    }

    nodes = [];
    ni = 0;
    while ni < len(node_order) {
        nodes.append(node_map[node_order[ni]]);
        ni = ni + 1;
    }
    ci2 = 0;
    while ci2 < len(nodes) {
        nodes[ci2]["style"] = styles[nodes[ci2]["id"]] or {};
        ci2 = ci2 + 1;
    }
    return {"ok": True, "error": "", "direction": direction, "nodes": nodes, "edges": edges};
}


"""A readable name for a diagram type we decline to draw."""
def parts_name(key: str) -> str {
    names = {
        "sequencediagram": "sequence diagram",
        "classdiagram": "class diagram",
        "statediagram": "state diagram",
        "erdiagram": "entity relationship diagram",
        "gantt": "Gantt chart",
        "pie": "pie chart",
        "journey": "user journey",
        "mindmap": "mind map",
        "timeline": "timeline"
    };
    return names[key] or "diagram";
}


"""Place the nodes in layers, and give each one a size that fits its label.

Layer assignment is longest-path: a node sits one layer below the deepest
parent that points at it, which is what makes a flowchart read top to bottom
without edges skipping backwards. Cycles are broken by refusing to revisit a
node, so a loop lays out rather than hanging."""
def:pub layout_graph(parsed: any, origin_x: float, origin_y: float) -> any {
    nodes = parsed["nodes"];
    edges = parsed["edges"];
    direction = (parsed["direction"] or "TD").upper();
    horizontal = direction == "LR" or direction == "RL";

    index_of = {};
    ii = 0;
    while ii < len(nodes) {
        index_of[nodes[ii]["id"]] = ii;
        # size first: the layer maths needs the extents
        label_len = len(str(nodes[ii]["label"] or ""));
        w = MM_MIN_WIDTH;
        measured = label_len * MM_CHAR_WIDTH + 32;
        if measured > w {
            w = measured;
        }
        if w > MM_MAX_WIDTH {
            w = MM_MAX_WIDTH;
        }
        h = MM_NODE_HEIGHT;
        if nodes[ii]["shape"] == "diamond" {
            w = w + MM_DIAMOND_PAD;
            h = h + MM_DIAMOND_PAD;
        }
        nodes[ii]["width"] = w;
        nodes[ii]["height"] = h;
        nodes[ii]["layer"] = 0;
        ii = ii + 1;
    }

    # longest-path layering, relaxed repeatedly; bounded by the node count so a
    # cycle cannot spin forever
    passes = 0;
    changed = True;
    while changed and passes <= len(nodes) {
        changed = False;
        ei = 0;
        while ei < len(edges) {
            a = index_of[edges[ei]["from"]];
            b = index_of[edges[ei]["to"]];
            if a != None and b != None and a != undefined and b != undefined {
                want = nodes[a]["layer"] + 1;
                if want > nodes[b]["layer"] {
                    nodes[b]["layer"] = want;
                    changed = True;
                }
            }
            ei = ei + 1;
        }
        passes = passes + 1;
    }

    # group by layer, preserving declaration order within each
    layers = {};
    max_layer = 0;
    mi = 0;
    while mi < len(nodes) {
        lay = nodes[mi]["layer"];
        if lay > max_layer {
            max_layer = lay;
        }
        if lay not in layers {
            layers[lay] = [];
        }
        layers[lay].append(mi);
        mi = mi + 1;
    }

    # position: layers advance along one axis, siblings spread along the other,
    # each layer centred on the widest so the diagram reads as a column
    widest = 0.0;
    lz = 0;
    while lz <= max_layer {
        row = layers[lz] or [];
        span = 0.0;
        ri = 0;
        while ri < len(row) {
            span = span + (horizontal and nodes[row[ri]]["height"] or nodes[row[ri]]["width"]);
            if ri < len(row) - 1 {
                span = span + MM_SIBLING_GAP;
            }
            ri = ri + 1;
        }
        if span > widest {
            widest = span;
        }
        lz = lz + 1;
    }

    depth = 0.0;
    lay_i = 0;
    while lay_i <= max_layer {
        row = layers[lay_i] or [];
        span = 0.0;
        tallest = 0.0;
        ri2 = 0;
        while ri2 < len(row) {
            span = span + (horizontal and nodes[row[ri2]]["height"] or nodes[row[ri2]]["width"]);
            if ri2 < len(row) - 1 {
                span = span + MM_SIBLING_GAP;
            }
            other = horizontal and nodes[row[ri2]]["width"] or nodes[row[ri2]]["height"];
            if other > tallest {
                tallest = other;
            }
            ri2 = ri2 + 1;
        }
        cursor = (widest - span) / 2;
        ri3 = 0;
        while ri3 < len(row) {
            n = nodes[row[ri3]];
            if horizontal {
                n["x"] = origin_x + depth;
                n["y"] = origin_y + cursor;
                cursor = cursor + n["height"] + MM_SIBLING_GAP;
            } else {
                n["x"] = origin_x + cursor;
                n["y"] = origin_y + depth;
                cursor = cursor + n["width"] + MM_SIBLING_GAP;
            }
            ri3 = ri3 + 1;
        }
        depth = depth + tallest + MM_LAYER_GAP;
        lay_i = lay_i + 1;
    }

    return parsed;
}


"""Turn a laid-out graph into canvas elements.

Connectors are bound to the shapes at both ends, so moving an imported node
drags its arrows with it exactly as a hand-drawn one would."""
def:pub to_elements(parsed: any, color: str, stroke_width: float, font_family: str, font_size: float) -> list {
    nodes = parsed["nodes"];
    edges = parsed["edges"];
    out = [];
    id_for = {};

    ni = 0;
    while ni < len(nodes) {
        n = nodes[ni];
        el_id = "mm-" + str(Date.now()) + "-" + str(ni);
        id_for[n["id"]] = el_id;
        # A node's own style wins over the panel defaults, per field, so a
        # diagram that colours only some nodes keeps the rest consistent with
        # whatever the user was drawing in.
        st = n["style"] or {};
        node_color = st["color"] or color;
        node_fill = st["fillColor"] or "transparent";
        node_stroke = st["strokeWidth"] or stroke_width;
        out.append({
            "id": el_id,
            "type": n["shape"],
            "x": n["x"],
            "y": n["y"],
            "width": n["width"],
            "height": n["height"],
            "color": node_color,
            "strokeWidth": node_stroke,
            "fillColor": node_fill,
            "lineStyle": "solid",
            "opacity": 1.0,
            "shapeText": n["label"],
            "shapeTextColor": node_color,
            "shapeTextFontSize": font_size,
            "shapeTextFontFamily": font_family
        });
        ni = ni + 1;
    }

    ei = 0;
    while ei < len(edges) {
        e = edges[ei];
        a_id = id_for[e["from"]];
        b_id = id_for[e["to"]];
        if a_id and b_id {
            a = None;
            b = None;
            fi = 0;
            while fi < len(nodes) {
                if nodes[fi]["id"] == e["from"] { a = nodes[fi]; }
                if nodes[fi]["id"] == e["to"] { b = nodes[fi]; }
                fi = fi + 1;
            }
            if a and b {
                # leave from the side facing the target, arrive on the facing side
                ax = a["x"] + a["width"] / 2;
                ay = a["y"] + a["height"];
                bx = b["x"] + b["width"] / 2;
                by = b["y"];
                a_side = "bottom";
                b_side = "top";
                if Math.abs(b["y"] - a["y"]) < 8 {
                    # same layer: go sideways instead of through each other
                    if b["x"] > a["x"] {
                        ax = a["x"] + a["width"]; ay = a["y"] + a["height"] / 2; a_side = "right";
                        bx = b["x"]; by = b["y"] + b["height"] / 2; b_side = "left";
                    } else {
                        ax = a["x"]; ay = a["y"] + a["height"] / 2; a_side = "left";
                        bx = b["x"] + b["width"]; by = b["y"] + b["height"] / 2; b_side = "right";
                    }
                } elif b["y"] < a["y"] {
                    ay = a["y"]; a_side = "top";
                    by = b["y"] + b["height"]; b_side = "bottom";
                }
                out.append({
                    "id": "mm-e-" + str(Date.now()) + "-" + str(ei),
                    "type": e["kind"],
                    "x1": ax, "y1": ay, "x2": bx, "y2": by,
                    "color": color,
                    "strokeWidth": stroke_width,
                    "lineStyle": e["style"],
                    "curveStyle": "curved",
                    "opacity": 1.0,
                    "startBinding": {"elementId": a_id, "side": a_side},
                    "endBinding": {"elementId": b_id, "side": b_side},
                    "shapeText": e["label"] or None,
                    "shapeTextColor": e["label"] and color or None,
                    "shapeTextFontSize": e["label"] and font_size or None,
                    "shapeTextFontFamily": e["label"] and font_family or None
                });
            }
        }
        ei = ei + 1;
    }
    return out;
}


"""Text in, elements out. Returns {"ok", "error", "elements"}."""
def:pub mermaid_to_elements(
    source: str, origin_x: float, origin_y: float,
    color: str, stroke_width: float, font_family: str, font_size: float
) -> any {
    parsed = parse_mermaid(source);
    if not parsed["ok"] {
        return {"ok": False, "error": parsed["error"], "elements": []};
    }
    laid = layout_graph(parsed, origin_x, origin_y);
    return {"ok": True, "error": "", "elements": to_elements(laid, color, stroke_width, font_family, font_size)};
}
