import from .geometry { calculateDistance, getTextDimensions, get_elbow_full_points, get_freehand_center }

def:pub isPointInRectangle(point: dict, rect: dict) -> bool {
    return (
        point["x"] >= rect["x"] and
        point["x"] <= rect["x"] + rect["width"] and
        point["y"] >= rect["y"] and
        point["y"] <= rect["y"] + rect["height"]
    );
}

def:pub isPointInCircle(point: dict, circle: dict) -> bool {
    centerX = circle["x"] + circle["width"] / 2;
    centerY = circle["y"] + circle["height"] / 2;
    rx = Math.abs(circle["width"]) / 2;
    ry = Math.abs(circle["height"]) / 2;
    if rx == 0 or ry == 0 {
        return False;
    }
    dx = point["x"] - centerX;
    dy = point["y"] - centerY;
    return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1;
}

def:pub isPointInDiamond(point: dict, diamond: dict) -> bool {
    cx = diamond["x"] + diamond["width"] / 2;
    cy = diamond["y"] + diamond["height"] / 2;
    halfW = Math.abs(diamond["width"]) / 2;
    halfH = Math.abs(diamond["height"]) / 2;
    if halfW == 0 or halfH == 0 {
        return False;
    }
    dx = Math.abs(point["x"] - cx) / halfW;
    dy = Math.abs(point["y"] - cy) / halfH;
    return (dx + dy) <= 1.0;
}

def:pub isPointNearLine(point: dict, line: dict, tolerance: float) -> bool {
    if line["bendX"] != None and line["bendX"] != undefined {
        t = 0;
        while t <= 1.0 {
            bx = (1 - t) * (1 - t) * line["x1"] + 2 * (1 - t) * t * line["bendX"] + t * t * line["x2"];
            by = (1 - t) * (1 - t) * line["y1"] + 2 * (1 - t) * t * line["bendY"] + t * t * line["y2"];
            dist = Math.sqrt((point["x"] - bx) * (point["x"] - bx) + (point["y"] - by) * (point["y"] - by));
            if dist <= tolerance {
                return True;
            }
            t = t + 0.05;
        }
        return False;
    }

    dist1 = calculateDistance(point, {"x": line["x1"], "y": line["y1"]});
    dist2 = calculateDistance(point, {"x": line["x2"], "y": line["y2"]});

    if dist1 <= tolerance or dist2 <= tolerance {
        return True;
    }

    lineLength = calculateDistance({"x": line["x1"], "y": line["y1"]}, {"x": line["x2"], "y": line["y2"]});

    if Math.abs(dist1 + dist2 - lineLength) <= tolerance * 2 {
        return True;
    }

    return False;
}

def:pub getLineEndpointAtPoint(point: dict, element: dict) -> str {
    if element["type"] != "line" and element["type"] != "arrow" {
        return None;
    }
    handleRadius = 8;
    distStart = Math.sqrt((point["x"] - element["x1"]) * (point["x"] - element["x1"]) + (point["y"] - element["y1"]) * (point["y"] - element["y1"]));
    if distStart <= handleRadius {
        return "start";
    }
    distEnd = Math.sqrt((point["x"] - element["x2"]) * (point["x"] - element["x2"]) + (point["y"] - element["y2"]) * (point["y"] - element["y2"]));
    if distEnd <= handleRadius {
        return "end";
    }
    return None;
}

def:pub getBendHandleAtPoint(point: dict, element: dict) -> bool {
    # Only for sharp/curved arrows (elbow arrows use get_elbow_segment_at_point instead)
    if element["type"] != "line" and element["type"] != "arrow" {
        return False;
    }
    if element["curveStyle"] == "straight" or element["curveStyle"] == "elbow" {
        return False;
    }
    # Handle at explicit bend point, or midpoint by default
    handleX = (element["x1"] + element["x2"]) / 2;
    handleY = (element["y1"] + element["y2"]) / 2;
    if element["bendX"] != None and element["bendX"] != undefined {
        handleX = element["bendX"];
        handleY = element["bendY"];
    }
    dist = Math.sqrt((point["x"] - handleX) * (point["x"] - handleX) + (point["y"] - handleY) * (point["y"] - handleY));
    return dist <= 8;
}

def:pub isPointInText(point: dict, textElement: dict) -> bool {
    dimensions = getTextDimensions(textElement["text"], textElement["fontSize"]);
    return (
        point["x"] >= textElement["x"] and
        point["x"] <= textElement["x"] + dimensions["width"] and
        point["y"] >= textElement["y"] and
        point["y"] <= textElement["y"] + dimensions["height"]
    );
}

def:pub isPointInFreehandPath(point: dict, path: list, tolerance: float) -> bool {
    if path.length == 0 {
        return False;
    }

    minX = path[0].x;
    minY = path[0].y;
    maxX = path[0].x;
    maxY = path[0].y;

    i = 1;
    while i < path.length {
        if path[i].x < minX {
            minX = path[i].x;
        }
        if path[i].x > maxX {
            maxX = path[i].x;
        }
        if path[i].y < minY {
            minY = path[i].y;
        }
        if path[i].y > maxY {
            maxY = path[i].y;
        }
        i = i + 1;
    }

    if point["x"] < minX - tolerance or point["x"] > maxX + tolerance or point["y"] < minY - tolerance or point["y"] > maxY + tolerance {
        return False;
    }

    i = 0;
    while i < path.length {
        pathPoint = path[i];
        distance = calculateDistance(point, pathPoint);
        if distance <= tolerance {
            return True;
        }
        i = i + 1;
    }
    return False;
}

def:pub getResizeHandleAtPoint(point: dict, bounds: dict) -> str {
    handleRadius = 8;
    handleIds = ["nw", "n", "ne", "e", "se", "s", "sw", "w"];
    handlePositions = [
        {"x": bounds["x"], "y": bounds["y"]},
        {"x": bounds["x"] + bounds["width"] / 2, "y": bounds["y"]},
        {"x": bounds["x"] + bounds["width"], "y": bounds["y"]},
        {"x": bounds["x"] + bounds["width"], "y": bounds["y"] + bounds["height"] / 2},
        {"x": bounds["x"] + bounds["width"], "y": bounds["y"] + bounds["height"]},
        {"x": bounds["x"] + bounds["width"] / 2, "y": bounds["y"] + bounds["height"]},
        {"x": bounds["x"], "y": bounds["y"] + bounds["height"]},
        {"x": bounds["x"], "y": bounds["y"] + bounds["height"] / 2}
    ];

    i = 0;
    while i < handlePositions.length {
        dist = calculateDistance(point, handlePositions[i]);
        if dist <= handleRadius {
            return handleIds[i];
        }
        i = i + 1;
    }
    return None;
}

def:pub get_rotation_handle_at_point(point: dict, bounds: dict, element: dict) -> bool {
    # Check if element supports rotation
    supportedTypes = ["rectangle", "circle", "diamond", "image", "text", "freehand"];
    isSupported = False;
    i = 0;
    while i < supportedTypes.length {
        if element["type"] == supportedTypes[i] {
            isSupported = True;
        }
        i = i + 1;
    }
    if not isSupported {
        return False;
    }

    # If element is rotated, transform the test point by inverse rotation
    testPoint = point;
    if element["rotation"] and (element["rotation"] != 0) {
        cx = bounds["x"] + bounds["width"] / 2;
        cy = bounds["y"] + bounds["height"] / 2;
        rad = -element["rotation"] * 0.0174533;  # PI / 180
        cos_r = Math.cos(rad);
        sin_r = Math.sin(rad);
        dx = point["x"] - cx;
        dy = point["y"] - cy;
        testPoint = {
            "x": cx + dx * cos_r - dy * sin_r,
            "y": cy + dx * sin_r + dy * cos_r
        };
    }

    # Rotation handle is at the top-center of bounds, 28px above (in element's local space)
    rotHandleX = bounds["x"] + bounds["width"] / 2;
    rotHandleY = bounds["y"] - 28;

    # Handle radius for click detection
    dist = calculateDistance(testPoint, {"x": rotHandleX, "y": rotHandleY});
    return dist <= 10;
}

def:pub isPointInElement(point: dict, element: dict) -> bool {
    # Handle rotation by transforming the test point to element's local space
    testPoint = point;
    if element["rotation"] and (element["rotation"] != 0) {
        rotation = element["rotation"];
        cx = element["x"] + (element["width"] or 0) / 2;
        cy = element["y"] + (element["height"] or 0) / 2;
        if element["type"] == "freehand" {
            fc = get_freehand_center(element);
            cx = fc["x"];
            cy = fc["y"];
        }
        # Apply inverse rotation: rotate point by -rotation around element center
        rad = -rotation * 0.0174533;  # PI / 180
        cos_r = Math.cos(rad);
        sin_r = Math.sin(rad);
        dx = point["x"] - cx;
        dy = point["y"] - cy;
        testPoint = {
            "x": cx + dx * cos_r - dy * sin_r,
            "y": cy + dx * sin_r + dy * cos_r
        };
    }

    if element["type"] == "text" {
        return isPointInText(testPoint, element);
    } elif element["type"] == "rectangle" or element["type"] == "image" {
        return isPointInRectangle(testPoint, element);
    } elif element["type"] == "circle" {
        return isPointInCircle(testPoint, element);
    } elif element["type"] == "diamond" {
        return isPointInDiamond(testPoint, element);
    } elif element["type"] == "line" or element["type"] == "arrow" {
        return isPointNearLine(testPoint, element, 20.0);
    } elif element["type"] == "freehand" {
        return isPointInFreehandPath(testPoint, element["points"], 15.0);
    }
    return False;
}

def:pub get_elbow_segment_at_point(point: dict, element: dict) -> int {
    # Returns segment index (1-based) if point is near a segment midpoint handle, else -1.
    if element["type"] != "line" and element["type"] != "arrow" {
        return -1;
    }
    if (element["curveStyle"] or "curved") != "elbow" {
        return -1;
    }
    fullPts = get_elbow_full_points(element);
    handleRadius = 8;
    si = 1;
    while si < fullPts.length {
        midX = (fullPts[si - 1].x + fullPts[si].x) / 2;
        midY = (fullPts[si - 1].y + fullPts[si].y) / 2;
        dist = Math.sqrt((point["x"] - midX) * (point["x"] - midX) + (point["y"] - midY) * (point["y"] - midY));
        if dist <= handleRadius {
            return si;
        }
        si = si + 1;
    }
    return -1;
}
