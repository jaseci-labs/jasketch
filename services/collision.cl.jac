import from .geometry { calculateDistance, calculateCircleRadius, getTextDimensions }

def:pub isPointInRectangle(point: dict, rect: dict) -> bool {
    return (
        point.x >= rect.x and
        point.x <= rect.x + rect.width and
        point.y >= rect.y and
        point.y <= rect.y + rect.height
    );
}

def:pub isPointInCircle(point: dict, circle: dict) -> bool {
    centerX = circle.x + circle.width / 2;
    centerY = circle.y + circle.height / 2;
    radius = calculateCircleRadius(circle.width, circle.height);
    distance = calculateDistance(point, {"x": centerX, "y": centerY});
    return distance <= radius;
}

def:pub isPointNearLine(point: dict, line: dict, tolerance: float) -> bool {
    dist1 = calculateDistance(point, {"x": line.x1, "y": line.y1});
    dist2 = calculateDistance(point, {"x": line.x2, "y": line.y2});

    if dist1 <= tolerance or dist2 <= tolerance {
        return True;
    }

    lineLength = calculateDistance({"x": line.x1, "y": line.y1}, {"x": line.x2, "y": line.y2});

    if Math.abs(dist1 + dist2 - lineLength) <= tolerance * 2 {
        return True;
    }

    return False;
}

def:pub isPointInText(point: dict, textElement: dict) -> bool {
    dimensions = getTextDimensions(textElement.text, textElement.fontSize);
    return (
        point.x >= textElement.x and
        point.x <= textElement.x + dimensions.width and
        point.y >= textElement.y and
        point.y <= textElement.y + dimensions.height
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

    if point.x < minX - tolerance or point.x > maxX + tolerance or point.y < minY - tolerance or point.y > maxY + tolerance {
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
        {"x": bounds.x, "y": bounds.y},
        {"x": bounds.x + bounds.width / 2, "y": bounds.y},
        {"x": bounds.x + bounds.width, "y": bounds.y},
        {"x": bounds.x + bounds.width, "y": bounds.y + bounds.height / 2},
        {"x": bounds.x + bounds.width, "y": bounds.y + bounds.height},
        {"x": bounds.x + bounds.width / 2, "y": bounds.y + bounds.height},
        {"x": bounds.x, "y": bounds.y + bounds.height},
        {"x": bounds.x, "y": bounds.y + bounds.height / 2}
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

def:pub isPointInElement(point: dict, element: dict) -> bool {
    if element.type == "text" {
        return isPointInText(point, element);
    } elif element.type == "rectangle" {
        return isPointInRectangle(point, element);
    } elif element.type == "circle" {
        return isPointInCircle(point, element);
    } elif element.type == "line" or element.type == "arrow" {
        return isPointNearLine(point, element, 20.0);
    } elif element.type == "freehand" {
        return isPointInFreehandPath(point, element.points, 15.0);
    }
    return False;
}
