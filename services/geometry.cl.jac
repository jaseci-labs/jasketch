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
    textWidth = fontSize * text.length * 0.6;
    textHeight = fontSize * 1.2;
    return {
        "width": textWidth,
        "height": textHeight
    };
}

def:pub getConnectionPoints(element: dict) -> list {
    if element.type == "rectangle" {
        cx = element.x + element.width / 2;
        cy = element.y + element.height / 2;
        return [
            {"x": cx, "y": element.y, "side": "top"},
            {"x": element.x + element.width, "y": cy, "side": "right"},
            {"x": cx, "y": element.y + element.height, "side": "bottom"},
            {"x": element.x, "y": cy, "side": "left"}
        ];
    } elif element.type == "circle" {
        cx = element.x + element.width / 2;
        cy = element.y + element.height / 2;
        radius = calculateCircleRadius(element.width, element.height);
        return [
            {"x": cx, "y": cy - radius, "side": "top"},
            {"x": cx + radius, "y": cy, "side": "right"},
            {"x": cx, "y": cy + radius, "side": "bottom"},
            {"x": cx - radius, "y": cy, "side": "left"}
        ];
    } elif element.type == "text" {
        dims = getTextDimensions(element.text, element.fontSize);
        cx = element.x + dims.width / 2;
        cy = element.y + dims.height / 2;
        return [
            {"x": cx, "y": element.y, "side": "top"},
            {"x": element.x + dims.width, "y": cy, "side": "right"},
            {"x": cx, "y": element.y + dims.height, "side": "bottom"},
            {"x": element.x, "y": cy, "side": "left"}
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

