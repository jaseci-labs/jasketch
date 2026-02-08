import from .geometry { calculateCircleRadius, getConnectionPoints }

def:pub drawElement(ctx: any, element: dict) -> None {
    if element.type == "text" {
        drawTextElement(ctx, element);
    } else {
        drawShapeElement(ctx, element);
    }
}

def:pub drawTextElement(ctx: any, element: dict) -> None {
    ctx.font = element.fontSize + "px " + element.fontFamily;
    ctx.fillStyle = element.color;
    ctx.textBaseline = "top";

    # Subtle text shadow
    ctx.shadowColor = "rgba(0, 0, 0, 0.06)";
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 1;

    lines = element.text.split("\n");
    lines.forEach(lambda line: any, index: any -> None {
        ctx.fillText(line, element.x, element.y + (index * element.fontSize * 1.2));
    });

    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
}

def:pub drawShapeElement(ctx: any, element: dict) -> None {
    ctx.strokeStyle = element.color;
    ctx.lineWidth = element.strokeWidth;
    ctx.fillStyle = element.fillColor or "transparent";
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    # Subtle shadow for modern look
    ctx.shadowColor = "rgba(0, 0, 0, 0.08)";
    ctx.shadowBlur = 4;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 2;

    if element.type == "freehand" {
        drawFreehand(ctx, element);
    } elif element.type == "rectangle" {
        drawRectangle(ctx, element);
    } elif element.type == "circle" {
        drawCircle(ctx, element);
    } elif element.type == "line" {
        drawLine(ctx, element);
    } elif element.type == "arrow" {
        drawArrow(ctx, element);
    }

    # Reset shadow
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
}

def:pub drawFreehand(ctx: any, element: dict) -> None {
    points = element.points;
    if points.length == 0 {
        return;
    }
    ctx.beginPath();
    if points.length == 1 {
        ctx.arc(points[0].x, points[0].y, ctx.lineWidth / 2, 0, Math.PI * 2);
        ctx.fill();
        return;
    }
    if points.length == 2 {
        ctx.moveTo(points[0].x, points[0].y);
        ctx.lineTo(points[1].x, points[1].y);
        ctx.stroke();
        return;
    }
    ctx.moveTo(points[0].x, points[0].y);
    i = 1;
    while i < points.length - 1 {
        midX = (points[i].x + points[i + 1].x) / 2;
        midY = (points[i].y + points[i + 1].y) / 2;
        ctx.quadraticCurveTo(points[i].x, points[i].y, midX, midY);
        i = i + 1;
    }
    ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
    ctx.stroke();
}

def:pub drawRectangle(ctx: any, element: dict) -> None {
    ctx.beginPath();
    ctx.roundRect(element.x, element.y, element.width, element.height, 8);
    ctx.stroke();
    if element.fillColor and element.fillColor != "transparent" {
        ctx.fill();
    }
}

def:pub drawCircle(ctx: any, element: dict) -> None {
    ctx.beginPath();
    radius = calculateCircleRadius(element.width, element.height);
    ctx.arc(element.x + element.width/2, element.y + element.height/2, radius, 0, 2 * Math.PI);
    ctx.stroke();
    if element.fillColor and element.fillColor != "transparent" {
        ctx.fill();
    }
}

def:pub drawLine(ctx: any, element: dict) -> None {
    ctx.beginPath();
    ctx.moveTo(element.x1, element.y1);
    ctx.lineTo(element.x2, element.y2);
    ctx.stroke();
}

def:pub drawArrow(ctx: any, element: dict) -> None {
    ctx.beginPath();
    ctx.moveTo(element.x1, element.y1);
    ctx.lineTo(element.x2, element.y2);
    ctx.stroke();

    # Draw arrowhead
    headLen = 12;
    angle = Math.atan2(element.y2 - element.y1, element.x2 - element.x1);
    ctx.beginPath();
    ctx.moveTo(element.x2, element.y2);
    ctx.lineTo(element.x2 - headLen * Math.cos(angle - Math.PI / 6), element.y2 - headLen * Math.sin(angle - Math.PI / 6));
    ctx.lineTo(element.x2 - headLen * Math.cos(angle + Math.PI / 6), element.y2 - headLen * Math.sin(angle + Math.PI / 6));
    ctx.closePath();
    ctx.fillStyle = element.color;
    ctx.fill();
}

def:pub drawPreview(ctx: any, tool: str, startPoint: dict, currentPoint: dict, color: str, strokeWidth: float) -> None {
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.globalAlpha = 0.6;

    if tool == "rectangle" {
        w = currentPoint.x - startPoint.x;
        h = currentPoint.y - startPoint.y;
        ctx.beginPath();
        ctx.roundRect(startPoint.x, startPoint.y, w, h, 8);
        ctx.stroke();
    } elif tool == "circle" {
        w = currentPoint.x - startPoint.x;
        h = currentPoint.y - startPoint.y;
        radius = calculateCircleRadius(w, h);
        ctx.beginPath();
        ctx.arc(startPoint.x + w/2, startPoint.y + h/2, radius, 0, 2 * Math.PI);
        ctx.stroke();
    } elif tool == "line" {
        ctx.beginPath();
        ctx.moveTo(startPoint.x, startPoint.y);
        ctx.lineTo(currentPoint.x, currentPoint.y);
        ctx.stroke();
    } elif tool == "arrow" {
        ctx.beginPath();
        ctx.moveTo(startPoint.x, startPoint.y);
        ctx.lineTo(currentPoint.x, currentPoint.y);
        ctx.stroke();
        # Preview arrowhead
        headLen = 12;
        angle = Math.atan2(currentPoint.y - startPoint.y, currentPoint.x - startPoint.x);
        ctx.beginPath();
        ctx.moveTo(currentPoint.x, currentPoint.y);
        ctx.lineTo(currentPoint.x - headLen * Math.cos(angle - Math.PI / 6), currentPoint.y - headLen * Math.sin(angle - Math.PI / 6));
        ctx.lineTo(currentPoint.x - headLen * Math.cos(angle + Math.PI / 6), currentPoint.y - headLen * Math.sin(angle + Math.PI / 6));
        ctx.closePath();
        ctx.fillStyle = color;
        ctx.fill();
    }

    ctx.globalAlpha = 1.0;
}

def:pub clearCanvas(ctx: any, width: float, height: float) -> None {
    ctx.clearRect(0, 0, width, height);
}

def:pub applyViewportTransform(ctx: any, zoom: float, panOffset: dict) -> None {
    ctx.translate(panOffset.x, panOffset.y);
    ctx.scale(zoom, zoom);
}

def:pub drawBoxSelectionRect(ctx: any, boxStart: dict, boxEnd: dict) -> None {
    ctx.save();
    ctx.strokeStyle = "#6366f1";
    ctx.fillStyle = "rgba(99, 102, 241, 0.1)";
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 5]);

    x = Math.min(boxStart.x, boxEnd.x);
    y = Math.min(boxStart.y, boxEnd.y);
    width = Math.abs(boxEnd.x - boxStart.x);
    height = Math.abs(boxEnd.y - boxStart.y);

    ctx.fillRect(x, y, width, height);
    ctx.strokeRect(x, y, width, height);

    ctx.setLineDash([]);
    ctx.restore();
}

def:pub getElementBounds(ctx: any, element: dict) -> dict {
    padding = 5;
    if element.type == "text" {
        ctx.font = element.fontSize + "px " + element.fontFamily;
        metrics = ctx.measureText(element.text);
        lines = element.text.split("\n");
        textHeight = lines.length * element.fontSize * 1.2;
        return {
            "x": element.x - padding,
            "y": element.y - padding,
            "width": metrics.width + padding * 2,
            "height": textHeight + padding * 2
        };
    } elif element.type == "rectangle" or element.type == "circle" {
        return {
            "x": element.x - padding,
            "y": element.y - padding,
            "width": element.width + padding * 2,
            "height": element.height + padding * 2
        };
    } elif element.type == "line" or element.type == "arrow" {
        minX = Math.min(element.x1, element.x2);
        minY = Math.min(element.y1, element.y2);
        maxX = Math.max(element.x1, element.x2);
        maxY = Math.max(element.y1, element.y2);
        return {
            "x": minX - padding,
            "y": minY - padding,
            "width": (maxX - minX) + padding * 2,
            "height": (maxY - minY) + padding * 2
        };
    } elif element.type == "freehand" {
        if element.points.length > 0 {
            minX = element.points[0].x;
            minY = element.points[0].y;
            maxX = element.points[0].x;
            maxY = element.points[0].y;

            element.points.forEach(lambda point: dict -> None {
                if point.x < minX {
                    minX = point.x;
                }
                if point.y < minY {
                    minY = point.y;
                }
                if point.x > maxX {
                    maxX = point.x;
                }
                if point.y > maxY {
                    maxY = point.y;
                }
            });

            return {
                "x": minX - padding,
                "y": minY - padding,
                "width": (maxX - minX) + padding * 2,
                "height": (maxY - minY) + padding * 2
            };
        }
    }
    return {"x": 0, "y": 0, "width": 0, "height": 0};
}

def:pub drawSelectionBox(ctx: any, element: dict) -> None {
    ctx.save();
    bounds = getElementBounds(ctx, element);

    # Solid selection border
    ctx.strokeStyle = "#6366f1";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([]);
    ctx.strokeRect(bounds.x, bounds.y, bounds.width, bounds.height);

    # Draw resize handles at corners and edges
    handleSize = 6;
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#6366f1";
    ctx.lineWidth = 1.5;

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
        hp = handlePositions[i];
        ctx.beginPath();
        ctx.arc(hp.x, hp.y, handleSize / 2, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        i = i + 1;
    }

    ctx.restore();
}

def:pub drawConnectionPoints(ctx: any, element: dict) -> None {
    points = getConnectionPoints(element);
    if points.length == 0 {
        return;
    }
    ctx.save();
    i = 0;
    while i < points.length {
        cp = points[i];
        ctx.beginPath();
        ctx.arc(cp.x, cp.y, 5, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(99, 102, 241, 0.3)";
        ctx.fill();
        ctx.strokeStyle = "#6366f1";
        ctx.lineWidth = 1.5;
        ctx.stroke();
        i = i + 1;
    }
    ctx.restore();
}

def:pub drawSnapIndicator(ctx: any, point: dict) -> None {
    ctx.save();
    ctx.beginPath();
    ctx.arc(point.x, point.y, 7, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(99, 102, 241, 0.5)";
    ctx.fill();
    ctx.strokeStyle = "#6366f1";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
}
