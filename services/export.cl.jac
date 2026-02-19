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

    padding = 20;
    svgW = bounds.width + padding * 2;
    svgH = bounds.height + padding * 2;
    svgOffX = padding - bounds.x;
    svgOffY = padding - bounds.y;

    parts = [];
    parts.push("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + String(Math.ceil(svgW)) + "\" height=\"" + String(Math.ceil(svgH)) + "\" viewBox=\"0 0 " + String(Math.ceil(svgW)) + " " + String(Math.ceil(svgH)) + "\">");
    parts.push("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>");
    parts.push("<g transform=\"translate(" + String(svgOffX) + "," + String(svgOffY) + ")\">");

    si = 0;
    while si < allElements.length {
        el = allElements[si];
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
            top = String(dCx) + "," + String(el.y);
            right = String(el.x + el.width) + "," + String(dCy);
            bottom = String(dCx) + "," + String(el.y + el.height);
            leftPt = String(el.x) + "," + String(dCy);
            parts.push("<polygon points=\"" + top + " " + right + " " + bottom + " " + leftPt + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "circle" {
            eCx = el.x + el.width / 2;
            eCy = el.y + el.height / 2;
            eRx = Math.abs(el.width) / 2;
            eRy = Math.abs(el.height) / 2;
            parts.push("<ellipse cx=\"" + String(eCx) + "\" cy=\"" + String(eCy) + "\" rx=\"" + String(eRx) + "\" ry=\"" + String(eRy) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "line" {
            if el.bendX != None and el.bendX != undefined {
                csvgD = "M " + String(el.x1) + " " + String(el.y1) + " Q " + String(el.bendX) + " " + String(el.bendY) + " " + String(el.x2) + " " + String(el.y2);
                parts.push("<path d=\"" + csvgD + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\"" + dashAttr + "/>");
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
            cHeadLen = 14;
            cArrAngle = 0;
            if el.bendX != None and el.bendX != undefined {
                cArrAngle = Math.atan2(el.y2 - el.bendY, el.x2 - el.bendX);
            } else {
                cArrAngle = Math.atan2(el.y2 - el.y1, el.x2 - el.x1);
            }
            cAx1 = el.x2 - cHeadLen * Math.cos(cArrAngle - Math.PI / 6);
            cAy1 = el.y2 - cHeadLen * Math.sin(cArrAngle - Math.PI / 6);
            cAx2 = el.x2 - cHeadLen * Math.cos(cArrAngle + Math.PI / 6);
            cAy2 = el.y2 - cHeadLen * Math.sin(cArrAngle + Math.PI / 6);
            parts.push("<polygon points=\"" + String(el.x2) + "," + String(el.y2) + " " + String(cAx1) + "," + String(cAy1) + " " + String(cAx2) + "," + String(cAy2) + "\" fill=\"" + el.color + "\"/>");
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
    svgText = parts.join(String.fromCharCode(10));

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
        # Build stroke-dasharray attribute from lineStyle
        dashAttr = "";
        if el.lineStyle == "dashed" {
            dashAttr = " stroke-dasharray=\"12,6\"";
        } elif el.lineStyle == "dotted" {
            dashAttr = " stroke-dasharray=\"3,6\"";
        }

        fillVal = el.fillColor or "transparent";

        if el.type == "rectangle" {
            svgParts.push("<rect x=\"" + String(el.x) + "\" y=\"" + String(el.y) + "\" width=\"" + String(el.width) + "\" height=\"" + String(el.height) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\" rx=\"8\"" + dashAttr + "/>");
        } elif el.type == "diamond" {
            dCx = el.x + el.width / 2;
            dCy = el.y + el.height / 2;
            top = String(dCx) + "," + String(el.y);
            right = String(el.x + el.width) + "," + String(dCy);
            bottom = String(dCx) + "," + String(el.y + el.height);
            left = String(el.x) + "," + String(dCy);
            svgParts.push("<polygon points=\"" + top + " " + right + " " + bottom + " " + left + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "circle" {
            eCx = el.x + el.width / 2;
            eCy = el.y + el.height / 2;
            eRx = Math.abs(el.width) / 2;
            eRy = Math.abs(el.height) / 2;
            svgParts.push("<ellipse cx=\"" + String(eCx) + "\" cy=\"" + String(eCy) + "\" rx=\"" + String(eRx) + "\" ry=\"" + String(eRy) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"" + fillVal + "\"" + dashAttr + "/>");
        } elif el.type == "line" {
            if el.bendX != None and el.bendX != undefined {
                esvgD = "M " + String(el.x1) + " " + String(el.y1) + " Q " + String(el.bendX) + " " + String(el.bendY) + " " + String(el.x2) + " " + String(el.y2);
                svgParts.push("<path d=\"" + esvgD + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\"" + dashAttr + "/>");
            } else {
                svgParts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"" + dashAttr + "/>");
            }
        } elif el.type == "arrow" {
            if el.bendX != None and el.bendX != undefined {
                easvgD = "M " + String(el.x1) + " " + String(el.y1) + " Q " + String(el.bendX) + " " + String(el.bendY) + " " + String(el.x2) + " " + String(el.y2);
                svgParts.push("<path d=\"" + easvgD + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\"" + dashAttr + "/>");
            } else {
                svgParts.push("<line x1=\"" + String(el.x1) + "\" y1=\"" + String(el.y1) + "\" x2=\"" + String(el.x2) + "\" y2=\"" + String(el.y2) + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" stroke-linecap=\"round\"" + dashAttr + "/>");
            }
            eHeadLen = 14;
            eArrAngle = 0;
            if el.bendX != None and el.bendX != undefined {
                eArrAngle = Math.atan2(el.y2 - el.bendY, el.x2 - el.bendX);
            } else {
                eArrAngle = Math.atan2(el.y2 - el.y1, el.x2 - el.x1);
            }
            eAx1 = el.x2 - eHeadLen * Math.cos(eArrAngle - Math.PI / 6);
            eAy1 = el.y2 - eHeadLen * Math.sin(eArrAngle - Math.PI / 6);
            eAx2 = el.x2 - eHeadLen * Math.cos(eArrAngle + Math.PI / 6);
            eAy2 = el.y2 - eHeadLen * Math.sin(eArrAngle + Math.PI / 6);
            svgParts.push("<polygon points=\"" + String(el.x2) + "," + String(el.y2) + " " + String(eAx1) + "," + String(eAy1) + " " + String(eAx2) + "," + String(eAy2) + "\" fill=\"" + el.color + "\"/>");
        } elif el.type == "text" {
            svgParts.push("<text x=\"" + String(el.x) + "\" y=\"" + String(el.y + el.fontSize) + "\" font-size=\"" + String(el.fontSize) + "\" font-family=\"" + el.fontFamily + "\" fill=\"" + el.color + "\">" + el.text + "</text>");
        } elif el.type == "freehand" and el.points and el.points.length > 1 {
            d = "M " + String(el.points[0].x) + " " + String(el.points[0].y);
            pi = 1;
            while pi < el.points.length {
                d = d + " L " + String(el.points[pi].x) + " " + String(el.points[pi].y);
                pi = pi + 1;
            }
            svgParts.push("<path d=\"" + d + "\" stroke=\"" + el.color + "\" stroke-width=\"" + String(el.strokeWidth) + "\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" + dashAttr + "/>");
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
