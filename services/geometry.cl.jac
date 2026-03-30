def:pub getMousePosition(e: dict, canvas: any, panOffset: dict, zoom: float) -> dict {
    rect = canvas.getBoundingClientRect();
    screenX = e.clientX - rect.left;
    screenY = e.clientY - rect.top;
    return {
        "x": (screenX - panOffset.x) / zoom,
        "y": (screenY - panOffset.y) / zoom
    };
}

def:pub calculateDistance(point1: dict, point2: dict) -> float {
    return Math.sqrt(
        Math.pow(point2.x - point1.x, 2) +
        Math.pow(point2.y - point1.y, 2)
    );
}

def:pub getTextDimensions(text: str, fontSize: float) -> dict {
    lines = text.split(String.fromCharCode(10));
    maxLen = 0;
    i = 0;
    while i < lines.length {
        if lines[i].length > maxLen {
            maxLen = lines[i].length;
        }
        i = i + 1;
    }
    textWidth = fontSize * maxLen * 0.6;
    textHeight = lines.length * fontSize * 1.2;
    return {
        "width": textWidth,
        "height": textHeight
    };
}

def:pub getConnectionPoints(element: dict) -> list {
    if element.type == "rectangle" {
        rCx = element.x + element.width / 2;
        rCy = element.y + element.height / 2;
        rX2 = element.x + element.width;
        rY2 = element.y + element.height;
        return [
            {"x": rCx, "y": element.y, "side": "top"},
            {"x": rX2, "y": element.y, "side": "top-right"},
            {"x": rX2, "y": rCy, "side": "right"},
            {"x": rX2, "y": rY2, "side": "bottom-right"},
            {"x": rCx, "y": rY2, "side": "bottom"},
            {"x": element.x, "y": rY2, "side": "bottom-left"},
            {"x": element.x, "y": rCy, "side": "left"},
            {"x": element.x, "y": element.y, "side": "top-left"}
        ];
    } elif element.type == "circle" {
        eCx = element.x + element.width / 2;
        eCy = element.y + element.height / 2;
        eRx = Math.abs(element.width) / 2;
        eRy = Math.abs(element.height) / 2;
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
    } elif element.type == "diamond" {
        dCx = element.x + element.width / 2;
        dCy = element.y + element.height / 2;
        dX2 = element.x + element.width;
        dY2 = element.y + element.height;
        return [
            {"x": dCx, "y": element.y, "side": "top"},
            {"x": (dCx + dX2) / 2, "y": (element.y + dCy) / 2, "side": "top-right"},
            {"x": dX2, "y": dCy, "side": "right"},
            {"x": (dCx + dX2) / 2, "y": (dCy + dY2) / 2, "side": "bottom-right"},
            {"x": dCx, "y": dY2, "side": "bottom"},
            {"x": (element.x + dCx) / 2, "y": (dCy + dY2) / 2, "side": "bottom-left"},
            {"x": element.x, "y": dCy, "side": "left"},
            {"x": (element.x + dCx) / 2, "y": (element.y + dCy) / 2, "side": "top-left"}
        ];
    } elif element.type == "text" {
        dims = getTextDimensions(element.text, element.fontSize);
        tCx = element.x + dims.width / 2;
        tCy = element.y + dims.height / 2;
        tX2 = element.x + dims.width;
        tY2 = element.y + dims.height;
        return [
            {"x": tCx, "y": element.y, "side": "top"},
            {"x": tX2, "y": element.y, "side": "top-right"},
            {"x": tX2, "y": tCy, "side": "right"},
            {"x": tX2, "y": tY2, "side": "bottom-right"},
            {"x": tCx, "y": tY2, "side": "bottom"},
            {"x": element.x, "y": tY2, "side": "bottom-left"},
            {"x": element.x, "y": tCy, "side": "left"},
            {"x": element.x, "y": element.y, "side": "top-left"}
        ];
    }
    return [];
}

def:pub findConnectedLineUpdates(shapeElement: dict, dx: float, dy: float, elements: list, skipId: str) -> list {
    # Find all line/arrow elements whose endpoints match this shape's connection points
    # and return updates with those endpoints shifted by dx, dy
    result = [];
    cpts = getConnectionPoints(shapeElement);
    if cpts.length == 0 {
        return result;
    }
    idx = 0;
    while idx < elements.length {
        el = elements[idx];
        if el.id != skipId {
            if el.type == "line" or el.type == "arrow" {
                moveStart = False;
                moveEnd = False;
                pi = 0;
                while pi < cpts.length {
                    cp = cpts[pi];
                    sdx = el.x1 - cp.x;
                    sdy = el.y1 - cp.y;
                    sDist = Math.sqrt(sdx * sdx + sdy * sdy);
                    if sDist < 5 {
                        moveStart = True;
                    }
                    edx = el.x2 - cp.x;
                    edy = el.y2 - cp.y;
                    eDist = Math.sqrt(edx * edx + edy * edy);
                    if eDist < 5 {
                        moveEnd = True;
                    }
                    pi = pi + 1;
                }
                if moveStart or moveEnd {
                    updatedEl = Object.assign({}, el);
                    if moveStart {
                        updatedEl.x1 = el.x1 + dx;
                        updatedEl.y1 = el.y1 + dy;
                    }
                    if moveEnd {
                        updatedEl.x2 = el.x2 + dx;
                        updatedEl.y2 = el.y2 + dy;
                    }
                    result.push({"id": el.id, "element": updatedEl});
                }
            }
        }
        idx = idx + 1;
    }
    return result;
}

def:pub findNearestConnectionPoint(mousePos: dict, elements: list, threshold: float) -> dict {
    nearest = None;
    nearestDist = threshold;

    i = 0;
    while i < elements.length {
        element = elements[i];
        connPoints = getConnectionPoints(element);
        j = 0;
        while j < connPoints.length {
            dist = calculateDistance(mousePos, connPoints[j]);
            if dist < nearestDist {
                nearestDist = dist;
                nearest = {
                    "point": connPoints[j],
                    "elementIndex": i,
                    "side": connPoints[j].side
                };
            }
            j = j + 1;
        }
        i = i + 1;
    }
    return nearest;
}

