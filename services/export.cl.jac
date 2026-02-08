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

    padding = 20;
    w = bounds.width + padding * 2;
    h = bounds.height + padding * 2;
    offsetX = padding - bounds.x;
    offsetY = padding - bounds.y;

    svgParts = [];
    svgParts.push("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + String(Math.ceil(w)) + "\" height=\"" + String(Math.ceil(h)) + "\" viewBox=\"0 0 " + String(Math.ceil(w)) + " " + String(Math.ceil(h)) + "\">");
    svgParts.push("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>");
    svgParts.push("<g transform=\"translate(" + String(offsetX) + "," + String(offsetY) + ")\">");

    i = 0;
    while i < elements.length {
        el = elements[i];
        if el.type == "rectangle" {
            svgParts.push("<rect x=\"" + String(el.x) + "\" y=\"" + String(el.y) + "\" width=\"" + String(el.width) + "\" height=\"" + String(el.height) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + (el.fillColor or "transparent") + "\" rx=\"8\"/>");
        } elif el.type == "circle" {
            cx = el.x + el.width / 2;
            cy = el.y + el.height / 2;
            rx = Math.abs(el.width) / 2;
            ry = Math.abs(el.height) / 2;
            svgParts.push("<ellipse cx=\"" + String(cx) + "\" cy=\"" + String(cy) + "\" rx=\"" + String(rx) + "\" ry=\"" + String(ry) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + (el.fillColor or "transparent") + "\"/>");
        } elif el.type == "line" {
            svgParts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"/>");
        } elif el.type == "arrow" {
            svgParts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"/>");
            headLen = 14;
            angle = Math.atan2(el.y2 - el.y1, el.x2 - el.x1);
            ax1 = el.x2 - headLen * Math.cos(angle - Math.PI / 6);
            ay1 = el.y2 - headLen * Math.sin(angle - Math.PI / 6);
            ax2 = el.x2 - headLen * Math.cos(angle + Math.PI / 6);
            ay2 = el.y2 - headLen * Math.sin(angle + Math.PI / 6);
            svgParts.push("<polygon points=\"" + String(el.x2) + "," + String(el.y2) + " " + String(ax1) + "," + String(ay1) + " " + String(ax2) + "," + String(ay2) + "\" fill=\"" + el.color + "\"/>");
        } elif el.type == "text" {
            svgParts.push("<text x=\"" + String(el.x) + "\" y=\"" + String(el.y + el.fontSize) + "\" font-size=\"" + String(el.fontSize) + "\" font-family=\"" + el.fontFamily + "\" fill=\"" + el.color + "\">" + el.text + "</text>");
        } elif el.type == "freehand" and el.points and el.points.length > 1 {
            d = "M " + String(el.points[0].x) + " " + String(el.points[0].y);
            pi = 1;
            while pi < el.points.length {
                d = d + " L " + String(el.points[pi].x) + " " + String(el.points[pi].y);
                pi = pi + 1;
            }
            svgParts.push("<path d=\"" + d + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>");
        } elif el.type == "image" and el.src {
            svgParts.push("<image x=\"" + String(el.x) + "\" y=\"" + String(el.y) + "\" width=\"" + String(el.width) + "\" height=\"" + String(el.height) + "\" href=\"" + el.src + "\"/>");
        }
        i = i + 1;
    }

    svgParts.push("</g>");
    svgParts.push("</svg>");
    svgContent = svgParts.join("\n");

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
