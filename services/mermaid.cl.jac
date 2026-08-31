"""Turn a Mermaid diagram into JaSketch elements.

Three kinds are handled, chosen because they map onto what this canvas already
draws -- boxes, circles, diamonds and labelled connectors -- without inventing
new primitives:

  flowchart   `graph` / `flowchart`      boxes, diamonds and labelled arrows
  state       `stateDiagram` / `-v2`     a directed graph, so it shares the
                                         flowchart pipeline exactly
  sequence    `sequenceDiagram`          NOT a graph: a row of participants and
                                         a script of messages down a timeline,
                                         so it has its own layout

Anything else -- pie, Gantt, Sankey, radar and the rest -- is declined BY NAME
rather than parsed into something plausible but wrong. Several of them cannot
be drawn honestly at all until the canvas can render arcs and filled polygons.

Stages, kept separate so each can be reasoned about on its own:

  diagram_kind    text            -> which of the three, or what to decline
  parse_*         text            -> {nodes, edges} or {participants, events}
  layout_graph    parsed          -> nodes gain x/y/width/height
  to_elements     laid-out graph  -> JaSketch elements ready for the canvas

  sequence_to_elements does its own layout and element building in one pass,
  because participant columns and message rows are decided together.

The parser is deliberately forgiving. Mermaid that a human wrote by hand tends
to have stray whitespace, semicolons and blank lines, and refusing the whole
paste over one of those would be worse than ignoring the line.
"""

# Sizing. A node is measured, not guessed: the label is rendered into an
# offscreen context at the real font and the box is built around it. Estimating
# by character count made every box too narrow for a handwriting face, so
# labels wrapped mid-word -- "Christmas" arriving as "Christm / as" -- which
# reads as broken rather than as a different style.
glob MM_LABEL_PAD_X: float = 34.0;
glob MM_MIN_WIDTH: float = 120.0;
glob MM_MAX_WIDTH: float = 280.0;
glob MM_NODE_HEIGHT: float = 62.0;
glob MM_DIAMOND_PAD_X: float = 64.0;
glob MM_DIAMOND_PAD_Y: float = 34.0;

# Spacing between layers, and between siblings within a layer.
# Layers are spaced generously ON PURPOSE. A connector label clears the line
# behind itself so the words are not struck through, and on a short arrow that
# knockout eats most of the line and the arrow reads as severed. Longer arrows
# leave room for the label and still look like arrows.
# How far apart to hold an A->B / B->A pair so both labels stay readable.
glob MM_PAIR_OFFSET: float = 27.0;

glob MM_STATE_DOT: float = 34.0;

# Sequence diagrams lay out on a different geometry entirely: participants in a
# row, time running downward. These are in the same world units as the rest.
glob MM_SEQ_BOX_H: float = 54.0;
glob MM_SEQ_GAP_X: float = 60.0;
glob MM_SEQ_MAX_GAP_X: float = 320.0;
glob MM_SEQ_MIN_BOX_W: float = 110.0;
glob MM_SEQ_MSG_GAP: float = 58.0;
glob MM_SEQ_TOP_PAD: float = 46.0;
glob MM_SEQ_SELF_W: float = 66.0;
glob MM_SEQ_SELF_H: float = 34.0;
glob MM_SEQ_NOTE_W: float = 158.0;
glob MM_SEQ_TAIL: float = 46.0;

# Longest first: at any position the longest token must win, or `-->>` would be
# read as `-->` with a stray `>`.
glob MM_SEQ_ARROWS: list = ["<<-->>", "<<->>", "-->>", "-->", "--x", "--)", "->>", "-x", "-)", "->"];

glob MM_SEQ_BLOCKS: list = ["loop", "alt", "else", "opt", "par", "and",
                            "critical", "option", "break", "rect"];

glob MM_LAYER_GAP: float = 128.0;
glob MM_SIBLING_GAP: float = 64.0;


"""Mermaid in the wild is often pasted inside a fenced code block."""
def _strip_fence(raw: str) -> str {
    text = str(raw or "").strip();
    if text.startswith("```") {
        first_nl = text.find("\n");
        if first_nl > 0 {
            text = text[first_nl + 1:];
        }
        if text.rstrip().endswith("```") {
            text = text.rstrip()[:len(text.rstrip()) - 3];
        }
    }
    return text.strip();
}


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
        ["[(", ")]", "rectangle"],   # cylinder / database
        ["([", "])", "rectangle"],   # stadium
        ["[[", "]]", "rectangle"],   # subroutine
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

    text = _strip_fence(text);

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
            known = ["classdiagram", "erdiagram", "gantt", "pie", "journey",
                     "mindmap", "timeline", "quadrantchart", "gitgraph",
                     "requirementdiagram", "sankey", "xychart", "block",
                     "packet", "architecture", "radar", "treemap", "kanban",
                     "c4context", "c4container", "c4component"];
            ki = 0;
            while ki < len(known) {
                if lowered.replace("-", "").startswith(known[ki]) {
                    return {
                        "ok": False,
                        "error": "This looks like a " + parts_name(known[ki]) + ". Flowcharts, state diagrams and sequence diagrams can be imported so far.",
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
        "classdiagram": "class diagram",
        "erdiagram": "entity relationship diagram",
        "gantt": "Gantt chart",
        "pie": "pie chart",
        "journey": "user journey",
        "mindmap": "mind map",
        "timeline": "timeline",
        "quadrantchart": "quadrant chart",
        "gitgraph": "Git graph",
        "requirementdiagram": "requirement diagram",
        "sankey": "Sankey diagram",
        "xychart": "XY chart",
        "block": "block diagram",
        "packet": "packet diagram",
        "architecture": "architecture diagram",
        "radar": "radar chart",
        "treemap": "treemap",
        "kanban": "Kanban board",
        "c4context": "C4 diagram",
        "c4container": "C4 diagram",
        "c4component": "C4 diagram"
    };
    return names[key] or "diagram";
}


"""Which edges close a loop, and so must not push anything further down.

A cycle in a flowchart is normal -- a retry arrow going back to a check -- but
longest-path layering has no answer for it: each pass round the loop pushes both
nodes one layer further, so a diagram with a retry arrow spread itself across
thousands of pixels instead of a few hundred.

A depth-first walk marks any edge pointing at a node still on the current path
as a back edge. Those are drawn, but they take no part in deciding what sits
below what."""
def _back_edges(node_count: int, edges: list, index_of: any) -> any {
    out_edges = {};
    ei = 0;
    while ei < len(edges) {
        a = index_of[edges[ei]["from"]];
        if a != None and a != undefined {
            if a not in out_edges {
                out_edges[a] = [];
            }
            out_edges[a].append(ei);
        }
        ei = ei + 1;
    }

    # 0 unvisited, 1 on the current path, 2 finished
    state = [];
    si = 0;
    while si < node_count {
        state.append(0);
        si = si + 1;
    }
    back = {};

    # Not `root`: like `node` and `skip`, it is a built-in reference in Jac and
    # cannot be used as a variable name.
    seed = 0;
    while seed < node_count {
        if state[seed] == 0 {
            # explicit stack of [node index, position in its edge list]
            stack = [[seed, 0]];
            state[seed] = 1;
            while len(stack) > 0 {
                top = stack[len(stack) - 1];
                here = top[0];
                mine = out_edges[here] or [];
                if top[1] >= len(mine) {
                    state[here] = 2;
                    stack.pop();
                    continue;
                }
                edge_i = mine[top[1]];
                top[1] = top[1] + 1;
                nxt = index_of[edges[edge_i]["to"]];
                if nxt == None or nxt == undefined {
                    continue;
                }
                if state[nxt] == 1 {
                    back[edge_i] = True;     # points back up the current path
                } elif state[nxt] == 0 {
                    state[nxt] = 1;
                    stack.append([nxt, 0]);
                }
            }
        }
        seed = seed + 1;
    }
    return back;
}


"""How wide the label really is, at the font it will be drawn in.

A detached canvas is enough: measureText needs a context, not a visible one."""
def:pub measure_label(text: str, font_size: float, font_family: str) -> float {
    probe = document.createElement("canvas");
    ctx = probe.getContext("2d");
    if not ctx {
        return len(str(text or "")) * font_size * 0.55;
    }
    ctx.font = font_size + "px " + font_family;
    return ctx.measureText(str(text or "")).width;
}


"""Place the nodes in layers, and give each one a size that fits its label.

Layer assignment is longest-path: a node sits one layer below the deepest
parent that points at it, which is what makes a flowchart read top to bottom
without edges skipping backwards. Cycles are broken by refusing to revisit a
node, so a loop lays out rather than hanging."""
def:pub layout_graph(parsed: any, origin_x: float, origin_y: float, font_size: float, font_family: str) -> any {
    nodes = parsed["nodes"];
    edges = parsed["edges"];
    direction = (parsed["direction"] or "TD").upper();
    horizontal = direction == "LR" or direction == "RL";

    index_of = {};
    ii = 0;
    while ii < len(nodes) {
        index_of[nodes[ii]["id"]] = ii;
        # size first: the layer maths needs the extents
        text_w = measure_label(nodes[ii]["label"], font_size, font_family);
        w = text_w + MM_LABEL_PAD_X * 2;
        if w < MM_MIN_WIDTH {
            w = MM_MIN_WIDTH;
        }
        h = MM_NODE_HEIGHT;
        if w > MM_MAX_WIDTH {
            # Too long for one line: let it wrap, and give it the height to do
            # so rather than pushing the words outside the box.
            w = MM_MAX_WIDTH;
            lines = Math.ceil(text_w / (MM_MAX_WIDTH - MM_LABEL_PAD_X * 2));
            h = MM_NODE_HEIGHT + (lines - 1) * font_size * 1.3;
        }
        if nodes[ii]["shape"] == "diamond" {
            # A diamond only has its full width across the middle, so the label
            # needs noticeably more room than the same text in a box.
            w = w + MM_DIAMOND_PAD_X;
            h = h + MM_DIAMOND_PAD_Y;
        }
        if nodes[ii]["fixed_size"] {
            # A state diagram's start and end pseudostates are dots, not boxes:
            # sizing them from an empty label would give a 120px circle.
            w = nodes[ii]["fixed_size"];
            h = nodes[ii]["fixed_size"];
        }
        nodes[ii]["width"] = w;
        nodes[ii]["height"] = h;
        nodes[ii]["layer"] = 0;
        ii = ii + 1;
    }

    # longest-path layering over the acyclic part only
    # `skip` is a reserved word in Jac.
    loop_edges = _back_edges(len(nodes), edges, index_of);
    passes = 0;
    changed = True;
    while changed and passes <= len(nodes) {
        changed = False;
        ei = 0;
        while ei < len(edges) {
            a = index_of[edges[ei]["from"]];
            b = index_of[edges[ei]["to"]];
            if not loop_edges[ei] and a != None and b != None and a != undefined and b != undefined {
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
    # Which way the layers advance decides which FACE an edge should leave from.
    # Without this every edge was routed bottom-to-top, which is right for TD and
    # draws a diagonal straight through the shapes in LR.
    direction = (parsed["direction"] or "TD").upper();
    horizontal = direction == "LR" or direction == "RL";
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

    # A -> B and B -> A land on exactly the same line, so one label sits on top
    # of the other and reads as missing. State machines are full of these pairs
    # (retry loops, toggles), so each is nudged to its own side of the run.
    has_reverse = {};
    ri = 0;
    while ri < len(edges) {
        has_reverse[edges[ri]["from"] + " " + edges[ri]["to"]] = True;
        ri = ri + 1;
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
                # Leave from the face pointing at the target, arrive on the
                # face pointing back. Which axis counts as "forward" depends on
                # the layout direction, not on the shapes.
                if horizontal {
                    ax = a["x"] + a["width"]; ay = a["y"] + a["height"] / 2;
                    bx = b["x"]; by = b["y"] + b["height"] / 2;
                    a_side = "right"; b_side = "left";
                    if Math.abs(b["x"] - a["x"]) < 8 {
                        # Same column in a sideways layout: go up or down
                        # instead of doubling back through both shapes.
                        if b["y"] > a["y"] {
                            ax = a["x"] + a["width"] / 2; ay = a["y"] + a["height"]; a_side = "bottom";
                            bx = b["x"] + b["width"] / 2; by = b["y"]; b_side = "top";
                        } else {
                            ax = a["x"] + a["width"] / 2; ay = a["y"]; a_side = "top";
                            bx = b["x"] + b["width"] / 2; by = b["y"] + b["height"]; b_side = "bottom";
                        }
                    } elif b["x"] < a["x"] {
                        # A back edge, so face the other way.
                        ax = a["x"]; ay = a["y"] + a["height"] / 2; a_side = "left";
                        bx = b["x"] + b["width"]; by = b["y"] + b["height"] / 2; b_side = "right";
                    }
                } else {
                    ax = a["x"] + a["width"] / 2; ay = a["y"] + a["height"];
                    bx = b["x"] + b["width"] / 2; by = b["y"];
                    a_side = "bottom"; b_side = "top";
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
                }
                if has_reverse[e["to"] + " " + e["from"]] {
                    # Perpendicular to this edge's own direction, so the
                    # opposing edge derives the opposite normal and the two
                    # separate instead of both shifting the same way.
                    dx = bx - ax;
                    dy = by - ay;
                    run = Math.sqrt(dx * dx + dy * dy);
                    if run > 0.5 {
                        ox = (0 - dy) / run * MM_PAIR_OFFSET;
                        oy = dx / run * MM_PAIR_OFFSET;
                        ax = ax + ox; ay = ay + oy;
                        bx = bx + ox; by = by + oy;
                    }
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


"""Which kind of Mermaid diagram this is, by its opening keyword.

Returns "flowchart", "state", "sequence", or the lowercased keyword of
something we do not draw, so the caller can name it in the error."""
def:pub diagram_kind(source: str) -> str {
    text = _strip_fence(str(source or "").strip());
    lines = text.split("\n");
    li = 0;
    while li < len(lines) {
        line = _clean_line(lines[li]);
        li = li + 1;
        if line == "" {
            continue;
        }
        lowered = line.lower().replace("-", "");
        if lowered.startswith("graph") or lowered.startswith("flowchart") {
            return "flowchart";
        }
        if lowered.startswith("statediagram") {
            return "state";
        }
        if lowered.startswith("sequencediagram") {
            return "sequence";
        }
        # First non-blank line is the header in every Mermaid dialect.
        space = lowered.find(" ");
        if space > 0 {
            return lowered[:space];
        }
        return lowered;
    }
    return "";
}


"""Parse a Mermaid state diagram into the same nodes and edges a flowchart
produces, so it goes straight through layout_graph and to_elements unchanged.

A state machine IS a directed graph, so none of the layout has to know the
difference. Only the grammar differs: `-->` is the only connector, the label
comes after a colon instead of inside pipes, and `[*]` is a pseudostate meaning
the start when it is the source and the end when it is the target."""
def:pub parse_state(source: str) -> any {
    text = _strip_fence(str(source or "").strip());
    if text == "" {
        return {"ok": False, "error": "Nothing to import.", "direction": "TD", "nodes": [], "edges": []};
    }

    raw_lines = text.split("\n");
    direction = "TD";
    node_order = [];
    node_map = {};
    edges = [];
    in_note = False;

    def touch(state_id: str, label: any, dot: any) -> None {
        if state_id == "" {
            return;
        }
        if state_id not in node_map {
            # Explicit, not `label or state_id`: the pseudostate dots carry an
            # EMPTY label on purpose, and `or` would fall back to the id and
            # caption them __start__ and __end__.
            shown = state_id;
            if label != None {
                shown = label;
            }
            node_map[state_id] = {
                "id": state_id,
                "label": shown,
                "shape": dot and "circle" or "rectangle",
                "style": {},
                "fixed_size": dot
            };
            node_order.append(state_id);
        } elif label {
            node_map[state_id]["label"] = label;
        }
    }

    # `[*]` is not one state. As a source it is the start, as a target the end.
    def resolve(token: str, is_target: bool) -> str {
        t = str(token or "").strip();
        if t == "" {
            return "";
        }
        if t == "[*]" {
            if is_target {
                touch("__end__", "", MM_STATE_DOT);
                return "__end__";
            }
            touch("__start__", "", MM_STATE_DOT);
            return "__start__";
        }
        touch(t, None, None);
        return t;
    }

    li = 0;
    while li < len(raw_lines) {
        line = _clean_line(raw_lines[li]);
        li = li + 1;
        if line == "" {
            continue;
        }
        lowered = line.lower();

        if in_note {
            if lowered == "end note" {
                in_note = False;
            }
            continue;
        }
        if lowered.replace("-", "").startswith("statediagram") {
            continue;
        }
        if lowered.startswith("direction ") {
            bits = line.split();
            if len(bits) > 1 {
                direction = bits[1].strip().upper();
            }
            continue;
        }
        if lowered.startswith("note ") or lowered.startswith("note:") {
            # A one-line note carries its text after a colon; a block note runs
            # until `end note`. Neither is drawn.
            if line.find(":") < 0 {
                in_note = True;
            }
            continue;
        }
        # Composite states are flattened: the brace lines carry no transition,
        # and the inner transitions are read exactly like the outer ones.
        if lowered == "}" or lowered == "--" {
            continue;
        }

        if lowered.startswith("state ") {
            body = line[6:].strip();
            if body.endswith("{") {
                body = body[:len(body) - 1].strip();
            }
            as_at = body.lower().find(" as ");
            if as_at > 0 {
                touch(body[as_at + 4:].strip(), _unquote(body[:as_at].strip()), None);
            } else {
                bare = body.replace("<<fork>>", "").replace("<<join>>", "");
                bare = bare.replace("<<choice>>", "").replace("<<end>>", "").strip();
                if bare != "" {
                    touch(bare, None, None);
                }
            }
            continue;
        }

        arrow_at = line.find("-->");
        if arrow_at < 0 {
            continue;
        }
        left = line[:arrow_at].strip();
        rest = line[arrow_at + 3:].strip();
        label = None;
        colon = rest.find(":");
        if colon >= 0 {
            label = rest[colon + 1:].strip();
            rest = rest[:colon].strip();
        }
        from_id = resolve(left, False);
        to_id = resolve(rest, True);
        if from_id != "" and to_id != "" {
            edges.append({
                "from": from_id, "to": to_id, "label": label,
                "kind": "arrow", "style": "solid"
            });
        }
    }

    if len(node_order) == 0 {
        return {"ok": False, "error": "No states found.", "direction": direction, "nodes": [], "edges": []};
    }

    nodes = [];
    ni = 0;
    while ni < len(node_order) {
        nodes.append(node_map[node_order[ni]]);
        ni = ni + 1;
    }
    return {"ok": True, "error": "", "direction": direction, "nodes": nodes, "edges": edges};
}


"""The first message arrow on a line, and where it starts.

Scans left to right testing the longest token first, so `-->>` is never read
as `-->` followed by a stray `>`."""
def _seq_arrow_at(line: str) -> any {
    pos = 0;
    while pos < len(line) {
        ai = 0;
        while ai < len(MM_SEQ_ARROWS) {
            tok = MM_SEQ_ARROWS[ai];
            if line[pos:pos + len(tok)] == tok {
                return {"at": pos, "token": tok};
            }
            ai = ai + 1;
        }
        pos = pos + 1;
    }
    return None;
}


"""Parse a Mermaid sequence diagram.

Returns {"ok", "error", "participants", "events"}. Unlike a flowchart this is
not a graph: it is a row of participants and an ordered script of things that
happen between them, so it gets its own layout rather than reusing
layout_graph."""
def:pub parse_sequence(source: str) -> any {
    text = _strip_fence(str(source or "").strip());
    if text == "" {
        return {"ok": False, "error": "Nothing to import.", "participants": [], "events": []};
    }

    raw_lines = text.split("\n");
    participants = [];
    p_index = {};
    events = [];

    def add_participant(pid: any, label: any) -> str {
        p = str(pid or "").strip();
        if p == "" {
            return "";
        }
        if p not in p_index {
            shown = p;
            if label != None and label != "" {
                shown = label;
            }
            p_index[p] = len(participants);
            participants.append({"id": p, "label": shown});
        } elif label {
            participants[p_index[p]]["label"] = label;
        }
        return p;
    }

    li = 0;
    while li < len(raw_lines) {
        line = _clean_line(raw_lines[li]);
        li = li + 1;
        if line == "" {
            continue;
        }
        lowered = line.lower();

        if lowered.startswith("sequencediagram") or lowered.startswith("autonumber") {
            continue;
        }
        # Activation bars are not drawn; the messages that carry them still are.
        if lowered.startswith("activate ") or lowered.startswith("deactivate ") {
            continue;
        }
        if lowered == "end" {
            continue;
        }

        if lowered.startswith("participant ") or lowered.startswith("actor ") {
            body = line[12:].strip() if lowered.startswith("participant ") else line[6:].strip();
            as_at = body.lower().find(" as ");
            if as_at > 0 {
                add_participant(body[:as_at].strip(), _unquote(body[as_at + 4:].strip()));
            } else {
                add_participant(body, None);
            }
            continue;
        }

        if lowered.startswith("note ") {
            body = line[5:].strip();
            colon = body.find(":");
            note_text = "";
            head = body;
            if colon >= 0 {
                note_text = body[colon + 1:].strip();
                head = body[:colon].strip();
            }
            headl = head.lower();
            side = "over";
            who = head;
            if headl.startswith("right of ") {
                side = "right"; who = head[9:];
            } elif headl.startswith("left of ") {
                side = "left"; who = head[8:];
            } elif headl.startswith("over ") {
                side = "over"; who = head[5:];
            }
            targets = [];
            for piece in str(who or "").split(",") {
                got = add_participant(piece.strip(), None);
                if got != "" {
                    targets.append(got);
                }
            }
            if len(targets) > 0 {
                events.append({"kind": "note", "side": side, "who": targets, "label": note_text});
            }
            continue;
        }

        # loop / alt / else / opt / par: the frame is not drawn, but dropping the
        # label silently would change what the diagram MEANS, so it is kept as a
        # marker down the left-hand side.
        first_word = lowered.split()[0] if len(lowered.split()) > 0 else "";
        if first_word in MM_SEQ_BLOCKS {
            events.append({"kind": "block", "label": line});
            continue;
        }

        found = _seq_arrow_at(line);
        if not found {
            continue;
        }
        token = found["token"];
        left = line[:found["at"]].strip();
        rest = line[found["at"] + len(token):];
        label = "";
        colon2 = rest.find(":");
        if colon2 >= 0 {
            label = rest[colon2 + 1:].strip();
            rest = rest[:colon2];
        }
        right = rest.strip();
        # `A->>+B` / `B-->>-A` activate and deactivate; the marker is not a name.
        if right.startswith("+") or right.startswith("-") {
            right = right[1:].strip();
        }
        from_id = add_participant(left, None);
        to_id = add_participant(right, None);
        if from_id == "" or to_id == "" {
            continue;
        }
        has_head = token.endswith(">>") or token.endswith(")") or token.endswith("x");
        events.append({
            "kind": "message",
            "from": from_id,
            "to": to_id,
            "label": label,
            "style": (token.find("--") >= 0) and "dashed" or "solid",
            "element": has_head and "arrow" or "line"
        });
        li = li;
    }

    if len(participants) == 0 {
        return {"ok": False, "error": "No participants found.", "participants": [], "events": []};
    }
    return {"ok": True, "error": "", "participants": participants, "events": events};
}


"""Turn a parsed sequence diagram into canvas elements.

Participants sit in a row with a dashed lifeline dropping from each, and time
runs downward. Messages are deliberately NOT bound to the participant boxes:
a binding would re-route them onto the box edges and collapse the timeline,
which is the one thing a sequence diagram cannot lose."""
def:pub sequence_to_elements(
    parsed: any, origin_x: float, origin_y: float,
    color: str, stroke_width: float, font_family: str, font_size: float
) -> list {
    participants = parsed["participants"];
    events = parsed["events"];
    out = [];
    if len(participants) == 0 {
        return out;
    }

    stamp = str(Date.now());
    seq = 0;

    def next_id(tag: str) -> str {
        seq = seq + 1;
        return "mm-" + tag + "-" + stamp + "-" + str(seq);
    }

    # Column widths come from the participant names.
    widths = [];
    pi = 0;
    while pi < len(participants) {
        w = measure_label(participants[pi]["label"], font_size, font_family) + MM_LABEL_PAD_X * 2;
        if w < MM_SEQ_MIN_BOX_W {
            w = MM_SEQ_MIN_BOX_W;
        }
        widths.append(w);
        pi = pi + 1;
    }

    # The gap has to hold the widest message label, or the text of one message
    # runs across the lifeline of the next participant.
    gap = MM_SEQ_GAP_X;
    ei = 0;
    while ei < len(events) {
        if events[ei]["kind"] == "message" and events[ei]["label"] != "" {
            lw = measure_label(events[ei]["label"], font_size, font_family) + 28;
            if lw > gap {
                gap = lw;
            }
        }
        ei = ei + 1;
    }
    if gap > MM_SEQ_MAX_GAP_X {
        gap = MM_SEQ_MAX_GAP_X;
    }

    xs = [];
    centers = [];
    index_of = {};
    cursor = origin_x;
    pi = 0;
    while pi < len(participants) {
        index_of[participants[pi]["id"]] = pi;
        xs.append(cursor);
        centers.append(cursor + widths[pi] / 2);
        cursor = cursor + widths[pi] + gap;
        pi = pi + 1;
    }

    # Place events on the timeline first, so the lifelines know how far to run.
    lane_y = origin_y + MM_SEQ_BOX_H + MM_SEQ_TOP_PAD;
    placed = [];
    ei = 0;
    while ei < len(events) {
        ev = events[ei];
        placed.append({"ev": ev, "y": lane_y});
        if ev["kind"] == "message" and ev["from"] == ev["to"] {
            lane_y = lane_y + MM_SEQ_SELF_H + MM_SEQ_MSG_GAP;
        } elif ev["kind"] == "note" {
            lane_y = lane_y + MM_SEQ_MSG_GAP + 18;
        } else {
            lane_y = lane_y + MM_SEQ_MSG_GAP;
        }
        ei = ei + 1;
    }
    bottom = lane_y + MM_SEQ_TAIL;

    # Participant boxes.
    pi = 0;
    while pi < len(participants) {
        out.append({
            "id": next_id("p"),
            "type": "rectangle",
            "x": xs[pi], "y": origin_y,
            "width": widths[pi], "height": MM_SEQ_BOX_H,
            "color": color, "strokeWidth": stroke_width,
            "fillColor": "transparent", "lineStyle": "solid", "opacity": 1.0,
            "shapeText": participants[pi]["label"],
            "shapeTextColor": color,
            "shapeTextFontSize": font_size,
            "shapeTextFontFamily": font_family
        });
        pi = pi + 1;
    }

    # Lifelines.
    pi = 0;
    while pi < len(participants) {
        out.append({
            "id": next_id("ll"),
            "type": "line",
            "x1": centers[pi], "y1": origin_y + MM_SEQ_BOX_H,
            "x2": centers[pi], "y2": bottom,
            "color": color, "strokeWidth": stroke_width,
            "lineStyle": "dashed", "curveStyle": "straight", "opacity": 1.0
        });
        pi = pi + 1;
    }

    def label_bits(txt: any) -> any {
        if not txt or txt == "" {
            return {"t": None, "c": None, "s": None, "f": None};
        }
        return {"t": txt, "c": color, "s": font_size, "f": font_family};
    }

    ei = 0;
    while ei < len(placed) {
        ev = placed[ei]["ev"];
        y = placed[ei]["y"];

        if ev["kind"] == "block" {
            out.append({
                "id": next_id("blk"),
                "type": "text",
                "x": origin_x, "y": y - font_size - 12,
                "text": ev["label"],
                "color": color,
                "fontSize": font_size * 0.8,
                "fontFamily": font_family,
                "opacity": 0.75
            });
            ei = ei + 1;
            continue;
        }

        if ev["kind"] == "note" {
            first = index_of[ev["who"][0]];
            last = first;
            wi = 0;
            while wi < len(ev["who"]) {
                idx = index_of[ev["who"][wi]];
                if idx != None and idx != undefined {
                    if idx < first { first = idx; }
                    if idx > last { last = idx; }
                }
                wi = wi + 1;
            }
            nx = centers[first] + 22;
            nw = MM_SEQ_NOTE_W;
            if ev["side"] == "left" {
                nx = centers[first] - 22 - MM_SEQ_NOTE_W;
            } elif ev["side"] == "over" {
                nx = centers[first] - 46;
                nw = centers[last] - centers[first] + 92;
                if nw < MM_SEQ_NOTE_W { nw = MM_SEQ_NOTE_W; }
            }
            out.append({
                "id": next_id("note"),
                "type": "rectangle",
                "x": nx, "y": y - 20,
                "width": nw, "height": 46,
                "color": color, "strokeWidth": stroke_width,
                "fillColor": "transparent", "lineStyle": "dashed", "opacity": 1.0,
                "shapeText": ev["label"],
                "shapeTextColor": color,
                "shapeTextFontSize": font_size * 0.85,
                "shapeTextFontFamily": font_family
            });
            ei = ei + 1;
            continue;
        }

        a = index_of[ev["from"]];
        b = index_of[ev["to"]];
        if a == None or b == None or a == undefined or b == undefined {
            ei = ei + 1;
            continue;
        }
        bits = label_bits(ev["label"]);

        if a == b {
            # A message to itself: out, down, and back, so it reads as a loop
            # rather than a zero-length arrow hidden inside the lifeline.
            cx = centers[a];
            out.append({
                "id": next_id("m"), "type": "line",
                "x1": cx, "y1": y, "x2": cx + MM_SEQ_SELF_W, "y2": y,
                "color": color, "strokeWidth": stroke_width,
                "lineStyle": ev["style"], "curveStyle": "straight", "opacity": 1.0
            });
            out.append({
                "id": next_id("m"), "type": "line",
                "x1": cx + MM_SEQ_SELF_W, "y1": y,
                "x2": cx + MM_SEQ_SELF_W, "y2": y + MM_SEQ_SELF_H,
                "color": color, "strokeWidth": stroke_width,
                "lineStyle": ev["style"], "curveStyle": "straight", "opacity": 1.0
            });
            out.append({
                "id": next_id("m"), "type": ev["element"],
                "x1": cx + MM_SEQ_SELF_W, "y1": y + MM_SEQ_SELF_H,
                "x2": cx, "y2": y + MM_SEQ_SELF_H,
                "color": color, "strokeWidth": stroke_width,
                "lineStyle": ev["style"], "curveStyle": "straight", "opacity": 1.0,
                "shapeText": bits["t"], "shapeTextColor": bits["c"],
                "shapeTextFontSize": bits["s"], "shapeTextFontFamily": bits["f"]
            });
        } else {
            out.append({
                "id": next_id("m"), "type": ev["element"],
                "x1": centers[a], "y1": y, "x2": centers[b], "y2": y,
                "color": color, "strokeWidth": stroke_width,
                "lineStyle": ev["style"], "curveStyle": "straight", "opacity": 1.0,
                "shapeText": bits["t"], "shapeTextColor": bits["c"],
                "shapeTextFontSize": bits["s"], "shapeTextFontFamily": bits["f"]
            });
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
    kind = diagram_kind(source);

    # A sequence diagram is a timeline, not a graph, so it gets its own layout.
    if kind == "sequence" {
        seq = parse_sequence(source);
        if not seq["ok"] {
            return {"ok": False, "error": seq["error"], "elements": []};
        }
        return {
            "ok": True, "error": "",
            "elements": sequence_to_elements(
                seq, origin_x, origin_y, color, stroke_width, font_family, font_size
            )
        };
    }

    # A state machine is a directed graph, so it shares the flowchart pipeline.
    parsed = None;
    if kind == "state" {
        parsed = parse_state(source);
    } else {
        parsed = parse_mermaid(source);
    }
    if not parsed["ok"] {
        return {"ok": False, "error": parsed["error"], "elements": []};
    }
    laid = layout_graph(parsed, origin_x, origin_y, font_size, font_family);
    return {"ok": True, "error": "", "elements": to_elements(laid, color, stroke_width, font_family, font_size)};
}
