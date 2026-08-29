def:pub getMousePosition(e: MouseEvent, canvas: any, panOffset: dict, zoom: float) -> dict {
    rect = canvas.getBoundingClientRect();
    screenX = e.clientX - rect.left;
    screenY = e.clientY - rect.top;
    return {
        "x": (screenX - panOffset["x"]) / zoom,
        "y": (screenY - panOffset["y"]) / zoom
    };
}

def:pub calculateDistance(point1: dict, point2: dict) -> float {
    return Math.sqrt(
        Math.pow(point2["x"] - point1["x"], 2) +
        Math.pow(point2["y"] - point1["y"], 2)
    );
}

def:pub getTextDimensions(text: str, fontSize: float) -> dict {
    lines = text.split(String.fromCharCode(10));
    maxLen = 0;
    i = 0;
    while i < len(lines) {
        if len(lines[i]) > maxLen {
            maxLen = len(lines[i]);
        }
        i = i + 1;
    }
    textWidth = fontSize * maxLen * 0.6;
    textHeight = len(lines) * fontSize * 1.2;
    return {
        "width": textWidth,
        "height": textHeight
    };
}

def:pub _rotate_points(points: list, cx: float, cy: float, angle_deg: float) -> list {
    rad = angle_deg * 0.0174533;
    cos_r = Math.cos(rad);
    sin_r = Math.sin(rad);
    result = [];
    i = 0;
    while i < len(points) {
        p = points[i];
        dx = p.x - cx;
        dy = p.y - cy;
        result.append({
            "x": cx + dx * cos_r - dy * sin_r,
            "y": cy + dx * sin_r + dy * cos_r,
            "side": p.side
        });
        i = i + 1;
    }
    return result;
}

def:pub getConnectionPoints(element: dict) -> list {
    if element["type"] == "rectangle" {
        rCx = element["x"] + element["width"] / 2;
        rCy = element["y"] + element["height"] / 2;
        rX2 = element["x"] + element["width"];
        rY2 = element["y"] + element["height"];
        return [
            {"x": rCx, "y": element["y"], "side": "top"},
            {"x": rX2, "y": element["y"], "side": "top-right"},
            {"x": rX2, "y": rCy, "side": "right"},
            {"x": rX2, "y": rY2, "side": "bottom-right"},
            {"x": rCx, "y": rY2, "side": "bottom"},
            {"x": element["x"], "y": rY2, "side": "bottom-left"},
            {"x": element["x"], "y": rCy, "side": "left"},
            {"x": element["x"], "y": element["y"], "side": "top-left"}
        ];
    } elif element["type"] == "circle" {
        eCx = element["x"] + element["width"] / 2;
        eCy = element["y"] + element["height"] / 2;
        eRx = Math.abs(element["width"]) / 2;
        eRy = Math.abs(element["height"]) / 2;
        eDiag = 0.7071;
        return [
            {"x": eCx, "y": eCy - eRy, "side": "top"},
            {"x": eCx + eRx * eDiag, "y": eCy - eRy * eDiag, "side": "top-right"},
            {"x": eCx + eRx, "y": eCy, "side": "right"},
            {"x": eCx + eRx * eDiag, "y": eCy + eRy * eDiag, "side": "bottom-right"},
            {"x": eCx, "y": eCy + eRy, "side": "bottom"},
            {"x": eCx - eRx * eDiag, "y": eCy + eRy * eDiag, "side": "bottom-left"},
            {"x": eCx - eRx, "y": eCy, "side": "left"},
            {"x": eCx - eRx * eDiag, "y": eCy - eRy * eDiag, "side": "top-left"}
        ];
    } elif element["type"] == "diamond" {
        dCx = element["x"] + element["width"] / 2;
        dCy = element["y"] + element["height"] / 2;
        dX2 = element["x"] + element["width"];
        dY2 = element["y"] + element["height"];
        return [
            {"x": dCx, "y": element["y"], "side": "top"},
            {"x": (dCx + dX2) / 2, "y": (element["y"] + dCy) / 2, "side": "top-right"},
            {"x": dX2, "y": dCy, "side": "right"},
            {"x": (dCx + dX2) / 2, "y": (dCy + dY2) / 2, "side": "bottom-right"},
            {"x": dCx, "y": dY2, "side": "bottom"},
            {"x": (element["x"] + dCx) / 2, "y": (dCy + dY2) / 2, "side": "bottom-left"},
            {"x": element["x"], "y": dCy, "side": "left"},
            {"x": (element["x"] + dCx) / 2, "y": (element["y"] + dCy) / 2, "side": "top-left"}
        ];
    } elif element["type"] == "text" {
        dims = getTextDimensions(element["text"], element["fontSize"]);
        tCx = element["x"] + dims["width"] / 2;
        tCy = element["y"] + dims["height"] / 2;
        tX2 = element["x"] + dims["width"];
        tY2 = element["y"] + dims["height"];
        return [
            {"x": tCx, "y": element["y"], "side": "top"},
            {"x": tX2, "y": element["y"], "side": "top-right"},
            {"x": tX2, "y": tCy, "side": "right"},
            {"x": tX2, "y": tY2, "side": "bottom-right"},
            {"x": tCx, "y": tY2, "side": "bottom"},
            {"x": element["x"], "y": tY2, "side": "bottom-left"},
            {"x": element["x"], "y": tCy, "side": "left"},
            {"x": element["x"], "y": element["y"], "side": "top-left"}
        ];
    }
    return [];
}

def:pub get_elbow_full_points(element: dict) -> list {
    # Returns all waypoints [{x,y}] for an elbow arrow, including start and end.
    # If element.elbowBends is set, uses those intermediate points.
    # Otherwise routes based on binding sides (L-shape or Z-shape).
    if element["elbowBends"] and element["elbowBends"].length > 0 {
        pts = [{"x": element["x1"], "y": element["y1"]}];
        bi = 0;
        while bi < element["elbowBends"].length {
            pts.append({"x": element["elbowBends"][bi].x, "y": element["elbowBends"][bi].y});
            bi = bi + 1;
        }
        pts.append({"x": element["x2"], "y": element["y2"]});
        return pts;
    }

    # Determine routing based on binding sides
    # Vertical sides exit/enter perpendicular to top/bottom edges
    # Horizontal sides exit/enter perpendicular to left/right edges
    startSide = (element["startBinding"] and element["startBinding"].side) or "";
    endSide = (element["endBinding"] and element["endBinding"].side) or "";

    startIsVert = (startSide == "top" or startSide == "bottom" or
                   startSide == "top-left" or startSide == "top-right" or
                   startSide == "bottom-left" or startSide == "bottom-right");
    startIsHoriz = (startSide == "left" or startSide == "right");
    endIsVert = (endSide == "top" or endSide == "bottom" or
                 endSide == "top-left" or endSide == "top-right" or
                 endSide == "bottom-left" or endSide == "bottom-right");
    endIsHoriz = (endSide == "left" or endSide == "right");

    # L-shape: start exits vertically (top/bottom), end enters horizontally (left/right)
    # Route: (x1, y1) -> (x1, y2) -> (x2, y2)
    if startIsVert and endIsHoriz {
        return [
            {"x": element["x1"], "y": element["y1"]},
            {"x": element["x1"], "y": element["y2"]},
            {"x": element["x2"], "y": element["y2"]}
        ];
    }

    # L-shape: start exits horizontally (left/right), end enters vertically (top/bottom)
    # Route: (x1, y1) -> (x2, y1) -> (x2, y2)
    if startIsHoriz and endIsVert {
        return [
            {"x": element["x1"], "y": element["y1"]},
            {"x": element["x2"], "y": element["y1"]},
            {"x": element["x2"], "y": element["y2"]}
        ];
    }

    # Legacy bendX support, or default Z-shape (same-axis connections or no binding)
    midX = (element["x1"] + element["x2"]) / 2;
    if element["bendX"] != None and element["bendX"] != undefined {
        midX = element["bendX"];
    }
    return [
        {"x": element["x1"], "y": element["y1"]},
        {"x": midX, "y": element["y1"]},
        {"x": midX, "y": element["y2"]},
        {"x": element["x2"], "y": element["y2"]}
    ];
}

def:pub move_elbow_segment(fullPoints: list, segIdx: int, pos: dict) -> list {
    # Moves segment segIdx (from fullPoints[segIdx-1] to fullPoints[segIdx]) to pos.
    # Inner segments: both vertices move in the perpendicular axis.
    # First/last segments: a stub is inserted to maintain the fixed endpoint.
    # Returns new full-points list.
    n = len(fullPoints);
    if segIdx < 1 or segIdx >= n {
        return fullPoints;
    }

    p0 = fullPoints[segIdx - 1];
    p1 = fullPoints[segIdx];
    isHoriz = Math.abs(p1.x - p0.x) >= Math.abs(p1.y - p0.y);

    # Build mutable copy
    pts = [];
    ci = 0;
    while ci < n {
        pts.append({"x": fullPoints[ci].x, "y": fullPoints[ci].y});
        ci = ci + 1;
    }

    if isHoriz {
        newY = pos["y"];
        # First segment: endpoint[0] is fixed — insert a vertical stub before pts[1]
        if segIdx == 1 {
            pts[1].y = newY;
            newResult = [{"x": pts[0].x, "y": pts[0].y}, {"x": pts[0].x, "y": newY}];
            rj = 1;
            while rj < len(pts) {
                newResult.append({"x": pts[rj].x, "y": pts[rj].y});
                rj = rj + 1;
            }
            return newResult;
        }
        # Last segment: endpoint[n-1] is fixed — insert a vertical stub before pts[n-1]
        if segIdx == n - 1 {
            pts[n - 2].y = newY;
            newResult = [];
            rj = 0;
            while rj < len(pts) - 1 {
                newResult.append({"x": pts[rj].x, "y": pts[rj].y});
                rj = rj + 1;
            }
            newResult.append({"x": pts[n - 1].x, "y": newY});
            newResult.append({"x": pts[n - 1].x, "y": pts[n - 1].y});
            return newResult;
        }
        # Inner segment: move both vertices
        pts[segIdx - 1].y = newY;
        pts[segIdx].y = newY;
    } else {
        newX = pos["x"];
        # First segment: insert a horizontal stub before pts[1]
        if segIdx == 1 {
            pts[1].x = newX;
            newResult = [{"x": pts[0].x, "y": pts[0].y}, {"x": newX, "y": pts[0].y}];
            rj = 1;
            while rj < len(pts) {
                newResult.append({"x": pts[rj].x, "y": pts[rj].y});
                rj = rj + 1;
            }
            return newResult;
        }
        # Last segment: insert a horizontal stub before pts[n-1]
        if segIdx == n - 1 {
            pts[n - 2].x = newX;
            newResult = [];
            rj = 0;
            while rj < len(pts) - 1 {
                newResult.append({"x": pts[rj].x, "y": pts[rj].y});
                rj = rj + 1;
            }
            newResult.append({"x": newX, "y": pts[n - 1].y});
            newResult.append({"x": pts[n - 1].x, "y": pts[n - 1].y});
            return newResult;
        }
        # Inner segment
        pts[segIdx - 1].x = newX;
        pts[segIdx].x = newX;
    }

    return pts;
}

def:pub find_bound_line_updates_for_shape(updated_shape: dict, elements: list) -> list {
    result = [];
    cpts = getConnectionPoints(updated_shape);
    if len(cpts) == 0 {
        return result;
    }

    # Apply rotation to connection points if element is rotated
    if updated_shape["rotation"] and (updated_shape["rotation"] != 0) {
        rot_cx = updated_shape["x"] + updated_shape["width"] / 2;
        rot_cy = updated_shape["y"] + updated_shape["height"] / 2;
        if updated_shape["type"] == "text" {
            rot_dims = getTextDimensions(updated_shape["text"], updated_shape["fontSize"]);
            rot_cx = updated_shape["x"] + rot_dims["width"] / 2;
            rot_cy = updated_shape["y"] + rot_dims["height"] / 2;
        }
        cpts = _rotate_points(cpts, rot_cx, rot_cy, updated_shape["rotation"]);
    }

    i = 0;
    while i < len(elements) {
        el = elements[i];
        if el.id != updated_shape["id"] {
            if el.type == "line" or el.type == "arrow" {
                updated = False;
                updatedEl = {**el};
                if el.startBinding and el.startBinding.elementId == updated_shape["id"] {
                    j = 0;
                    while j < len(cpts) {
                        if cpts[j].side == el.startBinding.side {
                            updatedEl.x1 = cpts[j].x;
                            updatedEl.y1 = cpts[j].y;
                            updated = True;
                        }
                        j = j + 1;
                    }
                }
                if el.endBinding and el.endBinding.elementId == updated_shape["id"] {
                    j = 0;
                    while j < len(cpts) {
                        if cpts[j].side == el.endBinding.side {
                            updatedEl.x2 = cpts[j].x;
                            updatedEl.y2 = cpts[j].y;
                            updated = True;
                        }
                        j = j + 1;
                    }
                }
                if updated {
                    # Elbow arrows recompute their path when bound shape moves
                    if updatedEl.curveStyle == "elbow" {
                        updatedEl.elbowBends = None;
                    }
                    result.append({"id": el.id, "element": updatedEl});
                }
            }
        }
        i = i + 1;
    }
    return result;
}

def:pub get_freehand_center(element: dict) -> dict {
    if not element["points"] or element["points"].length == 0 {
        return {"x": 0, "y": 0};
    }
    minX = element["points"][0].x;
    minY = element["points"][0].y;
    maxX = element["points"][0].x;
    maxY = element["points"][0].y;
    i = 1;
    while i < element["points"].length {
        p = element["points"][i];
        if p.x < minX { minX = p.x; }
        if p.y < minY { minY = p.y; }
        if p.x > maxX { maxX = p.x; }
        if p.y > maxY { maxY = p.y; }
        i = i + 1;
    }
    return {"x": (minX + maxX) / 2, "y": (minY + maxY) / 2};
}

def:pub findNearestConnectionPoint(mousePos: dict, elements: list, threshold: float) -> dict {
    nearest = None;
    nearestDist = threshold;

    i = 0;
    while i < len(elements) {
        element = elements[i];
        connPoints = getConnectionPoints(element);

        # Apply rotation to connection points if element is rotated
        if element.rotation and (element.rotation != 0) {
            el_cx = element.x + element.width / 2;
            el_cy = element.y + element.height / 2;
            if element.type == "text" {
                el_dims = getTextDimensions(element.text, element.fontSize);
                el_cx = element.x + el_dims["width"] / 2;
                el_cy = element.y + el_dims["height"] / 2;
            }
            connPoints = _rotate_points(connPoints, el_cx, el_cy, element.rotation);
        }

        j = 0;
        while j < len(connPoints) {
            dist = calculateDistance(mousePos, connPoints[j]);
            if dist < nearestDist {
                nearestDist = dist;
                nearest = {
                    "point": connPoints[j],
                    "elementId": element.id,
                    "side": connPoints[j].side
                };
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return nearest;
}


"""Constrain a drag end-point while Shift is held.

Rectangles, diamonds and ellipses become square; lines and arrows snap to the
nearest 45 degrees. Every other whiteboard does this, so the muscle memory
arrives before the user reads any documentation -- holding Shift and getting a
lopsided rectangle reads as the tool being broken."""
def:pub constrain_drag_point(start: dict[str, float], pos: dict[str, float], tool: str) -> dict[str, float] {
    dx: float = pos["x"] - start["x"];
    dy: float = pos["y"] - start["y"];

    if tool == "line" or tool == "arrow" {
        step: float = Math.PI / 4;
        snapped: float = Math.round(Math.atan2(dy, dx) / step) * step;
        dist: float = Math.sqrt(dx * dx + dy * dy);
        return {
            "x": start["x"] + Math.cos(snapped) * dist,
            "y": start["y"] + Math.sin(snapped) * dist
        };
    }

    size: float = Math.max(Math.abs(dx), Math.abs(dy));
    return {
        "x": start["x"] + (size if dx >= 0 else -size),
        "y": start["y"] + (size if dy >= 0 else -size)
    };
}


"""Return a copy of `el` translated by (dx, dy), whatever its geometry is.

Shapes carry x/y, lines and arrows carry two endpoints plus an optional bend,
and freehand carries a point list. Moving one means touching whichever of those
it actually has."""
def:pub shift_element(el: any, dx: float, dy: float) -> any {
    # `any`, not dict: an element is a heterogeneous JSON record, and a dict
    # here types every value Unknown and turns the arithmetic below into errors.
    moved: any = {**el};
    if "x" in moved and moved["x"] != None {
        moved["x"] = moved["x"] + dx;
    }
    if "y" in moved and moved["y"] != None {
        moved["y"] = moved["y"] + dy;
    }
    for (a, b) in [("x1", "y1"), ("x2", "y2"), ("bendX", "bendY")] {
        if a in moved and moved[a] != None {
            moved[a] = moved[a] + dx;
        }
        if b in moved and moved[b] != None {
            moved[b] = moved[b] + dy;
        }
    }
    if "points" in moved and moved["points"] {
        moved["points"] = [{**pt, "x": pt["x"] + dx, "y": pt["y"] + dy} for pt in moved["points"]];
    }
    return moved;
}
