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
        drawElement(ctx, elements[i], None);
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
        # Add text inside shapes if present (with word wrapping)
        if el.shapeText and (el.type == "rectangle" or el.type == "circle" or el.type == "diamond") {
            svgTCx = el.x + el.width / 2;
            svgTCy = el.y + el.height / 2;
            svgTFs = el.shapeTextFontSize or 16;
            svgTFf = el.shapeTextFontFamily or "Virgil";
            svgTFc = el.shapeTextColor or el.color;
            svgTMaxW = Math.abs(el.width) - 20;
            if svgTMaxW < 20 {
                svgTMaxW = 20;
            }
            # Approximate max chars per line (0.6 * fontSize per char)
            svgTCharW = svgTFs * 0.6;
            svgTMaxChars = Math.floor(svgTMaxW / svgTCharW);
            if svgTMaxChars < 1 {
                svgTMaxChars = 1;
            }
            # Word-wrap text
            svgTRawLines = el.shapeText.split(String.fromCharCode(10));
            svgTWrapped = [];
            svgTRi = 0;
            while svgTRi < svgTRawLines.length {
                svgTRawLine = svgTRawLines[svgTRi];
                if svgTRawLine == "" {
                    svgTWrapped.push("");
                    svgTRi = svgTRi + 1;
                    continue;
                }
                svgTWords = svgTRawLine.split(" ");
                svgTCurLine = "";
                svgTWi = 0;
                while svgTWi < svgTWords.length {
                    svgTTestLine = svgTCurLine;
                    if svgTCurLine == "" {
                        svgTTestLine = svgTWords[svgTWi];
                    } else {
                        svgTTestLine = svgTCurLine + " " + svgTWords[svgTWi];
                    }
                    if svgTTestLine.length > svgTMaxChars and svgTCurLine != "" {
                        svgTWrapped.push(svgTCurLine);
                        svgTCurLine = svgTWords[svgTWi];
                    } else {
                        svgTCurLine = svgTTestLine;
                    }
                    svgTWi = svgTWi + 1;
                }
                if svgTCurLine != "" {
                    svgTWrapped.push(svgTCurLine);
                }
                svgTRi = svgTRi + 1;
            }
            svgTLineH = svgTFs * 1.2;
            svgTTotalH = svgTWrapped.length * svgTLineH;
            svgTStartY = svgTCy - svgTTotalH / 2 + svgTLineH / 2;
            svgTLi = 0;
            while svgTLi < svgTWrapped.length {
                svgTLy = svgTStartY + svgTLi * svgTLineH;
                parts.push("<text x=\"" + String(svgTCx) + "\" y=\"" + String(svgTLy) + "\" font-size=\"" + String(svgTFs) + "\" font-family=\"" + svgTFf + "\" fill=\"" + svgTFc + "\" text-anchor=\"middle\" dominant-baseline=\"central\">" + svgTWrapped[svgTLi] + "</text>");
                svgTLi = svgTLi + 1;
            }
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

def:pub saveAsJaSketch(elements: list, filename: str) -> None {
    files = {};
    serialized = [];
    fileCounter = 0;

    # Build boundElements map: elementId -> [{id, type}] for all bound arrows/lines
    boundMap = {};
    bmi = 0;
    while bmi < elements.length {
        bmel = elements[bmi];
        if bmel.type == "line" or bmel.type == "arrow" {
            if bmel.startBinding {
                sbEId = bmel.startBinding.elementId;
                if sbEId {
                    if not boundMap[sbEId] {
                        boundMap[sbEId] = [];
                    }
                    boundMap[sbEId].push({"id": bmel.id, "type": bmel.type});
                }
            }
            if bmel.endBinding {
                ebEId = bmel.endBinding.elementId;
                if ebEId {
                    if not boundMap[ebEId] {
                        boundMap[ebEId] = [];
                    }
                    boundMap[ebEId].push({"id": bmel.id, "type": bmel.type});
                }
            }
        }
        bmi = bmi + 1;
    }

    i = 0;
    while i < elements.length {
        el = elements[i];

        if el.type == "line" or el.type == "arrow" {
            # Build relative points array: [[0,0], [intermediate...], [dx, dy]]
            slPts = [[0, 0]];
            slCurve = el.curveStyle or "curved";
            slBends = el.elbowBends or [];
            slBendX = el.bendX;
            slBendY = el.bendY;
            if slCurve == "elbow" and slBends.length > 0 {
                slBi = 0;
                while slBi < slBends.length {
                    slPts.push([slBends[slBi].x - el.x1, slBends[slBi].y - el.y1]);
                    slBi = slBi + 1;
                }
            } elif slBendX != None and slBendX != undefined {
                slPts.push([slBendX - el.x1, slBendY - el.y1]);
            }
            slPts.push([el.x2 - el.x1, el.y2 - el.y1]);
            serialized.push({
                "id": el.id,
                "type": el.type,
                "x": el.x1,
                "y": el.y1,
                "points": slPts,
                "color": el.color or "#000000",
                "strokeWidth": el.strokeWidth or 2,
                "lineStyle": el.lineStyle or "solid",
                "curveStyle": slCurve,
                "opacity": el.opacity or 1,
                "boundElements": None,
                "startBinding": el.startBinding and {"elementId": el.startBinding.elementId, "side": el.startBinding.side or "", "mode": "inside"} or None,
                "endBinding": el.endBinding and {"elementId": el.endBinding.elementId, "side": el.endBinding.side or "", "mode": "orbit"} or None
            });

        } elif el.type == "freehand" {
            # Convert [{x,y}] to [[x,y]] for consistency with line/arrow points
            fhPts = [];
            fhI = 0;
            while fhI < el.points.length {
                fhPts.push([el.points[fhI].x, el.points[fhI].y]);
                fhI = fhI + 1;
            }
            serialized.push({
                "id": el.id,
                "type": el.type,
                "points": fhPts,
                "color": el.color or "#000000",
                "strokeWidth": el.strokeWidth or 2,
                "lineStyle": el.lineStyle or "solid",
                "opacity": el.opacity or 1,
                "rotation": el.rotation or 0,
                "boundElements": boundMap[el.id] or None
            });

        } elif el.type == "text" {
            serialized.push({
                "id": el.id,
                "type": el.type,
                "x": el.x,
                "y": el.y,
                "text": el.text or "",
                "color": el.color or "#000000",
                "fontSize": el.fontSize or 24,
                "fontFamily": el.fontFamily or "Virgil",
                "opacity": el.opacity or 1,
                "rotation": el.rotation or 0,
                "boundElements": boundMap[el.id] or None
            });

        } elif el.type == "image" and el.src {
            existingId = None;
            existingKeys = Object.keys(files);
            ki = 0;
            while ki < existingKeys.length {
                if files[existingKeys[ki]].dataURL == el.src {
                    existingId = existingKeys[ki];
                }
                ki = ki + 1;
            }
            fileId = existingId;
            if not fileId {
                fileId = "img_" + String(Date.now()) + "_" + String(fileCounter);
                fileCounter = fileCounter + 1;
                mimeType = "image/png";
                if el.src.indexOf("data:image/jpeg") == 0 or el.src.indexOf("data:image/jpg") == 0 {
                    mimeType = "image/jpeg";
                } elif el.src.indexOf("data:image/svg") == 0 {
                    mimeType = "image/svg+xml";
                } elif el.src.indexOf("data:image/gif") == 0 {
                    mimeType = "image/gif";
                } elif el.src.indexOf("data:image/webp") == 0 {
                    mimeType = "image/webp";
                }
                files[fileId] = {
                    "id": fileId,
                    "mimeType": mimeType,
                    "dataURL": el.src,
                    "created": Date.now()
                };
            }
            serialized.push({
                "id": el.id,
                "type": el.type,
                "x": el.x,
                "y": el.y,
                "width": el.width,
                "height": el.height,
                "fileId": fileId,
                "opacity": el.opacity or 1,
                "rotation": el.rotation or 0,
                "boundElements": boundMap[el.id] or None
            });

        } else {
            # Shapes: rectangle, circle, diamond
            serialized.push({
                "id": el.id,
                "type": el.type,
                "x": el.x,
                "y": el.y,
                "width": el.width,
                "height": el.height,
                "color": el.color or "#000000",
                "fillColor": el.fillColor or "transparent",
                "strokeWidth": el.strokeWidth or 2,
                "lineStyle": el.lineStyle or "solid",
                "opacity": el.opacity or 1,
                "rotation": el.rotation or 0,
                "boundElements": boundMap[el.id] or None,
                "shapeText": el.shapeText or None,
                "shapeTextColor": el.shapeTextColor or None,
                "shapeTextFontSize": el.shapeTextFontSize or None,
                "shapeTextFontFamily": el.shapeTextFontFamily or None
            });
        }

        i = i + 1;
    }

    data = {
        "type": "jasketch",
        "version": 2,
        "source": "jasketch",
        "elements": serialized,
        "appState": {
            "viewBackgroundColor": "#ffffff"
        },
        "files": files
    };

    jsonStr = JSON.stringify(data, None, 2);
    blob = Reflect.construct(Blob, [[jsonStr], {"type": "application/json"}]);
    url = URL.createObjectURL(blob);
    downloadBlob(url, filename);
}

def:pub loadFromJaSketch(file: any, onLoad: any, onError: any) -> None {
    reader = Reflect.construct(FileReader, []);
    reader.onload = lambda e: any -> None {
        parsed = JSON.parse(e.target.result);
        if not parsed or parsed.type != "jasketch" or not parsed.elements {
            if onError { onError("Invalid .jasketch file"); }
            return;
        }
        files = parsed.files or {};
        restoredElements = [];
        i = 0;
        while i < parsed.elements.length {
            el = parsed.elements[i];

            if el.type == "image" and el.fileId {
                fileData = files[el.fileId];
                if fileData and fileData.dataURL {
                    restoredElements.push({
                        "id": el.id,
                        "type": el.type,
                        "x": el.x,
                        "y": el.y,
                        "width": el.width,
                        "height": el.height,
                        "src": fileData.dataURL,
                        "opacity": el.opacity or 1,
                        "rotation": el.rotation or 0
                    });
                }

            } elif (el.type == "line" or el.type == "arrow") and el.points {
                # v2 format: restore x1,y1,x2,y2 and bend data from points array
                lx1 = el.x;
                ly1 = el.y;
                lastPt = el.points[el.points.length - 1];
                lx2 = lx1 + lastPt[0];
                ly2 = ly1 + lastPt[1];
                lCurve = el.curveStyle or "curved";
                lBendX = None;
                lBendY = None;
                lElbowBends = None;
                if el.points.length > 2 {
                    if lCurve == "elbow" {
                        lElbowBends = [];
                        lpi = 1;
                        while lpi < el.points.length - 1 {
                            lElbowBends.push({"x": lx1 + el.points[lpi][0], "y": ly1 + el.points[lpi][1]});
                            lpi = lpi + 1;
                        }
                    } else {
                        midPt = el.points[1];
                        lBendX = lx1 + midPt[0];
                        lBendY = ly1 + midPt[1];
                    }
                }
                restoredElements.push({
                    "id": el.id,
                    "type": el.type,
                    "x1": lx1,
                    "y1": ly1,
                    "x2": lx2,
                    "y2": ly2,
                    "color": el.color or "#000000",
                    "strokeWidth": el.strokeWidth or 2,
                    "lineStyle": el.lineStyle or "solid",
                    "curveStyle": lCurve,
                    "opacity": el.opacity or 1,
                    "startBinding": el.startBinding or None,
                    "endBinding": el.endBinding or None,
                    "bendX": lBendX,
                    "bendY": lBendY,
                    "elbowBends": lElbowBends
                });

            } elif el.type == "freehand" and el.points {
                # Convert [[x,y]] (v2) back to [{x,y}]; pass [{x,y}] (v1) through
                fhPoints = [];
                fhIsV2 = el.points.length > 0 and Array.isArray(el.points[0]);
                fhI = 0;
                while fhI < el.points.length {
                    fhPt = el.points[fhI];
                    if fhIsV2 {
                        fhPoints.push({"x": fhPt[0], "y": fhPt[1]});
                    } else {
                        fhPoints.push({"x": fhPt.x, "y": fhPt.y});
                    }
                    fhI = fhI + 1;
                }
                restoredElements.push({
                    "id": el.id,
                    "type": el.type,
                    "points": fhPoints,
                    "color": el.color or "#000000",
                    "strokeWidth": el.strokeWidth or 2,
                    "lineStyle": el.lineStyle or "solid",
                    "opacity": el.opacity or 1,
                    "rotation": el.rotation or 0
                });

            } else {
                # Shapes (rectangle, circle, diamond), text, and v1 line/arrow (has x1 not points)
                restoredElements.push(el);
            }

            i = i + 1;
        }
        onLoad(restoredElements);
    };
    reader.onerror = lambda -> None {
        if onError { onError("Failed to read file"); }
    };
    reader.readAsText(file);
}
