"""Alignment snapping: pull a dragged shape onto its neighbours.

While a shape is being dragged its edges and centres are compared against every
other shape on the canvas. When one comes within SNAP_THRESHOLD the drag is
nudged the last few pixels so the two line up exactly, and a guide is reported
so the canvas can show WHY the shape stopped where it did.

Without this, every box in a diagram sits two or three pixels off its
neighbour, and the only way to correct it is to nudge with the arrow keys one
pixel at a time.

Distances here are in world units, so a snap feels the same at every zoom level
-- the caller divides the threshold by the zoom before calling.
"""

glob SNAP_THRESHOLD: float = 6.0;

# How far a guide is drawn past the two shapes it connects, so a line between
# two distant shapes still reads as one continuous hint.
glob GUIDE_OVERHANG: float = 16.0;


"""Axis-aligned bounds of any element, or None when it has no geometry.

Deliberately geometric rather than rendered: no canvas context, no text
measurement. A label makes its own shape taller through fit_shape_to_label, so
the stored width and height are already the right thing to align to."""
def:pub element_bounds(el: any) -> any {
    if not el {
        return None;
    }
    kind: str = el.type or "";

    if kind == "line" or kind == "arrow" {
        if el.x1 == None or el.x1 == undefined {
            return None;
        }
        return {
            "left": Math.min(el.x1, el.x2),
            "right": Math.max(el.x1, el.x2),
            "top": Math.min(el.y1, el.y2),
            "bottom": Math.max(el.y1, el.y2)
        };
    }

    if kind == "freehand" {
        pts = el.points;
        if not pts or pts.length == 0 {
            return None;
        }
        fl = pts[0].x; fr = pts[0].x; ft = pts[0].y; fb = pts[0].y;
        pi = 1;
        while pi < pts.length {
            if pts[pi].x < fl { fl = pts[pi].x; }
            if pts[pi].x > fr { fr = pts[pi].x; }
            if pts[pi].y < ft { ft = pts[pi].y; }
            if pts[pi].y > fb { fb = pts[pi].y; }
            pi = pi + 1;
        }
        return {"left": fl, "right": fr, "top": ft, "bottom": fb};
    }

    if el.width == None or el.width == undefined {
        return None;
    }
    w = el.width;
    h = el.height;
    return {
        "left": Math.min(el.x, el.x + w),
        "right": Math.max(el.x, el.x + w),
        "top": Math.min(el.y, el.y + h),
        "bottom": Math.max(el.y, el.y + h)
    };
}


"""Union of several bounds, so a multi-selection snaps as one block."""
def:pub union_bounds(list_of_bounds: list) -> any {
    out = None;
    ui = 0;
    while ui < len(list_of_bounds) {
        b = list_of_bounds[ui];
        if b {
            if not out {
                out = {"left": b["left"], "right": b["right"], "top": b["top"], "bottom": b["bottom"]};
            } else {
                if b["left"] < out["left"] { out["left"] = b["left"]; }
                if b["right"] > out["right"] { out["right"] = b["right"]; }
                if b["top"] < out["top"] { out["top"] = b["top"]; }
                if b["bottom"] > out["bottom"] { out["bottom"] = b["bottom"]; }
            }
        }
        ui = ui + 1;
    }
    return out;
}


"""The three interesting positions on one axis: both edges and the centre."""
def _x_anchors(b: any) -> list {
    return [b["left"], (b["left"] + b["right"]) / 2, b["right"]];
}

def _y_anchors(b: any) -> list {
    return [b["top"], (b["top"] + b["bottom"]) / 2, b["bottom"]];
}


"""Best snap for a dragged block against its neighbours.

`moving` is the block's bounds where the pointer would put it; `others` is a
list of bounds to align against. Returns the correction to ADD to the drag,
plus the guides that justify it:

    {"dx": float, "dy": float, "guides": [{"axis", "at", "from", "to"}]}

Each axis is decided independently, so a shape can land on a neighbour's left
edge and a different neighbour's centre line at the same time -- which is what
makes a row of boxes tidy itself up as you build it."""
def:pub compute_snap(moving: any, others: list, threshold: float) -> any {
    result = {"dx": 0.0, "dy": 0.0, "guides": []};
    if not moving or len(others) == 0 {
        return result;
    }

    mx = _x_anchors(moving);
    my = _y_anchors(moving);

    best_dx = None; best_x_at = 0.0; best_x_other = None;
    best_dy = None; best_y_at = 0.0; best_y_other = None;

    oi = 0;
    while oi < len(others) {
        other = others[oi];
        if other {
            ox = _x_anchors(other);
            oy = _y_anchors(other);

            ai = 0;
            while ai < 3 {
                bi = 0;
                while bi < 3 {
                    dx = ox[bi] - mx[ai];
                    if Math.abs(dx) <= threshold {
                        if best_dx == None or Math.abs(dx) < Math.abs(best_dx) {
                            best_dx = dx;
                            best_x_at = ox[bi];
                            best_x_other = other;
                        }
                    }
                    dy = oy[bi] - my[ai];
                    if Math.abs(dy) <= threshold {
                        if best_dy == None or Math.abs(dy) < Math.abs(best_dy) {
                            best_dy = dy;
                            best_y_at = oy[bi];
                            best_y_other = other;
                        }
                    }
                    bi = bi + 1;
                }
                ai = ai + 1;
            }
        }
        oi = oi + 1;
    }

    guides = [];
    if best_dx != None {
        result["dx"] = best_dx;
        # The guide spans both shapes, so it reads as "these two agree".
        span_top = Math.min(moving["top"] + result["dy"], best_x_other["top"]) - GUIDE_OVERHANG;
        span_bottom = Math.max(moving["bottom"] + result["dy"], best_x_other["bottom"]) + GUIDE_OVERHANG;
        guides.append({"axis": "x", "at": best_x_at, "from": span_top, "to": span_bottom});
    }
    if best_dy != None {
        result["dy"] = best_dy;
        span_left = Math.min(moving["left"] + result["dx"], best_y_other["left"]) - GUIDE_OVERHANG;
        span_right = Math.max(moving["right"] + result["dx"], best_y_other["right"]) + GUIDE_OVERHANG;
        guides.append({"axis": "y", "at": best_y_at, "from": span_left, "to": span_right});
    }
    result["guides"] = guides;
    return result;
}


"""The snap radius in WORLD units for a given zoom.

A function rather than the bare glob: a module-level `glob` is not exported to
the client bundle, so importing SNAP_THRESHOLD directly fails at bundle time."""
def:pub snap_threshold_for(zoom: float) -> float {
    z = zoom or 1.0;
    if z <= 0 {
        z = 1.0;
    }
    return SNAP_THRESHOLD / z;
}


"""Draw the guides. Thin, dashed and in the accent colour: a hint, not an object."""
def:pub draw_snap_guides(ctx: any, guides: list, zoom: float) -> None {
    if not guides or len(guides) == 0 {
        return;
    }
    ctx.save();
    ctx.strokeStyle = "#e8590c";
    # Constant on screen whatever the zoom, because it is UI rather than content.
    ctx.lineWidth = 1 / zoom;
    ctx.setLineDash([6 / zoom, 4 / zoom]);
    gi = 0;
    while gi < len(guides) {
        g = guides[gi];
        ctx.beginPath();
        if g["axis"] == "x" {
            ctx.moveTo(g["at"], g["from"]);
            ctx.lineTo(g["at"], g["to"]);
        } else {
            ctx.moveTo(g["from"], g["at"]);
            ctx.lineTo(g["to"], g["at"]);
        }
        ctx.stroke();
        gi = gi + 1;
    }
    ctx.setLineDash([]);
    ctx.restore();
}
