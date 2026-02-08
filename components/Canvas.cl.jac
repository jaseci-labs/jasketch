import from react { useRef, useEffect, useState }
import from "..hooks.useCanvas" { useCanvas }
import from "..hooks.useDrawingState" { useDrawingState }
import from "..hooks.useElements" { useElements }
import from "..hooks.useSelection" { useSelection }
import from "..hooks.useViewport" { useViewport }
import from "..hooks.useTextInput" { useTextInput }
import from "..services.geometry" { getMousePosition, findNearestConnectionPoint }
import from "..services.canvas" { drawPreview, getElementBounds, drawConnectionPoints, drawSnapIndicator }
import from "..services.collision" { getResizeHandleAtPoint }
import from .canvas.CanvasRenderer { CanvasRenderer }
import from .canvas.TextInput { TextInput }

def:pub Canvas(props: dict) -> any {
    currentTool = props.currentTool or "freehand";
    currentColor = props.currentColor or "#000000";
    currentStrokeWidth = props.currentStrokeWidth or 2;
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Virgil";

    canvasHook = useCanvas();
    drawingState = useDrawingState();
    elementsHook = useElements();
    selectionHook = useSelection();
    viewportHook = useViewport();
    textInputHook = useTextInput();

    canvasRef = canvasHook.canvasRef;
    containerRef = canvasHook.containerRef;
    textInputRef = useRef(None);
    [spacePressed, setSpacePressed] = useState(False);

    can with [elementsHook.elements, canvasHook.canvasSize, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd] entry {
        canvas = canvasRef.current;
        if canvas {
            canvas.width = canvasHook.canvasSize.width;
            canvas.height = canvasHook.canvasSize.height;
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd);
        }
    }

    useEffect(lambda -> any {
        def handleKeyDown(e: dict) -> None {
            if e.key == " " and not textInputHook.textInput {
                e.preventDefault();
                setSpacePressed(True);
            }
            if not textInputHook.textInput and (e.key == "a" or e.key == "A") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                allElements = [];
                idx = 0;
                while idx < elementsHook.elements.length {
                    allElements.push({"element": elementsHook.elements[idx], "index": idx});
                    idx = idx + 1;
                }
                selectionHook.setSelectedElements(allElements);
            }
            if not textInputHook.textInput and (e.key == "Delete" or e.key == "Backspace") {
                if selectionHook.selectedElements.length > 0 {
                    indices = [];
                    i = 0;
                    while i < selectionHook.selectedElements.length {
                        indices.push(selectionHook.selectedElements[i].index);
                        i = i + 1;
                    }
                    elementsHook.removeMultipleElements(indices);
                    selectionHook.clearSelection();
                    e.preventDefault();
                } elif selectionHook.selectedElement {
                    elementsHook.removeElement(selectionHook.selectedElement.index);
                    selectionHook.clearSelection();
                    e.preventDefault();
                }
            }
        }

        def handleKeyUp(e: dict) -> None {
            if e.key == " " {
                setSpacePressed(False);
            }
        }

        window.addEventListener("keydown", handleKeyDown);
        window.addEventListener("keyup", handleKeyUp);
        return lambda -> None {
            window.removeEventListener("keydown", handleKeyDown);
            window.removeEventListener("keyup", handleKeyUp);
        };
    }, [selectionHook.selectedElement, selectionHook.selectedElements, textInputHook.textInput, elementsHook.elements]);

    useEffect(lambda -> any {
        canvas = canvasRef.current;
        if not canvas {
            return None;
        }

        def handleWheel(e: dict) -> None {
            e.preventDefault();
            viewportHook.handleZoom(e.deltaY, e.clientX, e.clientY, canvas);
        }

        canvas.addEventListener("wheel", handleWheel, {"passive": False});
        return lambda -> None {
            canvas.removeEventListener("wheel", handleWheel);
        };
    }, [viewportHook.zoom, viewportHook.panOffset]);

    def handleCanvasClick(e: dict) -> None {
        if currentTool == "text" {
            pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
            textInputHook.startTextInput(pos.x, pos.y);
            setTimeout(lambda -> None {
                if textInputRef.current {
                    textInputRef.current.focus();
                }
            }, 10);
        }
    }

    def handleCanvasDoubleClick(e: dict) -> None {
        if currentTool == "select" {
            pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
            elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);

            if elementInfo and elementInfo.element.type == "text" {
                element = elementInfo.element;
                textInputHook.startTextInput(element.x, element.y, element.text);
                elementsHook.removeElement(elementInfo.index);
                selectionHook.clearSelection();

                setTimeout(lambda -> None {
                    if textInputRef.current {
                        textInputRef.current.focus();
                        textInputRef.current.select();
                    }
                }, 10);
            }
        }
    }

    def handleTextSubmit() -> None {
        if textInputHook.textInput and textInputHook.hasContent() {
            newElement = {
                "type": "text",
                "x": textInputHook.textInput.x,
                "y": textInputHook.textInput.y,
                "text": textInputHook.textInput.text,
                "color": currentColor,
                "fontSize": currentFontSize,
                "fontFamily": currentFontFamily
            };
            elementsHook.addElement(newElement);
        }
        textInputHook.cancelTextInput();
    }

    def handleTextKeyDown(e: dict) -> None {
        if e.key == "Escape" {
            textInputHook.cancelTextInput();
        } elif e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            handleTextSubmit();
        }
    }

    def handleMouseDown(e: dict) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

        if spacePressed or e.button == 1 {
            viewportHook.startPanning();
            e.preventDefault();
            return;
        }

        if currentTool == "select" {
            if e.button == 2 or e.metaKey or e.ctrlKey {
                viewportHook.startPanning();
                e.preventDefault();
                return;
            }

            # Check if clicking on a resize handle of selected element
            if selectionHook.selectedElement and selectionHook.selectedElement.element {
                canvas = canvasRef.current;
                if canvas {
                    ctx = canvas.getContext("2d");
                    bounds = getElementBounds(ctx, selectionHook.selectedElement.element);
                    handle = getResizeHandleAtPoint(pos, bounds);
                    if handle {
                        selectionHook.setIsResizing(True);
                        selectionHook.setResizeHandle(handle);
                        selectionHook.setResizeStartElement(Object.assign({}, selectionHook.selectedElement.element));
                        selectionHook.setDragStartPos(pos);
                        return;
                    }
                }
            }

            elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);
            if elementInfo {
                isInSelection = False;
                if selectionHook.selectedElements.length > 0 {
                    i = 0;
                    while i < selectionHook.selectedElements.length {
                        if selectionHook.selectedElements[i].index == elementInfo.index {
                            isInSelection = True;
                        }
                        i = i + 1;
                    }
                }

                if isInSelection {
                    selectionHook.setIsDragging(True);
                    selectionHook.setDragStartPos(pos);
                } else {
                    selectionHook.startDragging(elementInfo, pos);
                }
            } else {
                selectionHook.clearSelection();
                selectionHook.startBoxSelection(pos);
            }
            return;
        }

        if currentTool == "text" {
            return;
        }

        drawingState.setIsDrawing(True);

        # Snap start point to connection point for line/arrow tools
        if currentTool == "line" or currentTool == "arrow" {
            snap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
            if snap {
                drawingState.setStartPoint(snap.point);
            } else {
                drawingState.setStartPoint(pos);
            }
        } else {
            drawingState.setStartPoint(pos);
        }

        if currentTool == "freehand" {
            drawingState.setCurrentPath([pos]);
        }
    }

    def handleMouseMove(e: dict) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

        if viewportHook.isPanning {
            viewportHook.handlePan(e.movementX, e.movementY);
            return;
        }

        if selectionHook.isBoxSelecting and currentTool == "select" {
            selectionHook.updateBoxSelection(pos);
            return;
        }

        if selectionHook.isResizing and currentTool == "select" and selectionHook.resizeStartElement and selectionHook.dragStartPos {
            origEl = selectionHook.resizeStartElement;
            handle = selectionHook.resizeHandle;
            deltaX = pos.x - selectionHook.dragStartPos.x;
            deltaY = pos.y - selectionHook.dragStartPos.y;
            newElement = Object.assign({}, origEl);

            if origEl.type == "rectangle" or origEl.type == "circle" {
                if handle == "se" {
                    newElement.width = origEl.width + deltaX;
                    newElement.height = origEl.height + deltaY;
                } elif handle == "sw" {
                    newElement.x = origEl.x + deltaX;
                    newElement.width = origEl.width - deltaX;
                    newElement.height = origEl.height + deltaY;
                } elif handle == "ne" {
                    newElement.y = origEl.y + deltaY;
                    newElement.width = origEl.width + deltaX;
                    newElement.height = origEl.height - deltaY;
                } elif handle == "nw" {
                    newElement.x = origEl.x + deltaX;
                    newElement.y = origEl.y + deltaY;
                    newElement.width = origEl.width - deltaX;
                    newElement.height = origEl.height - deltaY;
                } elif handle == "n" {
                    newElement.y = origEl.y + deltaY;
                    newElement.height = origEl.height - deltaY;
                } elif handle == "s" {
                    newElement.height = origEl.height + deltaY;
                } elif handle == "e" {
                    newElement.width = origEl.width + deltaX;
                } elif handle == "w" {
                    newElement.x = origEl.x + deltaX;
                    newElement.width = origEl.width - deltaX;
                }
            } elif origEl.type == "line" or origEl.type == "arrow" {
                if handle == "nw" or handle == "w" or handle == "sw" {
                    newElement.x1 = origEl.x1 + deltaX;
                    newElement.y1 = origEl.y1 + deltaY;
                } elif handle == "ne" or handle == "e" or handle == "se" {
                    newElement.x2 = origEl.x2 + deltaX;
                    newElement.y2 = origEl.y2 + deltaY;
                } elif handle == "n" {
                    newElement.y1 = origEl.y1 + deltaY;
                    newElement.y2 = origEl.y2 + deltaY;
                } elif handle == "s" {
                    newElement.y1 = origEl.y1 + deltaY;
                    newElement.y2 = origEl.y2 + deltaY;
                }
            } elif origEl.type == "text" {
                # Scale font size proportionally
                if handle == "se" or handle == "s" or handle == "sw" or handle == "ne" or handle == "n" or handle == "nw" {
                    scaleFactor = 1 + deltaY / 100;
                    if scaleFactor < 0.3 {
                        scaleFactor = 0.3;
                    }
                    if scaleFactor > 5 {
                        scaleFactor = 5;
                    }
                    newElement.fontSize = Math.round(origEl.fontSize * scaleFactor);
                    if newElement.fontSize < 8 {
                        newElement.fontSize = 8;
                    }
                    if newElement.fontSize > 200 {
                        newElement.fontSize = 200;
                    }
                }
            } elif origEl.type == "freehand" {
                # Scale all points relative to bounding box
                if origEl.points.length > 0 {
                    minX = origEl.points[0].x;
                    minY = origEl.points[0].y;
                    maxX = origEl.points[0].x;
                    maxY = origEl.points[0].y;
                    pi = 0;
                    while pi < origEl.points.length {
                        if origEl.points[pi].x < minX { minX = origEl.points[pi].x; }
                        if origEl.points[pi].x > maxX { maxX = origEl.points[pi].x; }
                        if origEl.points[pi].y < minY { minY = origEl.points[pi].y; }
                        if origEl.points[pi].y > maxY { maxY = origEl.points[pi].y; }
                        pi = pi + 1;
                    }
                    bw = maxX - minX;
                    bh = maxY - minY;
                    if bw > 0 and bh > 0 {
                        scaleX = (bw + deltaX) / bw;
                        scaleY = (bh + deltaY) / bh;
                        if scaleX < 0.1 { scaleX = 0.1; }
                        if scaleY < 0.1 { scaleY = 0.1; }
                        newElement.points = origEl.points.map(lambda point: dict -> dict {
                            return {
                                "x": minX + (point.x - minX) * scaleX,
                                "y": minY + (point.y - minY) * scaleY
                            };
                        });
                    }
                }
            }

            elementsHook.updateElement(selectionHook.selectedElement.index, newElement);
            return;
        }

        if selectionHook.isDragging and currentTool == "select" {
            if selectionHook.selectedElements.length > 1 and selectionHook.dragStartPos {
                deltaX = pos.x - selectionHook.dragStartPos.x;
                deltaY = pos.y - selectionHook.dragStartPos.y;

                updates = [];
                i = 0;
                while i < selectionHook.selectedElements.length {
                    selectedInfo = selectionHook.selectedElements[i];
                    originalElement = selectedInfo.element;
                    newElement = Object.assign({}, originalElement);

                    if originalElement.type == "text" or originalElement.type == "rectangle" or originalElement.type == "circle" {
                        newElement.x = originalElement.x + deltaX;
                        newElement.y = originalElement.y + deltaY;
                    } elif originalElement.type == "line" or originalElement.type == "arrow" {
                        newElement.x1 = originalElement.x1 + deltaX;
                        newElement.y1 = originalElement.y1 + deltaY;
                        newElement.x2 = originalElement.x2 + deltaX;
                        newElement.y2 = originalElement.y2 + deltaY;
                    } elif originalElement.type == "freehand" {
                        newElement.points = originalElement.points.map(lambda point: dict -> dict {
                            return {"x": point.x + deltaX, "y": point.y + deltaY};
                        });
                    }

                    updates.push({"index": selectedInfo.index, "element": newElement});
                    i = i + 1;
                }
                elementsHook.updateMultipleElements(updates);
                return;
            } elif selectionHook.selectedElement {
                element = selectionHook.selectedElement.element;
                newElement = Object.assign({}, element);

                if element.type == "text" or element.type == "rectangle" or element.type == "circle" {
                    newElement.x = pos.x - selectionHook.dragOffset.x;
                    newElement.y = pos.y - selectionHook.dragOffset.y;
                } elif element.type == "line" or element.type == "arrow" {
                    deltaX = pos.x - selectionHook.dragOffset.x - element.x1;
                    deltaY = pos.y - selectionHook.dragOffset.y - element.y1;
                    newElement.x1 = element.x1 + deltaX;
                    newElement.y1 = element.y1 + deltaY;
                    newElement.x2 = element.x2 + deltaX;
                    newElement.y2 = element.y2 + deltaY;
                } elif element.type == "freehand" {
                    deltaX = pos.x - selectionHook.dragOffset.x - element.points[0].x;
                    deltaY = pos.y - selectionHook.dragOffset.y - element.points[0].y;
                    newElement.points = element.points.map(lambda point: dict -> dict {
                        return {"x": point.x + deltaX, "y": point.y + deltaY};
                    });
                }

                elementsHook.updateElement(selectionHook.selectedElement.index, newElement);
                return;
            }
        }

        if not drawingState.isDrawing {
            return;
        }

        if currentTool == "freehand" {
            newPath = drawingState.currentPath.concat([pos]);
            drawingState.setCurrentPath(newPath);

            canvas = canvasRef.current;
            ctx = canvas.getContext("2d");

            ctx.save();
            ctx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
            ctx.scale(viewportHook.zoom, viewportHook.zoom);

            ctx.strokeStyle = currentColor;
            ctx.lineWidth = currentStrokeWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();

            pathLen = drawingState.currentPath.length;
            if pathLen >= 2 {
                prev = drawingState.currentPath[pathLen - 2];
                last = drawingState.currentPath[pathLen - 1];
                midX = (last.x + pos.x) / 2;
                midY = (last.y + pos.y) / 2;
                ctx.moveTo(last.x, last.y);
                ctx.quadraticCurveTo(last.x, last.y, midX, midY);
                ctx.stroke();
            } elif pathLen == 1 {
                ctx.moveTo(drawingState.currentPath[0].x, drawingState.currentPath[0].y);
                ctx.lineTo(pos.x, pos.y);
                ctx.stroke();
            }

            ctx.restore();
        } else {
            canvas = canvasRef.current;
            ctx = canvas.getContext("2d");
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd);

            ctx.save();
            ctx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
            ctx.scale(viewportHook.zoom, viewportHook.zoom);

            # For line/arrow, show connection points and snap endpoint
            previewEnd = pos;
            if currentTool == "line" or currentTool == "arrow" {
                # Draw connection points on all shapes
                ei = 0;
                while ei < elementsHook.elements.length {
                    el = elementsHook.elements[ei];
                    if el.type == "rectangle" or el.type == "circle" or el.type == "text" {
                        drawConnectionPoints(ctx, el);
                    }
                    ei = ei + 1;
                }

                # Snap end point
                snap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if snap {
                    previewEnd = snap.point;
                    drawSnapIndicator(ctx, snap.point);
                }
            }

            drawPreview(ctx, currentTool, drawingState.startPoint, previewEnd, currentColor, currentStrokeWidth);
            ctx.restore();
        }
    }

    def handleMouseUp(e: dict) -> None {
        if selectionHook.isResizing {
            selectionHook.stopResizing();
            return;
        }

        if selectionHook.isBoxSelecting and currentTool == "select" {
            selectionHook.finishBoxSelection(elementsHook.elements);
            return;
        }

        selectionHook.stopDragging();
        viewportHook.stopPanning();

        if not drawingState.isDrawing {
            return;
        }

        drawingState.setIsDrawing(False);
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

        newElement = None;

        if currentTool == "freehand" {
            if drawingState.currentPath.length > 0 {
                newElement = {
                    "type": "freehand",
                    "points": drawingState.currentPath,
                    "color": currentColor,
                    "strokeWidth": currentStrokeWidth
                };
            }
            drawingState.setCurrentPath([]);
        } elif currentTool == "rectangle" {
            w = pos.x - drawingState.startPoint.x;
            h = pos.y - drawingState.startPoint.y;
            newElement = {
                "type": "rectangle",
                "x": drawingState.startPoint.x,
                "y": drawingState.startPoint.y,
                "width": w,
                "height": h,
                "color": currentColor,
                "strokeWidth": currentStrokeWidth,
                "fillColor": "transparent"
            };
        } elif currentTool == "circle" {
            w = pos.x - drawingState.startPoint.x;
            h = pos.y - drawingState.startPoint.y;
            newElement = {
                "type": "circle",
                "x": drawingState.startPoint.x,
                "y": drawingState.startPoint.y,
                "width": w,
                "height": h,
                "color": currentColor,
                "strokeWidth": currentStrokeWidth,
                "fillColor": "transparent"
            };
        } elif currentTool == "line" or currentTool == "arrow" {
            # Snap endpoint to connection point
            endPos = pos;
            snap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
            if snap {
                endPos = snap.point;
            }
            newElement = {
                "type": currentTool,
                "x1": drawingState.startPoint.x,
                "y1": drawingState.startPoint.y,
                "x2": endPos.x,
                "y2": endPos.y,
                "color": currentColor,
                "strokeWidth": currentStrokeWidth
            };
        }

        if newElement {
            elementsHook.addElement(newElement);
        }
    }

    def handleMouseLeave() -> None {
        drawingState.setIsDrawing(False);
        selectionHook.stopDragging();
        selectionHook.stopResizing();
        viewportHook.stopPanning();
    }

    cursorClass = "cursor-crosshair";
    if spacePressed or viewportHook.isPanning {
        cursorClass = "cursor-grab";
    } elif currentTool == "text" {
        cursorClass = "cursor-text";
    } elif currentTool == "select" {
        if selectionHook.isResizing {
            cursorClass = "cursor-grabbing";
        } elif selectionHook.isDragging {
            cursorClass = "cursor-grabbing";
        } else {
            cursorClass = "cursor-default";
        }
    }

    return (
        <div ref={containerRef} className="relative w-full h-full flex items-center justify-center overflow-hidden bg-white">
            <CanvasRenderer
                canvasRef={canvasRef}
                canvasSize={canvasHook.canvasSize}
                cursorClass={cursorClass}
                onClick={handleCanvasClick}
                onDoubleClick={handleCanvasDoubleClick}
                onMouseDown={handleMouseDown}
                onMouseMove={handleMouseMove}
                onMouseUp={handleMouseUp}
                onMouseLeave={handleMouseLeave}
            />

            <TextInput
                textInput={textInputHook.textInput}
                textInputRef={textInputRef}
                currentColor={currentColor}
                currentFontSize={currentFontSize}
                currentFontFamily={currentFontFamily}
                onTextChange={lambda e: any -> None {
                    textInputHook.updateTextContent(e.target.value);
                }}
                onKeyDown={handleTextKeyDown}
                onBlur={handleTextSubmit}
            />
        </div>
    );
}
