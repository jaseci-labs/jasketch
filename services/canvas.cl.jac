import from .geometry { getConnectionPoints, _rotate_points, getTextDimensions, get_elbow_full_points, get_freehand_center }

"""How wide a run of text really is, at the font it will be drawn in.

A detached canvas is enough: measureText needs a context, not a visible one.
Preferred over an element's scrollWidth, which on a <textarea> reports the
box's own width rather than its content and so cannot be used to shrink one."""
def:pub measure_text_width(text: str, font_size: float, font_family: str) -> float {
    probe = document.createElement("canvas");
    ctx = probe.getContext("2d");
    if not ctx {
        return len(str(text or "")) * font_size * 0.55;
    }
    ctx.font = font_size + "px " + font_family;
    return ctx.measureText(str(text or "")).width;
}


"""The widest line in a multi-line run of text."""
def:pub measure_widest_line(text: str, font_size: float, font_family: str) -> float {
    widest = 0.0;
    for line in str(text or "").split("\n") {
        w = measure_text_width(line, font_size, font_family);
        if w > widest {
            widest = w;
        }
    }
    return widest;
}


# Helper: Apply rotation transform to canvas context
def:pub apply_rotation_transform(ctx: any, element: dict) -> None {
    if element["rotation"] and (element["rotation"] != 0) {
        rotation = element["rotation"];
        # Compute center point based on element type
        cx = 0;
        cy = 0;
        if element["type"] == "text" {
            cx = element["x"] + element["fontSize"] / 2;
            cy = element["y"] + element["fontSize"] / 2;
        } elif element["type"] == "freehand" {
            fc = get_freehand_center(element);
            cx = fc["x"];
            cy = fc["y"];
        } else {
            cx = element["x"] + (element["width"] or 0) / 2;
            cy = element["y"] + (element["height"] or 0) / 2;
        }
        ctx.translate(cx, cy);
        ctx.rotate(rotation * Math.PI / 180);
        ctx.translate(-cx, -cy);
    }
}

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

def:pub drawElement(ctx: any, element: dict, onImageLoad: any) -> None {
    if element["type"] == "text" {
        drawTextElement(ctx, element);
    } elif element["type"] == "image" {
        drawImageElement(ctx, element, onImageLoad);
    } else {
        drawShapeElement(ctx, element);
    }
}

def:pub drawImageElement(ctx: any, element: dict, onImageLoad: any) -> None {
    if not element["imageObj"] or not element["imageObj"].src {
        img = new(Image);
        img.onload = lambda {
            # Image finished loading — request a canvas redraw
            if onImageLoad {
                onImageLoad();
            }
        };
        img.src = element["src"];
        element["imageObj"] = img;
    }
    if element["imageObj"].complete {
        ctx.save();
        ctx.globalAlpha = element["opacity"] or 1.0;
        ctx.shadowColor = "rgba(0, 0, 0, 0.1)";
        ctx.shadowBlur = 6;
        ctx.shadowOffsetX = 0;
        ctx.shadowOffsetY = 3;

        # Apply rotation transform if element has rotation
        apply_rotation_transform(ctx, element);

        ctx.drawImage(element["imageObj"], element["x"], element["y"], element["width"], element["height"]);
        ctx.restore();
    }
}

def:pub drawTextElement(ctx: any, element: dict) -> None {
    ctx.save();
    ctx.globalAlpha = element["opacity"] or 1.0;
    ctx.font = element["fontSize"] + "px " + element["fontFamily"];
    ctx.fillStyle = element["color"];
    ctx.textBaseline = "top";
    ctx.shadowColor = "rgba(0, 0, 0, 0.06)";
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 1;

    # Apply rotation transform if element has rotation
    apply_rotation_transform(ctx, element);

    lines = element["text"].split(String.fromCharCode(10));
    lineIdx = 0;
    while lineIdx < lines.length {
        ctx.fillText(lines[lineIdx], element["x"], element["y"] + (lineIdx * element["fontSize"] * 1.2));
        lineIdx = lineIdx + 1;
    }
    ctx.restore();
}

def wrapTextLines(ctx: any, text: str, maxWidth: float) -> list {
    # Split by explicit newlines first, then word-wrap each line
    rawLines = text.split(String.fromCharCode(10));
    wrapped = [];
    wri = 0;
    while wri < len(rawLines) {
        rawLine = rawLines[wri];
        if rawLine == "" {
            wrapped.append("");
            wri = wri + 1;
            continue;
        }
        words = rawLine.split(" ");
        currentLine = "";
        wrj = 0;
        while wrj < len(words) {
            word = words[wrj];

            # A word longer than the whole line can never fit by moving it to a
            # line of its own, so break it across lines. Without this the word
            # simply hangs out of both sides of the shape, which is what a
            # narrow box with a long label used to look like.
            if ctx.measureText(word).width > maxWidth {
                if currentLine != "" {
                    wrapped.append(currentLine);
                    currentLine = "";
                }
                piece = "";
                ci = 0;
                while ci < len(word) {
                    ch = word[ci];
                    if piece != "" and ctx.measureText(piece + ch).width > maxWidth {
                        wrapped.append(piece);
                        piece = ch;
                    } else {
                        piece = piece + ch;
                    }
                    ci = ci + 1;
                }
                currentLine = piece;
                wrj = wrj + 1;
                continue;
            }

            testLine = word;
            if currentLine != "" {
                testLine = currentLine + " " + word;
            }
            testWidth = ctx.measureText(testLine).width;
            if testWidth > maxWidth and currentLine != "" {
                wrapped.append(currentLine);
                currentLine = word;
            } else {
                currentLine = testLine;
            }
            wrj = wrj + 1;
        }
        if currentLine != "" {
            wrapped.append(currentLine);
        }
        wri = wri + 1;
    }
    return wrapped;
}

# Breathing room between a label and the edge of the shape holding it. Shared by
# the renderer and by shape_text_min_height so the two cannot drift apart.
glob SHAPE_TEXT_PADDING: float = 10.0;

# What the canvas actually looks like behind the elements (bg-gray-50/50 over
# white). A connector label knocks a hole in the line using this, so the words
# are not struck through by their own arrow.
glob CANVAS_BACKGROUND: str = "#fbfbfc";


"""The smallest height this shape can be without its label spilling out.

A label wraps to the shape's WIDTH, so a narrower shape needs a taller one to
hold the same words. Callers use this to grow a shape rather than let the text
escape it: a label that renders outside its own box makes a diagram look
broken, and the user has no way to put it back."""
def:pub shape_text_min_height(ctx: any, element: any) -> float {
    label = element["shapeText"] or "";
    if not label {
        return 0.0;
    }
    fontSize = element["shapeTextFontSize"] or 16;
    fontFamily = element["shapeTextFontFamily"] or "Virgil";
    ctx.save();
    # Must match drawShapeText exactly, or the measurement is of a different font.
    ctx.font = fontSize + "px " + fontFamily;
    maxWidth = Math.abs(element["width"]) - SHAPE_TEXT_PADDING * 2;
    if maxWidth < 20 {
        maxWidth = 20;
    }
    lines = wrapTextLines(ctx, label, maxWidth);
    ctx.restore();
    return len(lines) * fontSize * 1.2 + SHAPE_TEXT_PADDING * 2;
}


def drawShapeText(ctx: any, element: dict) -> None {
    if not element["shapeText"] {
        return;
    }
    ctx.save();
    stFontSize = element["shapeTextFontSize"] or 16;
    stFontFamily = element["shapeTextFontFamily"] or "Virgil";
    stColor = element["shapeTextColor"] or element["color"];

    ctx.font = stFontSize + "px " + stFontFamily;
    ctx.fillStyle = stColor;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;

    # Calculate shape center and available width (with padding)
    stCx = element["x"] + element["width"] / 2;
    stCy = element["y"] + element["height"] / 2;
    stMaxWidth = Math.abs(element["width"]) - SHAPE_TEXT_PADDING * 2;
    if stMaxWidth < 20 {
        stMaxWidth = 20;
    }

    stLines = wrapTextLines(ctx, element["shapeText"], stMaxWidth);
    stLineHeight = stFontSize * 1.2;
    stTotalHeight = len(stLines) * stLineHeight;
    stStartY = stCy - stTotalHeight / 2 + stLineHeight / 2;

    stIdx = 0;
    while stIdx < len(stLines) {
        ctx.fillText(stLines[stIdx], stCx, stStartY + stIdx * stLineHeight);
        stIdx = stIdx + 1;
    }
    ctx.restore();
}

"""Draw a label sitting on a line or arrow.

The connector is painted first and the label knocks a hole in it, so the words
sit ON the arrow rather than being crossed out by it. That hole is filled with
the canvas background rather than white, or a label would show as a pale block
on a dark canvas."""
def:pub drawLineLabel(ctx: any, element: dict, background: str) -> None {
    label = element["shapeText"] or "";
    if not label {
        return;
    }
    ctx.save();
    llFontSize = element["shapeTextFontSize"] or 16;
    llFontFamily = element["shapeTextFontFamily"] or "Virgil";
    ctx.font = llFontSize + "px " + llFontFamily;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;

    # The bend, when there is one: a curved arrow reads from its curve.
    llCx = (element["x1"] + element["x2"]) / 2;
    llCy = (element["y1"] + element["y2"]) / 2;
    if element["bendX"] != None and element["bendX"] != undefined {
        llCx = element["bendX"];
        llCy = element["bendY"];
    }

    # Wrap to a share of the connector's own length, so a label on a short
    # arrow stacks up rather than sprawling across the diagram.
    llSpan = Math.sqrt(
        Math.pow(element["x2"] - element["x1"], 2) + Math.pow(element["y2"] - element["y1"], 2)
    );
    llMaxWidth = Math.max(150.0, llSpan * 0.9);
    llLines = wrapTextLines(ctx, label, llMaxWidth);
    llLineHeight = llFontSize * 1.2;

    llWidest = 0.0;
    lli = 0;
    while lli < len(llLines) {
        llW = ctx.measureText(llLines[lli]).width;
        if llW > llWidest {
            llWidest = llW;
        }
        lli = lli + 1;
    }

    llPadX = 6.0;
    llPadY = 2.0;
    llBoxH = len(llLines) * llLineHeight;
    # CLEAR the line behind the words rather than painting over it. The canvas
    # sits on a dot grid, so a flat fill read as a pale box floating on the
    # page; clearing lets the page itself show through, whatever colour it is.
    ctx.clearRect(
        llCx - llWidest / 2 - llPadX,
        llCy - llBoxH / 2 - llPadY,
        llWidest + llPadX * 2,
        llBoxH + llPadY * 2
    );

    ctx.fillStyle = element["shapeTextColor"] or element["color"];
    llStartY = llCy - llBoxH / 2 + llLineHeight / 2;
    lli = 0;
    while lli < len(llLines) {
        ctx.fillText(llLines[lli], llCx, llStartY + lli * llLineHeight);
        lli = lli + 1;
    }
    ctx.restore();
}


"""A soft outline on the shape the pointer is over.

Answers "which one am I about to get" BEFORE the click, which matters most
exactly where it is hardest to tell: overlapping or closely packed shapes."""
def:pub draw_hover_outline(ctx: any, bounds: any, zoom: float) -> None {
    if not bounds {
        return;
    }
    ctx.save();
    ctx.strokeStyle = "rgba(232, 89, 12, 0.5)";
    # Constant on screen at any zoom: this is UI, not part of the drawing.
    ctx.lineWidth = 1.5 / zoom;
    ctx.setLineDash([]);
    pad = 3 / zoom;
    ctx.strokeRect(bounds.x - pad, bounds.y - pad, bounds.width + pad * 2, bounds.height + pad * 2);
    ctx.restore();
}


def:pub drawShapeElement(ctx: any, element: dict) -> None {
    ctx.save();
    ctx.globalAlpha = element["opacity"] or 1.0;
    ctx.strokeStyle = element["color"];
    ctx.lineWidth = element["strokeWidth"];
    ctx.fillStyle = element["fillColor"] or "transparent";
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    # No drop shadow. Shapes are stroked in two passes, so a shadow was applied
    # twice and every line sat under a doubled blur -- which is what made the
    # drawing read as soft and out of focus rather than confidently drawn.
    ctx.shadowColor = "transparent";
    ctx.shadowBlur = 0;
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;

    # Apply rotation transform if element has rotation
    apply_rotation_transform(ctx, element);

    # Apply line style
    lineStyle = element["lineStyle"] or "solid";
    if lineStyle == "dashed" {
        ctx.setLineDash([12, 6]);
    } elif lineStyle == "dotted" {
        ctx.setLineDash([3, 6]);
    } else {
        ctx.setLineDash([]);
    }

    if element["type"] == "freehand" {
        drawFreehand(ctx, element);
    } elif element["type"] == "rectangle" {
        drawRectangle(ctx, element);
    } elif element["type"] == "circle" {
        drawCircle(ctx, element);
    } elif element["type"] == "diamond" {
        drawDiamond(ctx, element);
    } elif element["type"] == "line" {
        drawLine(ctx, element);
    } elif element["type"] == "arrow" {
        drawArrow(ctx, element);
    }
    # A label belongs at the middle of a connector, not at the centre of a
    # bounding box the connector does not have.
    if element["type"] == "line" or element["type"] == "arrow" {
        drawLineLabel(ctx, element, CANVAS_BACKGROUND);
    } else {
        drawShapeText(ctx, element);
    }
    ctx.restore();
}

def:pub drawFreehand(ctx: any, element: dict) -> None {
    points = element["points"];
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

"""Corner radius for a box. Zero when the element asks for sharp edges.

Scaled to the box so a small shape does not turn into a lozenge, and capped so
a very large one still reads as a rectangle."""
def _corner_radius(element: dict) -> float {
    if element["edges"] == "sharp" {
        return 0.0;
    }
    w = Math.abs(element["width"]);
    h = Math.abs(element["height"]);
    return Math.min(24.0, w * 0.16, h * 0.16);
}


def:pub drawRectangle(ctx: any, element: dict) -> None {
    seed = element["x"] * 7 + element["y"] * 13 + element["width"] * 3 + element["height"] * 11;
    x = element["x"];
    y = element["y"];
    w = element["width"];
    h = element["height"];
    r = _corner_radius(element);

    # Draw 2 passes for a hand-drawn double-line effect
    pass_i = 0;
    while pass_i < 2 {
        s = seed + pass_i * 100;
        ctx.beginPath();
        if r < 1.0 {
            sketchyLine(ctx, x, y, x + w, y, s + 10);
            sketchyLine(ctx, x + w, y, x + w, y + h, s + 20);
            sketchyLine(ctx, x + w, y + h, x, y + h, s + 30);
            sketchyLine(ctx, x, y + h, x, y, s + 40);
        } else {
            # Sides stop short of each corner; the corners themselves are clean
            # arcs. Wobbling a corner as well reads as a mistake rather than as
            # a hand-drawn line.
            sketchyLine(ctx, x + r, y, x + w - r, y, s + 10);
            ctx.moveTo(x + w - r, y);
            ctx.quadraticCurveTo(x + w, y, x + w, y + r);
            sketchyLine(ctx, x + w, y + r, x + w, y + h - r, s + 20);
            ctx.moveTo(x + w, y + h - r);
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
            sketchyLine(ctx, x + w - r, y + h, x + r, y + h, s + 30);
            ctx.moveTo(x + r, y + h);
            ctx.quadraticCurveTo(x, y + h, x, y + h - r);
            sketchyLine(ctx, x, y + h - r, x, y + r, s + 40);
            ctx.moveTo(x, y + r);
            ctx.quadraticCurveTo(x, y, x + r, y);
        }
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    if element["fillColor"] and element["fillColor"] != "transparent" {
        ctx.beginPath();
        if r < 1.0 {
            ctx.rect(x, y, w, h);
        } else {
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + w - r, y);
            ctx.quadraticCurveTo(x + w, y, x + w, y + r);
            ctx.lineTo(x + w, y + h - r);
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
            ctx.lineTo(x + r, y + h);
            ctx.quadraticCurveTo(x, y + h, x, y + h - r);
            ctx.lineTo(x, y + r);
            ctx.quadraticCurveTo(x, y, x + r, y);
            ctx.closePath();
        }
        ctx.fill();
    }
}

def:pub drawCircle(ctx: any, element: dict) -> None {
    seed = element["x"] * 7 + element["y"] * 13 + element["width"] * 3 + element["height"] * 11;
    cx = element["x"] + element["width"] / 2;
    cy = element["y"] + element["height"] / 2;
    rx = Math.abs(element["width"]) / 2;
    ry = Math.abs(element["height"]) / 2;

    # Draw hand-drawn ellipse — 2 slightly offset passes for Excalidraw style
    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        segments = 64;
        step = (Math.PI * 2) / segments;
        startOffset = pass_i * 0.3;
        wobble = Math.min(Math.max(rx, ry) * 0.02, 2.5);
        j = 0;
        while j <= segments {
            angle = j * step + startOffset;
            jRx = rx + jitter(seed + j * 3 + pass_i * 200, wobble);
            jRy = ry + jitter(seed + j * 3 + 1 + pass_i * 200, wobble);
            px = cx + jRx * Math.cos(angle);
            py = cy + jRy * Math.sin(angle);
            if j == 0 {
                ctx.moveTo(px, py);
            } else {
                prevAngle = (j - 0.5) * step + startOffset;
                cpJRx = rx + jitter(seed + j * 3 + 2 + pass_i * 200, wobble);
                cpJRy = ry + jitter(seed + j * 3 + 3 + pass_i * 200, wobble);
                cpx = cx + cpJRx * Math.cos(prevAngle);
                cpy = cy + cpJRy * Math.sin(prevAngle);
                ctx.quadraticCurveTo(cpx, cpy, px, py);
            }
            j = j + 1;
        }
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    if element["fillColor"] and element["fillColor"] != "transparent" {
        ctx.beginPath();
        ctx.ellipse(cx, cy, rx, ry, 0, 0, 2 * Math.PI);
        ctx.fill();
    }
}

def:pub drawDiamond(ctx: any, element: dict) -> None {
    seed = element["x"] * 7 + element["y"] * 13 + element["width"] * 3 + element["height"] * 11;
    x = element["x"];
    y = element["y"];
    w = element["width"];
    h = element["height"];
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

    if element["fillColor"] and element["fillColor"] != "transparent" {
        ctx.beginPath();
        ctx.moveTo(cx, y);
        ctx.lineTo(x + w, cy);
        ctx.lineTo(cx, y + h);
        ctx.lineTo(x, cy);
        ctx.closePath();
        ctx.fill();
    }
}

def sketchyCurve(ctx: any, x1: float, y1: float, cpx: float, cpy: float, x2: float, y2: float, seed: float) -> None {
    wobble = Math.min(Math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)) * 0.03, 2);
    ctx.moveTo(x1 + jitter(seed + 1, wobble), y1 + jitter(seed + 2, wobble));
    ctx.quadraticCurveTo(cpx + jitter(seed + 3, wobble), cpy + jitter(seed + 4, wobble), x2 + jitter(seed + 5, wobble), y2 + jitter(seed + 6, wobble));
}

def drawElbowPath(ctx: any, element: dict, seed: float, pass_i: int) -> None {
    elbowPts = get_elbow_full_points(element);
    eptLen = len(elbowPts);
    if eptLen >= 2 {
        elj = jitter(seed + pass_i * 37, 1.2);
        ctx.moveTo(elbowPts[0].x + elj, elbowPts[0].y + jitter(seed + pass_i * 37 + 1, 1.2));
        ept_i = 1;
        while ept_i < eptLen - 1 {
            pPrev = elbowPts[ept_i - 1];
            pCur = elbowPts[ept_i];
            pNext = elbowPts[ept_i + 1];
            segLen1 = Math.sqrt((pCur.x - pPrev.x) * (pCur.x - pPrev.x) + (pCur.y - pPrev.y) * (pCur.y - pPrev.y));
            segLen2 = Math.sqrt((pNext.x - pCur.x) * (pNext.x - pCur.x) + (pNext.y - pCur.y) * (pNext.y - pCur.y));
            elr = Math.min(16, segLen1 / 2, segLen2 / 2);
            isH1 = Math.abs(pCur.x - pPrev.x) >= Math.abs(pCur.y - pPrev.y);
            edx1 = isH1 and ((pCur.x > pPrev.x) and 1 or -1) or 0;
            edy1 = (not isH1) and ((pCur.y > pPrev.y) and 1 or -1) or 0;
            isH2 = Math.abs(pNext.x - pCur.x) >= Math.abs(pNext.y - pCur.y);
            edx2 = isH2 and ((pNext.x > pCur.x) and 1 or -1) or 0;
            edy2 = (not isH2) and ((pNext.y > pCur.y) and 1 or -1) or 0;
            ctx.lineTo(pCur.x - edx1 * elr, pCur.y - edy1 * elr);
            ctx.quadraticCurveTo(pCur.x, pCur.y, pCur.x + edx2 * elr, pCur.y + edy2 * elr);
            ept_i = ept_i + 1;
        }
        ctx.lineTo(elbowPts[eptLen - 1].x + elj, elbowPts[eptLen - 1].y + jitter(seed + pass_i * 37 + 3, 1.2));
    }
}

def:pub drawLine(ctx: any, element: dict) -> None {
    seed = element["x1"] * 7 + element["y1"] * 13 + element["x2"] * 3 + element["y2"] * 11;
    curveStyle = element["curveStyle"] or "curved";

    # Pre-compute sharp bend point (V-apex, defaults to midpoint)
    sharpBX = (element["x1"] + element["x2"]) / 2;
    sharpBY = (element["y1"] + element["y2"]) / 2;
    if element["bendX"] != None and element["bendX"] != undefined {
        sharpBX = element["bendX"];
        sharpBY = element["bendY"];
    }

    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        if curveStyle == "sharp" or curveStyle == "straight" {
            # sharp: straight segments — V-shape if bend point set, else direct line
            if element["bendX"] != None and element["bendX"] != undefined {
                sketchyLine(ctx, element["x1"], element["y1"], sharpBX, sharpBY, seed + pass_i * 100);
                sketchyLine(ctx, sharpBX, sharpBY, element["x2"], element["y2"], seed + pass_i * 100 + 50);
            } else {
                sketchyLine(ctx, element["x1"], element["y1"], element["x2"], element["y2"], seed + pass_i * 100);
            }
        } elif curveStyle == "elbow" {
            drawElbowPath(ctx, element, seed, pass_i);
        } else {
            # curved (default): quadratic bezier if bend set, else straight sketchy line
            if element["bendX"] != None and element["bendX"] != undefined {
                sketchyCurve(ctx, element["x1"], element["y1"], element["bendX"], element["bendY"], element["x2"], element["y2"], seed + pass_i * 100);
            } else {
                sketchyLine(ctx, element["x1"], element["y1"], element["x2"], element["y2"], seed + pass_i * 100);
            }
        }
        ctx.stroke();
        pass_i = pass_i + 1;
    }
}

def:pub drawArrow(ctx: any, element: dict) -> None {
    seed = element["x1"] * 7 + element["y1"] * 13 + element["x2"] * 3 + element["y2"] * 11;
    curveStyle = element["curveStyle"] or "curved";

    # Pre-compute sharp bend point (V-apex for sharp style)
    sharpBX = (element["x1"] + element["x2"]) / 2;
    sharpBY = (element["y1"] + element["y2"]) / 2;
    if element["bendX"] != None and element["bendX"] != undefined {
        sharpBX = element["bendX"];
        sharpBY = element["bendY"];
    }
    # Pre-compute arrowhead angle for sharp
    sharpAngle = Math.atan2(element["y2"] - element["y1"], element["x2"] - element["x1"]);
    if element["bendX"] != None and element["bendX"] != undefined {
        sharpAngle = Math.atan2(element["y2"] - sharpBY, element["x2"] - sharpBX);
    }

    pass_i = 0;
    while pass_i < 2 {
        ctx.beginPath();
        if curveStyle == "sharp" or curveStyle == "straight" {
            if element["bendX"] != None and element["bendX"] != undefined {
                sketchyLine(ctx, element["x1"], element["y1"], sharpBX, sharpBY, seed + pass_i * 100);
                sketchyLine(ctx, sharpBX, sharpBY, element["x2"], element["y2"], seed + pass_i * 100 + 50);
            } else {
                sketchyLine(ctx, element["x1"], element["y1"], element["x2"], element["y2"], seed + pass_i * 100);
            }
        } elif curveStyle == "elbow" {
            drawElbowPath(ctx, element, seed, pass_i);
        } else {
            if element["bendX"] != None and element["bendX"] != undefined {
                sketchyCurve(ctx, element["x1"], element["y1"], element["bendX"], element["bendY"], element["x2"], element["y2"], seed + pass_i * 100);
            } else {
                sketchyLine(ctx, element["x1"], element["y1"], element["x2"], element["y2"], seed + pass_i * 100);
            }
        }
        ctx.stroke();
        pass_i = pass_i + 1;
    }

    # Arrowhead — angle based on direction of last segment
    headLen = 14;
    arrowAngle = Math.atan2(element["y2"] - element["y1"], element["x2"] - element["x1"]);
    if curveStyle == "elbow" {
        elbowPtsA = get_elbow_full_points(element);
        eptLenA = len(elbowPtsA);
        if eptLenA >= 2 {
            pSecondLast = elbowPtsA[eptLenA - 2];
            pLast = elbowPtsA[eptLenA - 1];
            arrowAngle = Math.atan2(pLast.y - pSecondLast.y, pLast.x - pSecondLast.x);
        }
    } elif curveStyle == "sharp" or curveStyle == "straight" {
        arrowAngle = sharpAngle;
    } else {
        if element["bendX"] != None and element["bendX"] != undefined {
            arrowAngle = Math.atan2(element["y2"] - element["bendY"], element["x2"] - element["bendX"]);
        } else {
            arrowAngle = Math.atan2(element["y2"] - element["y1"], element["x2"] - element["x1"]);
        }
    }
    ax1 = element["x2"] - headLen * Math.cos(arrowAngle - Math.PI / 6);
    ay1 = element["y2"] - headLen * Math.sin(arrowAngle - Math.PI / 6);
    ax2 = element["x2"] - headLen * Math.cos(arrowAngle + Math.PI / 6);
    ay2 = element["y2"] - headLen * Math.sin(arrowAngle + Math.PI / 6);

    ctx.beginPath();
    sketchyLine(ctx, element["x2"], element["y2"], ax1, ay1, seed + 300);
    ctx.stroke();
    ctx.beginPath();
    sketchyLine(ctx, element["x2"], element["y2"], ax2, ay2, seed + 400);
    ctx.stroke();
}

def:pub drawPreview(ctx: any, tool: str, startPoint: dict, currentPoint: dict, color: str, strokeWidth: float) -> None {
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.globalAlpha = 0.6;

    if tool == "rectangle" {
        rw = currentPoint["x"] - startPoint["x"];
        rh = currentPoint["y"] - startPoint["y"];
        rSeed = startPoint["x"] * 7 + startPoint["y"] * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint["x"], startPoint["y"], startPoint["x"] + rw, startPoint["y"], rSeed + 10);
        sketchyLine(ctx, startPoint["x"] + rw, startPoint["y"], startPoint["x"] + rw, startPoint["y"] + rh, rSeed + 20);
        sketchyLine(ctx, startPoint["x"] + rw, startPoint["y"] + rh, startPoint["x"], startPoint["y"] + rh, rSeed + 30);
        sketchyLine(ctx, startPoint["x"], startPoint["y"] + rh, startPoint["x"], startPoint["y"], rSeed + 40);
        ctx.stroke();
    } elif tool == "circle" {
        ew = currentPoint["x"] - startPoint["x"];
        eh = currentPoint["y"] - startPoint["y"];
        eRx = Math.abs(ew) / 2;
        eRy = Math.abs(eh) / 2;
        eCx = startPoint["x"] + ew / 2;
        eCy = startPoint["y"] + eh / 2;
        eSeed = startPoint["x"] * 7 + startPoint["y"] * 13;
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
        diamW = currentPoint["x"] - startPoint["x"];
        diamH = currentPoint["y"] - startPoint["y"];
        diamX = startPoint["x"];
        diamY = startPoint["y"];
        diamCx = diamX + diamW / 2;
        diamCy = diamY + diamH / 2;
        diamSeed = startPoint["x"] * 7 + startPoint["y"] * 13;
        ctx.beginPath();
        sketchyLine(ctx, diamCx, diamY, diamX + diamW, diamCy, diamSeed + 10);
        sketchyLine(ctx, diamX + diamW, diamCy, diamCx, diamY + diamH, diamSeed + 20);
        sketchyLine(ctx, diamCx, diamY + diamH, diamX, diamCy, diamSeed + 30);
        sketchyLine(ctx, diamX, diamCy, diamCx, diamY, diamSeed + 40);
        ctx.stroke();
    } elif tool == "line" {
        lineSeed = startPoint["x"] * 7 + startPoint["y"] * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint["x"], startPoint["y"], currentPoint["x"], currentPoint["y"], lineSeed);
        ctx.stroke();
    } elif tool == "arrow" {
        arrowSeed = startPoint["x"] * 7 + startPoint["y"] * 13;
        ctx.beginPath();
        sketchyLine(ctx, startPoint["x"], startPoint["y"], currentPoint["x"], currentPoint["y"], arrowSeed);
        ctx.stroke();
        # Preview arrowhead
        headLen = 14;
        angle = Math.atan2(currentPoint["y"] - startPoint["y"], currentPoint["x"] - startPoint["x"]);
        ax1 = currentPoint["x"] - headLen * Math.cos(angle - Math.PI / 6);
        ay1 = currentPoint["y"] - headLen * Math.sin(angle - Math.PI / 6);
        ax2 = currentPoint["x"] - headLen * Math.cos(angle + Math.PI / 6);
        ay2 = currentPoint["y"] - headLen * Math.sin(angle + Math.PI / 6);
        ctx.beginPath();
        sketchyLine(ctx, currentPoint["x"], currentPoint["y"], ax1, ay1, arrowSeed + 300);
        ctx.stroke();
        ctx.beginPath();
        sketchyLine(ctx, currentPoint["x"], currentPoint["y"], ax2, ay2, arrowSeed + 400);
        ctx.stroke();
    }

    ctx.globalAlpha = 1.0;
}

def:pub applyViewportTransform(ctx: any, zoom: float, panOffset: dict) -> None {
    ctx.translate(panOffset["x"], panOffset["y"]);
    ctx.scale(zoom, zoom);
}

def:pub drawBoxSelectionRect(ctx: any, boxStart: dict, boxEnd: dict) -> None {
    ctx.save();
    ctx.strokeStyle = "#f97316";
    ctx.fillStyle = "rgba(249, 115, 22, 0.1)";
    ctx.lineWidth = 2;
    ctx.setLineDash([5, 5]);

    x = Math.min(boxStart["x"], boxEnd["x"]);
    y = Math.min(boxStart["y"], boxEnd["y"]);
    width = Math.abs(boxEnd["x"] - boxStart["x"]);
    height = Math.abs(boxEnd["y"] - boxStart["y"]);

    ctx.fillRect(x, y, width, height);
    ctx.strokeRect(x, y, width, height);

    ctx.setLineDash([]);
    ctx.restore();
}

def:pub getElementBounds(ctx: any, element: dict) -> dict {
    padding = 5;
    if element["type"] == "text" {
        ctx.font = element["fontSize"] + "px " + element["fontFamily"];
        lines = element["text"].split(String.fromCharCode(10));
        maxWidth = 0;
        li = 0;
        while li < lines.length {
            lineWidth = ctx.measureText(lines[li]).width;
            if lineWidth > maxWidth {
                maxWidth = lineWidth;
            }
            li = li + 1;
        }
        textHeight = lines.length * element["fontSize"] * 1.2;
        return {
            "x": element["x"] - padding,
            "y": element["y"] - padding,
            "width": maxWidth + padding * 2,
            "height": textHeight + padding * 2
        };
    } elif element["type"] == "rectangle" or element["type"] == "circle" or element["type"] == "image" or element["type"] == "diamond" {
        return {
            "x": element["x"] - padding,
            "y": element["y"] - padding,
            "width": element["width"] + padding * 2,
            "height": element["height"] + padding * 2
        };
    } elif element["type"] == "line" or element["type"] == "arrow" {
        lMinX = Math.min(element["x1"], element["x2"]);
        lMinY = Math.min(element["y1"], element["y2"]);
        lMaxX = Math.max(element["x1"], element["x2"]);
        lMaxY = Math.max(element["y1"], element["y2"]);
        if element["bendX"] != None and element["bendX"] != undefined {
            if element["bendX"] < lMinX { lMinX = element["bendX"]; }
            if element["bendY"] < lMinY { lMinY = element["bendY"]; }
            if element["bendX"] > lMaxX { lMaxX = element["bendX"]; }
            if element["bendY"] > lMaxY { lMaxY = element["bendY"]; }
        }
        return {
            "x": lMinX - padding,
            "y": lMinY - padding,
            "width": (lMaxX - lMinX) + padding * 2,
            "height": (lMaxY - lMinY) + padding * 2
        };
    } elif element["type"] == "freehand" {
        if element["points"].length > 0 {
            fMinX = element["points"][0].x;
            fMinY = element["points"][0].y;
            fMaxX = element["points"][0].x;
            fMaxY = element["points"][0].y;

            fpi = 0;
            while fpi < element["points"].length {
                fPoint = element["points"][fpi];
                if fPoint.x < fMinX {
                    fMinX = fPoint.x;
                }
                if fPoint.y < fMinY {
                    fMinY = fPoint.y;
                }
                if fPoint.x > fMaxX {
                    fMaxX = fPoint.x;
                }
                if fPoint.y > fMaxY {
                    fMaxY = fPoint.y;
                }
                fpi = fpi + 1;
            }

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

    # Apply rotation transform if element has rotation
    if element["rotation"] and (element["rotation"] != 0) {
        rotation = element["rotation"];
        cx = bounds["x"] + bounds["width"] / 2;
        cy = bounds["y"] + bounds["height"] / 2;
        ctx.translate(cx, cy);
        ctx.rotate(rotation * Math.PI / 180);
        ctx.translate(-cx, -cy);
    }

    if element["type"] == "line" or element["type"] == "arrow" {
        # For lines/arrows: draw only start vertex, end vertex, and bend handle
        ctx.fillStyle = "#ffffff";
        ctx.strokeStyle = "#f97316";
        ctx.lineWidth = 1.5;
        # Start vertex handle
        ctx.beginPath();
        ctx.arc(element["x1"], element["y1"], 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        # End vertex handle
        ctx.beginPath();
        ctx.arc(element["x2"], element["y2"], 5, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        selCurveStyle = element["curveStyle"] or "curved";
        if selCurveStyle == "elbow" {
            # Elbow: ghost segment midpoint handles at each segment center
            elbowSelPts = get_elbow_full_points(element);
            ctx.fillStyle = "rgba(130, 100, 230, 0.65)";
            ctx.strokeStyle = "rgba(100, 70, 200, 0.5)";
            ctx.lineWidth = 1;
            shi = 1;
            while shi < len(elbowSelPts) {
                segMidX = (elbowSelPts[shi - 1].x + elbowSelPts[shi].x) / 2;
                segMidY = (elbowSelPts[shi - 1].y + elbowSelPts[shi].y) / 2;
                ctx.beginPath();
                ctx.arc(segMidX, segMidY, 5, 0, Math.PI * 2);
                ctx.fill();
                ctx.stroke();
                shi = shi + 1;
            }
        } elif selCurveStyle != "straight" {
            # sharp/curved: bend handle at bendX/bendY or midpoint
            ctx.fillStyle = "#ffffff";
            ctx.strokeStyle = "#f97316";
            ctx.lineWidth = 1.5;
            bendHandleX = (element["x1"] + element["x2"]) / 2;
            bendHandleY = (element["y1"] + element["y2"]) / 2;
            if element["bendX"] != None and element["bendX"] != undefined {
                bendHandleX = element["bendX"];
                bendHandleY = element["bendY"];
            }
            ctx.beginPath();
            ctx.arc(bendHandleX, bendHandleY, 5, 0, Math.PI * 2);
            ctx.fill();
            ctx.stroke();
        }
        ctx.restore();
        return;
    }

    # Solid selection border for shapes
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([]);
    ctx.strokeRect(bounds["x"], bounds["y"], bounds["width"], bounds["height"]);

    # Draw resize handles at corners and edges
    handleSize = 6;
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 1.5;

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
    while i < len(handlePositions) {
        hp = handlePositions[i];
        ctx.beginPath();
        ctx.arc(hp.x, hp.y, handleSize / 2, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        i = i + 1;
    }

    # Draw rotation handle for supported element types
    supportedForRotation = element["type"] == "rectangle" or element["type"] == "circle" or element["type"] == "diamond" or element["type"] == "image" or element["type"] == "text" or element["type"] == "freehand";
    if supportedForRotation {
        rotHandleX = bounds["x"] + bounds["width"] / 2;
        rotHandleY = bounds["y"] - 28;
        # Draw connecting line from top-center to handle
        ctx.beginPath();
        ctx.moveTo(bounds["x"] + bounds["width"] / 2, bounds["y"]);
        ctx.lineTo(rotHandleX, rotHandleY);
        ctx.strokeStyle = "#f97316";
        ctx.lineWidth = 1;
        ctx.stroke();
        # Draw rotation handle circle
        ctx.beginPath();
        ctx.arc(rotHandleX, rotHandleY, 5, 0, Math.PI * 2);
        ctx.fillStyle = "#ffffff";
        ctx.fill();
        ctx.strokeStyle = "#f97316";
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }

    ctx.restore();
}

def:pub drawGroupSelectionBox(ctx: any, elements: list) -> None {
    if len(elements) == 0 {
        return;
    }
    ctx.save();
    # Compute combined bounding box across all elements
    firstBounds = getElementBounds(ctx, elements[0]);
    gMinX = firstBounds["x"];
    gMinY = firstBounds["y"];
    gMaxX = firstBounds["x"] + firstBounds["width"];
    gMaxY = firstBounds["y"] + firstBounds["height"];
    gbi = 1;
    while gbi < len(elements) {
        elBounds = getElementBounds(ctx, elements[gbi]);
        if elBounds["x"] < gMinX { gMinX = elBounds["x"]; }
        if elBounds["y"] < gMinY { gMinY = elBounds["y"]; }
        if elBounds["x"] + elBounds["width"] > gMaxX { gMaxX = elBounds["x"] + elBounds["width"]; }
        if elBounds["y"] + elBounds["height"] > gMaxY { gMaxY = elBounds["y"] + elBounds["height"]; }
        gbi = gbi + 1;
    }
    # Add padding
    pad = 4;
    gMinX = gMinX - pad;
    gMinY = gMinY - pad;
    gMaxX = gMaxX + pad;
    gMaxY = gMaxY + pad;
    groupW = gMaxX - gMinX;
    groupH = gMaxY - gMinY;

    # Solid selection border
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 1.5;
    ctx.setLineDash([]);
    ctx.strokeRect(gMinX, gMinY, groupW, groupH);

    # Draw resize handles at corners and edges
    ghSize = 6;
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 1.5;

    ghPositions = [
        {"x": gMinX, "y": gMinY},
        {"x": gMinX + groupW / 2, "y": gMinY},
        {"x": gMaxX, "y": gMinY},
        {"x": gMaxX, "y": gMinY + groupH / 2},
        {"x": gMaxX, "y": gMaxY},
        {"x": gMinX + groupW / 2, "y": gMaxY},
        {"x": gMinX, "y": gMaxY},
        {"x": gMinX, "y": gMinY + groupH / 2}
    ];

    ghi = 0;
    while ghi < len(ghPositions) {
        ghp = ghPositions[ghi];
        ctx.beginPath();
        ctx.arc(ghp.x, ghp.y, ghSize / 2, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ghi = ghi + 1;
    }

    ctx.restore();
}

def:pub drawConnectionPoints(ctx: any, element: dict) -> None {
    points = getConnectionPoints(element);
    if len(points) == 0 {
        return;
    }
    # Apply rotation to connection points if element is rotated
    if element["rotation"] and (element["rotation"] != 0) {
        dc_cx = element["x"] + element["width"] / 2;
        dc_cy = element["y"] + element["height"] / 2;
        if element["type"] == "text" {
            dc_dims = getTextDimensions(element["text"], element["fontSize"]);
            dc_cx = element["x"] + dc_dims["width"] / 2;
            dc_cy = element["y"] + dc_dims["height"] / 2;
        }
        points = _rotate_points(points, dc_cx, dc_cy, element["rotation"]);
    }
    ctx.save();
    ctx.fillStyle = "rgba(249, 115, 22, 0.3)";
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 1.5;
    i = 0;
    while i < len(points) {
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
    ctx.arc(point["x"], point["y"], 7, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(249, 115, 22, 0.5)";
    ctx.fill();
    ctx.strokeStyle = "#f97316";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.restore();
}
