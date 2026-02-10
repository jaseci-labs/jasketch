import from .geometry { getConnectionPoints }

# Seeded random for consistent hand-drawn jitter per element
def seedRandom(seed: float) -> float {
    x = Math.sin(seed * 9301 + 49297) * 233280;
    return x - Math.floor(x);
}

def jitter(seed: float, amount: float) -> float {
    return (seedRandom(seed) - 0.5) * amount;
}

# Draw a hand-drawn line segment between two points using quadratic curves
def sketchyLine(ctx: any, x1: float, y1: float, x2: float, y2: float, seed: float) -> None {
    dx = x2 - x1;
    dy = y2 - y1;
    length = Math.sqrt(dx * dx + dy * dy);
    wobble = Math.min(length * 0.05, 3);

    # Use 2 control points for a subtle wobble
    mx1 = x1 + dx * 0.33 + jitter(seed + 1, wobble * 2);
    my1 = y1 + dy * 0.33 + jitter(seed + 2, wobble * 2);
    mx2 = x1 + dx * 0.67 + jitter(seed + 3, wobble * 2);
    my2 = y1 + dy * 0.67 + jitter(seed + 4, wobble * 2);

    ctx.moveTo(x1 + jitter(seed + 5, wobble), y1 + jitter(seed + 6, wobble));
    ctx.bezierCurveTo(mx1, my1, mx2, my2, x2 + jitter(seed + 7, wobble), y2 + jitter(seed + 8, wobble));
}

def:pub drawElement(ctx: any, element: dict) -> None {
    if element.type == "text" {
        drawTextElement(ctx, element);
    } elif element.type == "image" {
        drawImageElement(ctx, element);
    } else {
        drawShapeElement(ctx, element);
    }
}

def:pub drawImageElement(ctx: any, element: dict) -> None {
    if not element.imageObj {
        img = Reflect.construct(Image, []);
        img.src = element.src;
        element.imageObj = img;
    }
    if element.imageObj.complete {
        ctx.save();
        ctx.globalAlpha = element.opacity or 1.0;
        ctx.shadowColor = "rgba(0, 0, 0, 0.1)";
        ctx.shadowBlur = 6;
        ctx.shadowOffsetX = 0;
        ctx.shadowOffsetY = 3;
        ctx.drawImage(element.imageObj, element.x, element.y, element.width, element.height);
        ctx.restore();
    }
}

def:pub drawTextElement(ctx: any, element: dict) -> None {
    ctx.save();
    ctx.globalAlpha = element.opacity or 1.0;
    ctx.font = element.fontSize + "px " + element.fontFamily;
    ctx.fillStyle = element.color;
    ctx.textBaseline = "top";
    ctx.shadowColor = "rgba(0, 0, 0, 0.06)";
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 1;

    lines = element.text.split(String.fromCharCode(10));
    lines.forEach(lambda line: any, index: any -> None {
        ctx.fillText(line, element.x, element.y + (index * element.fontSize * 1.2));
    });
    ctx.restore();
}

def:pub drawShapeElement(ctx: any, element: dict) -> None {
    ctx.save();
    ctx.globalAlpha = element.opacity or 1.0;
    ctx.strokeStyle = element.color;
    ctx.lineWidth = element.strokeWidth;
    ctx.fillStyle = element.fillColor or "transparent";
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.shadowColor = "rgba(0, 0, 0, 0.08)";
    ctx.shadowBlur = 4;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 2;

    # Apply line style
    lineStyle = element.lineStyle or "solid";
    if lineStyle == "dashed" {
        ctx.setLineDash([12, 6]);
    } elif lineStyle == "dotted" {
        ctx.setLineDash([3, 6]);
    } else {
        ctx.setLineDash([]);
    }

    if element.type == "freehand" {
        drawFreehand(ctx, element);
    } elif element.type == "rectangle" {
        drawRectangle(ctx, element);
    } elif element.type == "circle" {
        drawCircle(ctx, element);
    } elif element.type == "diamond" {
        drawDiamond(ctx, element);
    } elif element.type == "line" {
        drawLine(ctx, element);
    } elif element.type == "arrow" {
        drawArrow(ctx, element);
    }
    ctx.restore();
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
    seed = element.x * 7 + element.y * 13 + element.width * 3 + element.height * 11;
    x = element.x;
    y = element.y;
    w = element.width;
    h = element.height;

    # Draw 2 passes for a hand-drawn double-line effect
    pass_i = 0;
    while pass_i < 2 {
        s = seed + pass_i * 100;
        ctx.beginPath();
        sketchyLine(ctx, x, y, x + w, y, s + 10);
        sketchyLine(ctx, x + w, y, x + w, y + h, s + 20);
        sketchyLine(ctx, x + w, y + h, x, y + h, s + 30);
        sketchyLine(ctx, x, y + h, x, y, s + 40);
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    if element.fillColor and element.fillColor != "transparent" {
        ctx.beginPath();
        ctx.rect(x, y, w, h);
        ctx.fill();
    }
}

def:pub drawCircle(ctx: any, element: dict) -> None {
    seed = element.x * 7 + element.y * 13 + element.width * 3 + element.height * 11;
    cx = element.x + element.width / 2;
    cy = element.y + element.height / 2;
    rx = Math.abs(element.width) / 2;
    ry = Math.abs(element.height) / 2;

    # Draw hand-drawn ellipse using many small segments with jitter
    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        segments = 36;
        step = (Math.PI * 2) / segments;
        j = 0;
        while j <= segments {
            angle = j * step;
            jRx = rx + jitter(seed + j * 3 + pass_i * 200, rx * 0.04);
            jRy = ry + jitter(seed + j * 3 + 1 + pass_i * 200, ry * 0.04);
            px = cx + jRx * Math.cos(angle);
            py = cy + jRy * Math.sin(angle);
            if j == 0 {
                ctx.moveTo(px, py);
            } else {
                prevAngle = (j - 0.5) * step;
                cpJRx = rx + jitter(seed + j * 3 + 2 + pass_i * 200, rx * 0.04);
                cpJRy = ry + jitter(seed + j * 3 + 3 + pass_i * 200, ry * 0.04);
                cpx = cx + cpJRx * Math.cos(prevAngle);
                cpy = cy + cpJRy * Math.sin(prevAngle);
                ctx.quadraticCurveTo(cpx, cpy, px, py);
            }
            j = j + 1;
        }
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    if element.fillColor and element.fillColor != "transparent" {
        ctx.beginPath();
        ctx.ellipse(cx, cy, rx, ry, 0, 0, 2 * Math.PI);
        ctx.fill();
    }
}

def:pub drawDiamond(ctx: any, element: dict) -> None {
    seed = element.x * 7 + element.y * 13 + element.width * 3 + element.height * 11;
    x = element.x;
    y = element.y;
    w = element.width;
    h = element.height;
    cx = x + w / 2;
    cy = y + h / 2;

    # Draw 2 passes for a hand-drawn double-line effect
    pass_i = 0;
    while pass_i < 2 {
        s = seed + pass_i * 100;
        ctx.beginPath();
        sketchyLine(ctx, cx, y, x + w, cy, s + 10);
        sketchyLine(ctx, x + w, cy, cx, y + h, s + 20);
        sketchyLine(ctx, cx, y + h, x, cy, s + 30);
        sketchyLine(ctx, x, cy, cx, y, s + 40);
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    if element.fillColor and element.fillColor != "transparent" {
        ctx.beginPath();
        ctx.moveTo(cx, y);
        ctx.lineTo(x + w, cy);
        ctx.lineTo(cx, y + h);
        ctx.lineTo(x, cy);
        ctx.closePath();
        ctx.fill();
    }
}

def:pub drawLine(ctx: any, element: dict) -> None {
    seed = element.x1 * 7 + element.y1 * 13 + element.x2 * 3 + element.y2 * 11;

    # Draw 2 passes for hand-drawn effect
    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        sketchyLine(ctx, element.x1, element.y1, element.x2, element.y2, seed + pass_i * 100);
        ctx.stroke();
        pass_i = pass_i + 1;
    }
}

def:pub drawArrow(ctx: any, element: dict) -> None {
    seed = element.x1 * 7 + element.y1 * 13 + element.x2 * 3 + element.y2 * 11;

    # Draw hand-drawn line (2 passes)
    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        sketchyLine(ctx, element.x1, element.y1, element.x2, element.y2, seed + pass_i * 100);
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    # Draw hand-drawn arrowhead
    headLen = 14;
    angle = Math.atan2(element.y2 - element.y1, element.x2 - element.x1);
    ax1 = element.x2 - headLen * Math.cos(angle - Math.PI / 6);
    ay1 = element.y2 - headLen * Math.sin(angle - Math.PI / 6);
    ax2 = element.x2 - headLen * Math.cos(angle + Math.PI / 6);
    ay2 = element.y2 - headLen * Math.sin(angle + Math.PI / 6);

    ctx.beginPath();
    sketchyLine(ctx, element.x2, element.y2, ax1, ay1, seed + 300);
    ctx.stroke();
    ctx.beginPath();
    sketchyLine(ctx, element.x2, element.y2, ax2, ay2, seed + 400);
    ctx.stroke();
}

def:pub drawPreview(ctx: any, tool: str, startPoint: dict, currentPoint: dict, color: str, strokeWidth: float) -> None {
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.globalAlpha = 0.6;

    if tool == "rectangle" {
        rw = currentPoint.x - startPoint.x;
        rh = currentPoint.y - startPoint.y;
        rSeed = startPoint.x * 7 + startPoint.y * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint.x, startPoint.y, startPoint.x + rw, startPoint.y, rSeed + 10);
        sketchyLine(ctx, startPoint.x + rw, startPoint.y, startPoint.x + rw, startPoint.y + rh, rSeed + 20);
        sketchyLine(ctx, startPoint.x + rw, startPoint.y + rh, startPoint.x, startPoint.y + rh, rSeed + 30);
        sketchyLine(ctx, startPoint.x, startPoint.y + rh, startPoint.x, startPoint.y, rSeed + 40);
        ctx.stroke();
    } elif tool == "circle" {
        ew = currentPoint.x - startPoint.x;
        eh = currentPoint.y - startPoint.y;
        eRx = Math.abs(ew) / 2;
        eRy = Math.abs(eh) / 2;
        eCx = startPoint.x + ew / 2;
        eCy = startPoint.y + eh / 2;
        eSeed = startPoint.x * 7 + startPoint.y * 13;
        ctx.beginPath();
        segments = 36;
        step = (Math.PI * 2) / segments;
        j = 0;
        while j <= segments {
            angle = j * step;
            jRx = eRx + jitter(eSeed + j * 3, eRx * 0.04);
            jRy = eRy + jitter(eSeed + j * 3 + 1, eRy * 0.04);
            px = eCx + jRx * Math.cos(angle);
            py = eCy + jRy * Math.sin(angle);
            if j == 0 {
                ctx.moveTo(px, py);
            } else {
                prevAngle = (j - 0.5) * step;
                cpJRx = eRx + jitter(eSeed + j * 3 + 2, eRx * 0.04);
                cpJRy = eRy + jitter(eSeed + j * 3 + 3, eRy * 0.04);
                cpx = eCx + cpJRx * Math.cos(prevAngle);
                cpy = eCy + cpJRy * Math.sin(prevAngle);
                ctx.quadraticCurveTo(cpx, cpy, px, py);
            }
            j = j + 1;
        }
        ctx.stroke();
    } elif tool == "diamond" {
        diamW = currentPoint.x - startPoint.x;
        diamH = currentPoint.y - startPoint.y;
        diamX = startPoint.x;
        diamY = startPoint.y;
        diamCx = diamX + diamW / 2;
        diamCy = diamY + diamH / 2;
        diamSeed = startPoint.x * 7 + startPoint.y * 13;
        ctx.beginPath();
        sketchyLine(ctx, diamCx, diamY, diamX + diamW, diamCy, diamSeed + 10);
        sketchyLine(ctx, diamX + diamW, diamCy, diamCx, diamY + diamH, diamSeed + 20);
        sketchyLine(ctx, diamCx, diamY + diamH, diamX, diamCy, diamSeed + 30);
        sketchyLine(ctx, diamX, diamCy, diamCx, diamY, diamSeed + 40);
        ctx.stroke();
    } elif tool == "line" {
        lineSeed = startPoint.x * 7 + startPoint.y * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint.x, startPoint.y, currentPoint.x, currentPoint.y, lineSeed);
        ctx.stroke();
    } elif tool == "arrow" {
        arrowSeed = startPoint.x * 7 + startPoint.y * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint.x, startPoint.y, currentPoint.x, currentPoint.y, arrowSeed);
        ctx.stroke();
        # Preview arrowhead
        headLen = 14;
        angle = Math.atan2(currentPoint.y - startPoint.y, currentPoint.x - startPoint.x);
        ax1 = currentPoint.x - headLen * Math.cos(angle - Math.PI / 6);
        ay1 = currentPoint.y - headLen * Math.sin(angle - Math.PI / 6);
        ax2 = currentPoint.x - headLen * Math.cos(angle + Math.PI / 6);
        ay2 = currentPoint.y - headLen * Math.sin(angle + Math.PI / 6);
        ctx.beginPath();
        sketchyLine(ctx, currentPoint.x, currentPoint.y, ax1, ay1, arrowSeed + 300);
        ctx.stroke();
        ctx.beginPath();
        sketchyLine(ctx, currentPoint.x, currentPoint.y, ax2, ay2, arrowSeed + 400);
        ctx.stroke();
    }

    ctx.globalAlpha = 1.0;
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
        lines = element.text.split(String.fromCharCode(10));
        maxWidth = 0;
        li = 0;
        while li < lines.length {
            lineWidth = ctx.measureText(lines[li]).width;
            if lineWidth > maxWidth {
                maxWidth = lineWidth;
            }
            li = li + 1;
        }
        textHeight = lines.length * element.fontSize * 1.2;
        return {
            "x": element.x - padding,
            "y": element.y - padding,
            "width": maxWidth + padding * 2,
            "height": textHeight + padding * 2
        };
    } elif element.type == "rectangle" or element.type == "circle" or element.type == "image" or element.type == "diamond" {
        return {
            "x": element.x - padding,
            "y": element.y - padding,
            "width": element.width + padding * 2,
            "height": element.height + padding * 2
        };
    } elif element.type == "line" or element.type == "arrow" {
        lMinX = Math.min(element.x1, element.x2);
        lMinY = Math.min(element.y1, element.y2);
        lMaxX = Math.max(element.x1, element.x2);
        lMaxY = Math.max(element.y1, element.y2);
        return {
            "x": lMinX - padding,
            "y": lMinY - padding,
            "width": (lMaxX - lMinX) + padding * 2,
            "height": (lMaxY - lMinY) + padding * 2
        };
    } elif element.type == "freehand" {
        if element.points.length > 0 {
            fMinX = element.points[0].x;
            fMinY = element.points[0].y;
            fMaxX = element.points[0].x;
            fMaxY = element.points[0].y;

            element.points.forEach(lambda point: dict -> None {
                if point.x < fMinX {
                    fMinX = point.x;
                }
                if point.y < fMinY {
                    fMinY = point.y;
                }
                if point.x > fMaxX {
                    fMaxX = point.x;
                }
                if point.y > fMaxY {
                    fMaxY = point.y;
                }
            });

            return {
                "x": fMinX - padding,
                "y": fMinY - padding,
                "width": (fMaxX - fMinX) + padding * 2,
                "height": (fMaxY - fMinY) + padding * 2
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
    ctx.fillStyle = "rgba(99, 102, 241, 0.3)";
    ctx.strokeStyle = "#6366f1";
    ctx.lineWidth = 1.5;
    i = 0;
    while i < points.length {
        cp = points[i];
        ctx.beginPath();
        ctx.arc(cp.x, cp.y, 5, 0, Math.PI * 2);
        ctx.fill();
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
