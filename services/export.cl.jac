import from .canvas { drawElement, getElementBounds }

def extractElements(selectedElements: list) -> list {
    elements = [];
    i = 0;
    while i < selectedElements.length {
        elements.push(selectedElements[i].element);
        i = i + 1;
    }
    return elements;
}

def getSelectedElementsBounds(ctx: any, elements: list) -> dict {
    if elements.length == 0 {
        return {"x": 0, "y": 0, "width": 0, "height": 0};
    }

    first = getElementBounds(ctx, elements[0]);
    minX = first.x;
    minY = first.y;
    maxX = first.x + first.width;
    maxY = first.y + first.height;

    i = 1;
    while i < elements.length {
        bounds = getElementBounds(ctx, elements[i]);
        if bounds.x < minX { minX = bounds.x; }
        if bounds.y < minY { minY = bounds.y; }
        if bounds.x + bounds.width > maxX { maxX = bounds.x + bounds.width; }
        if bounds.y + bounds.height > maxY { maxY = bounds.y + bounds.height; }
        i = i + 1;
    }

    return {
        "x": minX,
        "y": minY,
        "width": maxX - minX,
        "height": maxY - minY
    };
}

def renderToOffscreenCanvas(elements: list, bounds: dict, dpr: float) -> any {
    padding = 20;
    w = bounds.width + padding * 2;
    h = bounds.height + padding * 2;

    offscreen = document.createElement("canvas");
    offscreen.width = w * dpr;
    offscreen.height = h * dpr;
    ctx = offscreen.getContext("2d");
    ctx.scale(dpr, dpr);

    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, w, h);

    ctx.save();
    ctx.translate(padding - bounds.x, padding - bounds.y);
    i = 0;
    while i < elements.length {
        drawElement(ctx, elements[i]);
        i = i + 1;
    }
    ctx.restore();

    return offscreen;
}

def downloadBlob(url: str, filename: str) -> None {
    a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

def buildSvgString(elements: list, bounds: dict) -> str {
    newline = String.fromCharCode(10);
    padding = 20;
    svgW = bounds.width + padding * 2;
    svgH = bounds.height + padding * 2;
    svgOffX = padding - bounds.x;
    svgOffY = padding - bounds.y;
    headLen = 14;

    parts = [];
    parts.push("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + String(Math.ceil(svgW)) + "\" height=\"" + String(Math.ceil(svgH)) + "\" viewBox=\"0 0 " + String(Math.ceil(svgW)) + " " + String(Math.ceil(svgH)) + "\">");
    parts.push("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>");
    parts.push("<g transform=\"translate(" + String(svgOffX) + "," + String(svgOffY) + ")\">");

    si = 0;
    while si < elements.length {
        el = elements[si];
        dashAttr = "";
        if el.lineStyle == "dashed" {
            dashAttr = " stroke-dasharray=\"12,6\"";
        } elif el.lineStyle == "dotted" {
            dashAttr = " stroke-dasharray=\"3,6\"";
        }

        fillVal = el.fillColor or "transparent";

        if el.type == "rectangle" {
            parts.push("<rect x=\"" + String(el.x) + "\" y=\"" + String(el.y) + "\" width=\"" + String(el.width) + "\" height=\"" + String(el.height) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\" rx=\"8\"" + dashAttr + "/>");
        } elif el.type == "diamond" {
            dCx = el.x + el.width / 2;
            dCy = el.y + el.height / 2;
            topPt = String(dCx) + "," + String(el.y);
            rightPt = String(el.x + el.width) + "," + String(dCy);
            bottomPt = String(dCx) + "," + String(el.y + el.height);
            leftPt = String(el.x) + "," + String(dCy);
            parts.push("<polygon points=\"" + topPt + " " + rightPt + " " + bottomPt + " " + leftPt + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "circle" {
            eCx = el.x + el.width / 2;
            eCy = el.y + el.height / 2;
            eRx = Math.abs(el.width) / 2;
            eRy = Math.abs(el.height) / 2;
            parts.push("<ellipse cx=\"" + String(eCx) + "\" cy=\"" + String(eCy) + "\" rx=\"" + String(eRx) + "\" ry=\"" + String(eRy) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "line" {
            if el.bendX != None and el.bendX != undefined {
                svgD = "M " + String(el.x1) + " " + String(el.y1) + " Q " + String(el.bendX) + " " + String(el.bendY) + " " + String(el.x2) + " " + String(el.y2);
                parts.push("<path d=\"" + svgD + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\"" + dashAttr + "/>");
            } else {
                parts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"" + dashAttr + "/>");
            }
        } elif el.type == "arrow" {
            if el.bendX != None and el.bendX != undefined {
                asvgD = "M " + String(el.x1) + " " + String(el.y1) + " Q " + String(el.bendX) + " " + String(el.bendY) + " " + String(el.x2) + " " + String(el.y2);
                parts.push("<path d=\"" + asvgD + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\"" + dashAttr + "/>");
            } else {
                parts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"" + dashAttr + "/>");
            }
            arrAngle = 0;
            if el.bendX != None and el.bendX != undefined {
                arrAngle = Math.atan2(el.y2 - el.bendY, el.x2 - el.bendX);
            } else {
                arrAngle = Math.atan2(el.y2 - el.y1, el.x2 - el.x1);
            }
            ax1 = el.x2 - headLen * Math.cos(arrAngle - Math.PI / 6);
            ay1 = el.y2 - headLen * Math.sin(arrAngle - Math.PI / 6);
            ax2 = el.x2 - headLen * Math.cos(arrAngle + Math.PI / 6);
            ay2 = el.y2 - headLen * Math.sin(arrAngle + Math.PI / 6);
            parts.push("<polygon points=\"" + String(el.x2) + "," + String(el.y2) + " " + String(ax1) + "," + String(ay1) + " " + String(ax2) + "," + String(ay2) + "\" fill=\"" + el.color + "\"/>");
        } elif el.type == "text" {
            parts.push("<text x=\"" + String(el.x) + "\" y=\"" + String(el.y + el.fontSize) + "\" font-size=\"" + String(el.fontSize) + "\" font-family=\"" + el.fontFamily + "\" fill=\"" + el.color + "\">" + el.text + "</text>");
        } elif el.type == "freehand" and el.points and el.points.length > 1 {
            d = "M " + String(el.points[0].x) + " " + String(el.points[0].y);
            pi = 1;
            while pi < el.points.length {
                d = d + " L " + String(el.points[pi].x) + " " + String(el.points[pi].y);
                pi = pi + 1;
            }
            parts.push("<path d=\"" + d + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" + dashAttr + "/>");
        } elif el.type == "image" and el.src {
            parts.push("<image x=\"" + String(el.x) + "\" y=\"" + String(el.y) + "\" width=\"" + String(el.width) + "\" height=\"" + String(el.height) + "\" href=\"" + el.src + "\"/>");
        }
        si = si + 1;
    }

    parts.push("</g>");
    parts.push("</svg>");
    return parts.join(newline);
}

def:pub copySelectionAsPNG(selectedElements: list, canvasRef: any, onDone: any) -> None {
    if selectedElements.length == 0 {
        return;
    }

    elements = extractElements(selectedElements);
    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, elements);
    dpr = window.devicePixelRatio or 1;
    offscreen = renderToOffscreenCanvas(elements, bounds, dpr);

    offscreen.toBlob(lambda blob: any -> None {
        item = Reflect.construct(ClipboardItem, [{"image/png": blob}]);
        navigator.clipboard.write([item]).then(lambda -> None {
            if onDone { onDone(); }
        });
    });
}

def:pub copyCanvasAsPNG(allElements: list, canvasRef: any, onDone: any) -> None {
    if allElements.length == 0 {
        return;
    }

    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, allElements);
    dpr = window.devicePixelRatio or 1;
    offscreen = renderToOffscreenCanvas(allElements, bounds, dpr);

    offscreen.toBlob(lambda blob: any -> None {
        item = Reflect.construct(ClipboardItem, [{"image/png": blob}]);
        navigator.clipboard.write([item]).then(lambda -> None {
            if onDone { onDone(); }
        });
    });
}

def:pub copyCanvasAsSVG(allElements: list, canvasRef: any, onDone: any) -> None {
    if allElements.length == 0 {
        return;
    }

    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, allElements);
    svgText = buildSvgString(allElements, bounds);

    svgBlob = Reflect.construct(Blob, [[svgText], {"type": "text/plain"}]);
    navigator.clipboard.write([Reflect.construct(ClipboardItem, [{"text/plain": svgBlob}])]).then(lambda -> None {
        if onDone { onDone(); }
    });
}

def:pub exportSelectionAsPNG(selectedElements: list, canvasRef: any) -> None {
    if selectedElements.length == 0 {
        return;
    }

    elements = extractElements(selectedElements);
    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, elements);
    dpr = window.devicePixelRatio or 1;
    offscreen = renderToOffscreenCanvas(elements, bounds, dpr);

    offscreen.toBlob(lambda blob: any -> None {
        url = URL.createObjectURL(blob);
        downloadBlob(url, "jasketch-export.png");
    });
}

def:pub exportSelectionAsSVG(selectedElements: list, canvasRef: any) -> None {
    if selectedElements.length == 0 {
        return;
    }

    elements = extractElements(selectedElements);
    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, elements);
    svgContent = buildSvgString(elements, bounds);

    blob = Reflect.construct(Blob, [[svgContent], {"type": "image/svg+xml"}]);
    url = URL.createObjectURL(blob);
    downloadBlob(url, "jasketch-export.svg");
}

def:pub exportSelectionAsPDF(selectedElements: list, canvasRef: any) -> None {
    if selectedElements.length == 0 {
        return;
    }

    elements = extractElements(selectedElements);
    srcCtx = canvasRef.current.getContext("2d");
    bounds = getSelectedElementsBounds(srcCtx, elements);
    offscreen = renderToOffscreenCanvas(elements, bounds, 2);

    dataUrl = offscreen.toDataURL("image/png");
    printWindow = window.open("", "_blank");
    if printWindow {
        printWindow.document.write("<html><head><title>JaSketch Export</title><style>body{margin:0;display:flex;justify-content:center;align-items:center;min-height:100vh}img{max-width:100%;height:auto}@media print{body{margin:0}img{max-width:100%}}</style></head><body>");
        printWindow.document.write("<img src=\"" + dataUrl + "\" />");
        printWindow.document.write("</body></html>");
        printWindow.document.close();
        printWindow.focus();
        printWindow.print();
    }
}
