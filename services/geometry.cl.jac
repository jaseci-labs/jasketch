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

def:pub calculateCircleRadius(width: float, height: float) -> float {
    return Math.sqrt(Math.pow(width, 2) + Math.pow(height, 2)) / 2;
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
        return [
            {"x": rCx, "y": element.y, "side": "top"},
            {"x": element.x + element.width, "y": rCy, "side": "right"},
            {"x": rCx, "y": element.y + element.height, "side": "bottom"},
            {"x": element.x, "y": rCy, "side": "left"}
        ];
    } elif element.type == "circle" {
        eCx = element.x + element.width / 2;
        eCy = element.y + element.height / 2;
        eRx = Math.abs(element.width) / 2;
        eRy = Math.abs(element.height) / 2;
        return [
            {"x": eCx, "y": eCy - eRy, "side": "top"},
            {"x": eCx + eRx, "y": eCy, "side": "right"},
            {"x": eCx, "y": eCy + eRy, "side": "bottom"},
            {"x": eCx - eRx, "y": eCy, "side": "left"}
        ];
    } elif element.type == "diamond" {
        dCx = element.x + element.width / 2;
        dCy = element.y + element.height / 2;
        return [
            {"x": dCx, "y": element.y, "side": "top"},
            {"x": element.x + element.width, "y": dCy, "side": "right"},
            {"x": dCx, "y": element.y + element.height, "side": "bottom"},
            {"x": element.x, "y": dCy, "side": "left"}
        ];
    } elif element.type == "text" {
        dims = getTextDimensions(element.text, element.fontSize);
        tCx = element.x + dims.width / 2;
        tCy = element.y + dims.height / 2;
        return [
            {"x": tCx, "y": element.y, "side": "top"},
            {"x": element.x + dims.width, "y": tCy, "side": "right"},
            {"x": tCx, "y": element.y + dims.height, "side": "bottom"},
            {"x": element.x, "y": tCy, "side": "left"}
        ];
    }
    return [];
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

