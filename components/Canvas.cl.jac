import from react { useRef }
import from "..hooks.useCanvas" { useCanvas }
import from "..hooks.useDrawingState" { useDrawingState }
import from "..hooks.useElements" { useElements }
import from "..hooks.useSelection" { useSelection }
import from "..hooks.useViewport" { useViewport }
import from "..hooks.useTextInput" { useTextInput }
import from "..hooks.useWebSocket" { useWebSocket }
import from "..services.geometry" { getMousePosition, findNearestConnectionPoint, find_bound_line_updates_for_shape, get_elbow_full_points, move_elbow_segment }
import from "..services.canvas" { drawPreview, getElementBounds, drawConnectionPoints, drawSnapIndicator }
import from "..services.collision" { getResizeHandleAtPoint, getBendHandleAtPoint, get_rotation_handle_at_point, getLineEndpointAtPoint, get_elbow_segment_at_point }
import from "..services.export" { exportSelectionAsPNG, exportSelectionAsSVG, copySelectionAsPNG, copyCanvasAsPNG, copyCanvasAsSVG, saveAsJaSketch, loadFromJaSketch }
import from "..constants.tools" { TOOL_SHORTCUTS }
import from .canvas.CanvasRenderer { CanvasRenderer }
import from .canvas.TextInput { TextInput }
import from .canvas.ContextMenu { ContextMenu }
import from .canvas.collaborator_cursors { CollaboratorCursors }
import from .layout.ShortcutHelp { ShortcutHelp }
import from .layout.ConfirmDialog { ConfirmDialog }

def:pub Canvas(
    clearCanvasRef: any,
    addElementRef: any,
    updateElementRef: any,
    saveRef: any,
    loadElementsRef: any,
    elementsForShareRef: any,
    setElementsRef: any,
    endSessionRef: any,
    updateUsernameRef: any,
    onParticipantsChange: Callable[[dict], None],
    onSessionEnded: Callable[[], None],
    onSelectionChange: Callable[[any], None],
    onToolChange: Callable[[str], None],
    onToggleShortcuts: Callable[[], None],
    showShortcuts: bool = False,
    roomState: dict = {},
    currentTool: str = "select",
    currentColor: str = "#000000",
    currentStrokeWidth: float = 2,
    currentFontSize: float = 24,
    currentFontFamily: str = "Virgil",
    currentOpacity: float = 1.0,
    currentLineStyle: str = "solid",
    currentCurveStyle: str = "curved",
    currentFillColor: str = "transparent"
) -> JsxElement {

    canvasHook = useCanvas();
    drawingState = useDrawingState();
    elementsHook = useElements();
    selectionHook = useSelection();
    viewportHook = useViewport();
    textInputHook = useTextInput();
    wsHook = useWebSocket(elementsHook, viewportHook, canvasHook.canvasRef, canvasHook, roomState, onSessionEnded);
    wsHookRef = useRef(wsHook);
    wsHookRef.current = wsHook;
    # Expose sendEndSession to parent via ref
    if endSessionRef and wsHook.sendEndSessionRef {
        endSessionRef.current = wsHook.sendEndSessionRef.current;
    }
    if updateUsernameRef and wsHook.sendUpdateUsernameRef {
        updateUsernameRef.current = wsHook.sendUpdateUsernameRef.current;
    }
    hasBroadcastMountedRef = useRef(False);
    lastCursorBroadcastRef = useRef(0);
    lastDrawBroadcastRef = useRef(0);

    canvasRef = canvasHook.canvasRef;
    containerRef = canvasHook.containerRef;
    textInputRef = useRef(None);
    has spacePressed: bool = False;
    has contextMenu: any = None;
    has toastMessage: any = None;
    clipboardRef = useRef([]);
    selectedElementRef = useRef(None);
    selectedElementsRef = useRef([]);
    altDragCopiedRef = useRef(False);
    drawingStateRef = useRef(drawingState);
    viewportHookRef = useRef(viewportHook);
    selectionHookRef = useRef(selectionHook);
    has isDraggingBend: bool = False;
    has isRotating: bool = False;
    has rotatingElementId: any = None;
    has rotatingCenter: dict = {"x": 0, "y": 0};
    has pendingStartBinding: any = None;
    has isDraggingVertex: bool = False;
    has draggingVertexHandle: str = "";
    has isDraggingElbowSegment: bool = False;
    has draggingElbowSegIndex: int = 0;
    has showResetConfirm: bool = False;

    selectedElementRef.current = selectionHook.selectedElement;
    selectedElementsRef.current = selectionHook.selectedElements;
    drawingStateRef.current = drawingState;
    viewportHookRef.current = viewportHook;
    selectionHookRef.current = selectionHook;

    # Pass editing shape id to suppress its shapeText during editing
    editingShapeId = None;
    if textInputHook.textInput {
        editingShapeId = textInputHook.textInput.editingShapeId;
    }

    can with [elementsHook.elements] entry {
        if not hasBroadcastMountedRef.current {
            hasBroadcastMountedRef.current = True;
        } elif wsHookRef.current and wsHookRef.current.isApplyingRemoteRef and wsHookRef.current.isApplyingRemoteRef.current {
            wsHookRef.current.isApplyingRemoteRef.current = False;
        } elif wsHookRef.current and wsHookRef.current.sendRoomBroadcastRef and wsHookRef.current.sendRoomBroadcastRef.current {
            wsHookRef.current.sendRoomBroadcastRef.current(elementsHook.elements);
        }
    }

    can with [wsHook.participants, wsHook.hostSessionId] entry {
        if onParticipantsChange {
            # Merge hostSessionId as __hostSid meta key so parent can read it
            merged = {**wsHook.participants};
            if wsHook.hostSessionId {
                merged["__hostSid"] = wsHook.hostSessionId;
            }
            onParticipantsChange(merged);
        }
        return lambda {};
    }

    can with [elementsHook.elements, canvasHook.canvasSize, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, drawingState.isDrawing, textInputHook.textInput] entry {
        canvas = canvasRef.current;
        if canvas {
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, editingShapeId);
        }
        if onSelectionChange {
            onSelectionChange(selectionHook.selectedElement);
        }
    }

    def triggerImageUpload() -> None {
        imgInput = document.createElement("input");
        imgInput.type = "file";
        imgInput.accept = "image/*";
        imgInput.onchange = lambda (evt: any) {
            imgFile = evt.target.files[0];
            if imgFile {
                imgReader = Reflect.construct(FileReader, []);
                imgReader.onload = lambda (loadEvt: any) {
                    imgObj = Reflect.construct(Image, []);
                    imgObj.onload = lambda {
                        canvas = canvasRef.current;
                        centerX = 0;
                        centerY = 0;
                        if canvas {
                            rect = canvas.getBoundingClientRect();
                            centerX = (rect.width / 2 - viewportHook.panOffset.x) / viewportHook.zoom;
                            centerY = (rect.height / 2 - viewportHook.panOffset.y) / viewportHook.zoom;
                        }
                        imgElement = {
                            "type": "image",
                            "x": centerX - imgObj.width / 2,
                            "y": centerY - imgObj.height / 2,
                            "width": imgObj.width,
                            "height": imgObj.height,
                            "src": loadEvt.target.result
                        };
                        elementsHook.addElement(imgElement);
                        selectionHook.setSelectedElement({"element": imgElement, "id": imgElement.id});
                        if onToolChange {
                            onToolChange("select");
                        }
                    };
                    imgObj.src = loadEvt.target.result;
                };
                imgReader.readAsDataURL(imgFile);
            }
        };
        imgInput.click();
    }

    def triggerJaSketchLoad() -> None {
        loadInput = document.createElement("input");
        loadInput.type = "file";
        loadInput.accept = ".jasketch";
        loadInput.onchange = lambda (evt: any) {
            loadFile = evt.target.files[0];
            if loadFile {
                loadFromJaSketch(loadFile, lambda (loaded: any) {
                    elementsHook.setElements(loaded);
                    selectionHook.clearSelection();
                    showToast("Diagram loaded");
                }, lambda (errMsg: any) {
                    showToast(errMsg);
                });
            }
        };
        loadInput.click();
    }

    can with (textInputHook.textInput, elementsHook.elements) entry {
        def handleKeyDown(e: KeyboardEvent) -> None {
            if e.key == " " and not textInputHook.textInput {
                e.preventDefault();
                spacePressed = True;
            }
            if not textInputHook.textInput and (e.key == "a" or e.key == "A") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                allElements = [];
                idx = 0;
                while idx < elementsHook.elements.length {
                    allElements.append({"element": elementsHook.elements[idx], "id": elementsHook.elements[idx].id});
                    idx = idx + 1;
                }
                selectionHook.setSelectedElements(allElements);
            }
            if not textInputHook.textInput and e.key == "Escape" {
                if drawingStateRef.current.isDrawing {
                    drawingStateRef.current.setIsDrawing(False);
                    drawingStateRef.current.setStartPoint(None);
                }
            }
            if not textInputHook.textInput and (e.key == "Delete" or e.key == "Backspace") {
                deleteSelected();
                e.preventDefault();
            }
            if not textInputHook.textInput and (e.key == "z" or e.key == "Z") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                if e.shiftKey {
                    elementsHook.redo();
                } else {
                    elementsHook.undo();
                }
                selectionHook.clearSelection();
            }
            if not textInputHook.textInput and (e.key == "y" or e.key == "Y") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                elementsHook.redo();
                selectionHook.clearSelection();
            }
            if not textInputHook.textInput and (e.key == "g" or e.key == "G") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                if e.shiftKey {
                    handleUngroup();
                } else {
                    handleGroup();
                }
            }
            if not textInputHook.textInput and (e.key == "c" or e.key == "C") and e.shiftKey and e.altKey {
                e.preventDefault();
                copyCanvasAsPNG(elementsHook.elements, canvasRef, lambda {
                    showToast("Copied as PNG");
                });
            } elif not textInputHook.textInput and (e.key == "c" or e.key == "C") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                curMulti = selectedElementsRef.current;
                curSingle = selectedElementRef.current;
                if curMulti and curMulti.length > 0 {
                    copied = [];
                    ci = 0;
                    while ci < curMulti.length {
                        copied.append({**curMulti[ci].element});
                        ci = ci + 1;
                    }
                    clipboardRef.current = copied;
                } elif curSingle and curSingle.element {
                    clipboardRef.current = [{**curSingle.element}];
                }
            }
            if not textInputHook.textInput and (e.key == "v" or e.key == "V") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                pasteFromSystemClipboard();
            }
            if not textInputHook.textInput and (e.key == "d" or e.key == "D") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                handleDuplicate();
            }
            if not textInputHook.textInput and e.key == "]" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                handleBringToFront();
            }
            if not textInputHook.textInput and e.key == "[" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                handleSendToBack();
            }
            if not textInputHook.textInput and (e.key == "=" or e.key == "+") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                canvas = canvasRef.current;
                if canvas {
                    rect = canvas.getBoundingClientRect();
                    viewportHookRef.current.handleZoom(-1, rect.left + rect.width / 2, rect.top + rect.height / 2, canvas);
                }
            }
            if not textInputHook.textInput and e.key == "-" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                canvas = canvasRef.current;
                if canvas {
                    rect = canvas.getBoundingClientRect();
                    viewportHookRef.current.handleZoom(1, rect.left + rect.width / 2, rect.top + rect.height / 2, canvas);
                }
            }
            if not textInputHook.textInput and e.key == "0" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                viewportHookRef.current.setZoom(1);
                viewportHookRef.current.setPanOffset({"x": 0, "y": 0});
            }
            if not textInputHook.textInput and (e.key == "s" or e.key == "S") and (e.ctrlKey or e.metaKey) and not e.shiftKey {
                e.preventDefault();
                saveAsJaSketch(elementsHook.elements, "drawing.jasketch");
            }
            if not textInputHook.textInput and (e.key == "o" or e.key == "O") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                triggerJaSketchLoad();
            }
            if not textInputHook.textInput and (e.key == "x" or e.key == "X") and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                curMultiCut = selectedElementsRef.current;
                curSingleCut = selectedElementRef.current;
                if curMultiCut and curMultiCut.length > 0 {
                    copied = [];
                    ci = 0;
                    while ci < curMultiCut.length {
                        copied.append({**curMultiCut[ci].element});
                        ci = ci + 1;
                    }
                    clipboardRef.current = copied;
                } elif curSingleCut and curSingleCut.element {
                    clipboardRef.current = [{**curSingleCut.element}];
                }
                deleteSelected();
            }
            if not textInputHook.textInput and e.key == "Delete" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                showResetConfirm = True;
            }
            if not textInputHook.textInput and (e.key == "<" or e.key == ",") and (e.ctrlKey or e.metaKey) and e.shiftKey {
                e.preventDefault();
                curSel = selectedElementRef.current;
                if curSel and curSel.element.type == "text" {
                    element = curSel.element;
                    newSize = element.fontSize or 16;
                    newSize = newSize - 2;
                    if newSize < 8 {
                        newSize = 8;
                    }
                    elementsHook.updateElement(element.id, {**element, "fontSize": newSize});
                    selectionHookRef.current.setSelectedElement({"element": {**element, "fontSize": newSize}, "id": element.id});
                }
            }
            if not textInputHook.textInput and (e.key == ">" or e.key == ".") and (e.ctrlKey or e.metaKey) and e.shiftKey {
                e.preventDefault();
                curSel = selectedElementRef.current;
                if curSel and curSel.element.type == "text" {
                    element = curSel.element;
                    newSize = element.fontSize or 16;
                    newSize = newSize + 2;
                    elementsHook.updateElement(element.id, {**element, "fontSize": newSize});
                    selectionHookRef.current.setSelectedElement({"element": {**element, "fontSize": newSize}, "id": element.id});
                }
            }
            if not textInputHook.textInput and e.key == "?" {
                e.preventDefault();
                if onToggleShortcuts {
                    onToggleShortcuts();
                }
            }
            if not textInputHook.textInput and not e.ctrlKey and not e.metaKey and not e.shiftKey and not e.altKey {
                if e.key == "9" {
                    triggerImageUpload();
                } else {
                    shortcuts = TOOL_SHORTCUTS();
                    toolForKey = shortcuts[e.key];
                    if toolForKey and onToolChange {
                        onToolChange(toolForKey);
                    }
                }
            }
        }

        def handleKeyUp(e: KeyboardEvent) -> None {
            if e.key == " " {
                spacePressed = False;
            }
        }

        window.addEventListener("keydown", handleKeyDown);
        window.addEventListener("keyup", handleKeyUp);
        return lambda {
            window.removeEventListener("keydown", handleKeyDown);
            window.removeEventListener("keyup", handleKeyUp);
        };
    }

    can with (viewportHook.zoom, viewportHook.panOffset) entry {
        canvas = canvasRef.current;
        if not canvas {
            return None;
        }

        def handleWheel(e: WheelEvent) -> None {
            e.preventDefault();
            if e.ctrlKey or e.metaKey {
                viewportHook.handleZoom(e.deltaY, e.clientX, e.clientY, canvas);
            } else {
                panX = -(e.deltaX or 0);
                panY = -(e.deltaY or 0);
                if e.shiftKey and panX == 0 {
                    panX = panY;
                    panY = 0;
                }
                viewportHook.handlePan(panX, panY);
            }
        }

        canvas.addEventListener("wheel", handleWheel, {"passive": False});
        return lambda {
            canvas.removeEventListener("wheel", handleWheel);
        };
    }

    can with elementsHook.elements entry {
        if clearCanvasRef {
            clearCanvasRef.current = lambda {
                elementsHook.clearElements();
                selectionHook.clearSelection();
            };
        }
        if addElementRef {
            addElementRef.current = lambda (element: any) {
                elementsHook.addElement(element);
            };
        }
        if updateElementRef {
            updateElementRef.current = lambda (id: any, changes: any) {
                fi = 0;
                foundEl = None;
                while fi < elementsHook.elements.length {
                    if elementsHook.elements[fi] and elementsHook.elements[fi].id == id {
                        foundEl = elementsHook.elements[fi];
                    }
                    fi = fi + 1;
                }
                if foundEl {
                    newElement = {**foundEl, **changes};
                    elementsHook.updateElement(id, newElement);
                    selectionHook.setSelectedElement({"element": newElement, "id": id});
                }
            };
        }
        if saveRef {
            saveRef.current = lambda {
                saveAsJaSketch(elementsHook.elements, "drawing.jasketch");
            };
        }
        if loadElementsRef {
            loadElementsRef.current = lambda (file: any) {
                loadFromJaSketch(file, lambda (loaded: any) {
                    elementsHook.setElements(loaded);
                    selectionHook.clearSelection();
                    showToast("Diagram loaded");
                }, lambda (errMsg: any) {
                    showToast(errMsg);
                });
            };
        }
        if elementsForShareRef {
            elementsForShareRef.current = elementsHook.elements;
        }
        if setElementsRef {
            setElementsRef.current = lambda (elements: any) {
                elementsHook.setElements(elements);
                selectionHook.clearSelection();
            };
        }
    }

    def handleCanvasClick(e: MouseEvent) -> None {
        if currentTool == "text" {
            if textInputHook.textInput {
                handleTextSubmit();
                if onToolChange {
                    onToolChange("select");
                }
                return;
            }
            pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

            elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);
            if elementInfo and elementInfo.element.type == "text" {
                element = elementInfo.element;
                textInputHook.startTextInput(element.x, element.y, element.text, None, None);
                elementsHook.removeElement(elementInfo.id);
                selectionHook.clearSelection();
                setTimeout(lambda {
                    if textInputRef.current {
                        textInputRef.current.focus();
                        textInputRef.current.select();
                    }
                }, 10);
            } else {
                textInputHook.startTextInput(pos.x, pos.y, "", None, None);
                setTimeout(lambda {
                    if textInputRef.current {
                        textInputRef.current.focus();
                    }
                }, 10);
            }
        }
    }

    def handleCanvasDoubleClick(e: MouseEvent) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
        elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);

        if elementInfo and elementInfo.element.type == "text" {
            element = elementInfo.element;
            textInputHook.startTextInput(element.x, element.y, element.text, None, None);
            elementsHook.removeElement(elementInfo.id);
            selectionHook.clearSelection();

            setTimeout(lambda {
                if textInputRef.current {
                    textInputRef.current.focus();
                    textInputRef.current.select();
                }
            }, 10);
        } elif elementInfo and (elementInfo.element.type == "rectangle" or elementInfo.element.type == "circle" or elementInfo.element.type == "diamond") {
            # Double-click on shape -> edit text inside it
            shapeEl = elementInfo.element;
            shapeCenterX = shapeEl.x + shapeEl.width / 2;
            shapeCenterY = shapeEl.y + shapeEl.height / 2;
            existingShapeText = shapeEl.shapeText or "";
            textInputHook.startTextInput(shapeCenterX, shapeCenterY, existingShapeText, elementInfo.id, shapeEl);
            selectionHook.clearSelection();
            setTimeout(lambda {
                if textInputRef.current {
                    textInputRef.current.focus();
                    if existingShapeText != "" {
                        textInputRef.current.select();
                    }
                }
            }, 10);
        } elif not elementInfo {
            # Double-click on empty canvas -> start text input
            selectionHook.clearSelection();
            textInputHook.startTextInput(pos.x, pos.y, "", None, None);
            setTimeout(lambda {
                if textInputRef.current {
                    textInputRef.current.focus();
                }
            }, 10);
        }
    }

    def handleTextSubmit() -> None {
        if not textInputHook.textInput {
            return;
        }
        shapeId = textInputHook.textInput.editingShapeId;
        if shapeId != None and shapeId != undefined {
            # Updating text inside a shape
            shapeElement = textInputHook.textInput.editingShapeElement;
            updatedShape = {**shapeElement};
            trimmedText = textInputHook.textInput.text;
            if trimmedText and trimmedText.trim() != "" {
                updatedShape.shapeText = trimmedText;
                updatedShape.shapeTextColor = currentColor;
                updatedShape.shapeTextFontSize = currentFontSize;
                updatedShape.shapeTextFontFamily = currentFontFamily;
            } else {
                # Empty text: remove text from shape
                updatedShape.shapeText = None;
                updatedShape.shapeTextColor = None;
                updatedShape.shapeTextFontSize = None;
                updatedShape.shapeTextFontFamily = None;
            }
            elementsHook.updateElement(shapeId, updatedShape);
            selectionHook.setSelectedElement({"element": updatedShape, "id": shapeId});
        } elif textInputHook.hasContent() {
            # Create standalone text element
            textEl = {
                "type": "text",
                "x": textInputHook.textInput.x,
                "y": textInputHook.textInput.y,
                "text": textInputHook.textInput.text,
                "color": currentColor,
                "fontSize": currentFontSize,
                "fontFamily": currentFontFamily,
                "opacity": currentOpacity
            };
            elementsHook.addElement(textEl);
            selectionHook.setSelectedElement({"element": textEl, "id": textEl.id});
        }
        textInputHook.cancelTextInput();
        if onToolChange {
            onToolChange("select");
        }
    }

    def handleTextKeyDown(e: KeyboardEvent) -> None {
        if e.key == "Escape" {
            handleTextSubmit();
        }
        # Enter adds newlines naturally (textarea default behavior)
        # Escape finishes editing
    }

    def deleteSelected() -> None {
        curMulti = selectedElementsRef.current;
        curSingle = selectedElementRef.current;
        if curMulti and curMulti.length > 0 {
            delIds = [];
            di = 0;
            while di < curMulti.length {
                delIds.append(curMulti[di].id);
                di = di + 1;
            }
            elementsHook.removeMultipleElements(delIds);
            selectionHook.clearSelection();
        } elif curSingle {
            elementsHook.removeElement(curSingle.id);
            selectionHook.clearSelection();
        }
    }

    def handleContextMenu(e: MouseEvent) -> None {
        e.preventDefault();
        hasSel = selectionHook.selectedElement or selectionHook.selectedElements.length > 0;
        # Determine if we can group (2+ elements selected)
        ctxCanGroup = False;
        ctxCanUngroup = False;
        if selectionHook.selectedElements.length > 1 {
            ctxCanGroup = True;
        }
        # Check if any selected element has a groupId
        ctxAllSelected = [];
        if selectionHook.selectedElements.length > 0 {
            ctxAllSelected = selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            ctxAllSelected = [selectionHook.selectedElement];
        }
        ctxi = 0;
        while ctxi < len(ctxAllSelected) {
            if ctxAllSelected[ctxi].element and ctxAllSelected[ctxi].element.groupId {
                ctxCanUngroup = True;
            }
            ctxi = ctxi + 1;
        }
        contextMenu = {
            "x": e.clientX,
            "y": e.clientY,
            "hasSelection": hasSel,
            "canGroup": ctxCanGroup,
            "canUngroup": ctxCanUngroup
        };
    }

    def handleDeleteFromMenu() -> None {
        deleteSelected();
        contextMenu = None;
    }

    def offsetElement(original: dict, dx: float, dy: float) -> dict {
        dup = {**original};
        dup.id = None;
        if original["type"] == "text" or original["type"] == "rectangle" or original["type"] == "circle" or original["type"] == "image" or original["type"] == "diamond" {
            dup.x = original["x"] + dx;
            dup.y = original["y"] + dy;
        } elif original["type"] == "line" or original["type"] == "arrow" {
            dup.x1 = original["x1"] + dx;
            dup.y1 = original["y1"] + dy;
            dup.x2 = original["x2"] + dx;
            dup.y2 = original["y2"] + dy;
            if original["bendX"] != None and original["bendX"] != undefined {
                dup.bendX = original["bendX"] + dx;
                dup.bendY = original["bendY"] + dy;
            }
        } elif original["type"] == "freehand" {
            newPoints: list = [];
            for p in original["points"] {
                newPoints.append({"x": p.x + dx, "y": p.y + dy});
            }
            dup.points = newPoints;
        }
        return dup;
    }

    def handleDuplicate() -> None {
        curMultiDup = selectedElementsRef.current;
        curSingleDup = selectedElementRef.current;
        if curMultiDup and curMultiDup.length > 0 {
            dups = [];
            ddi = 0;
            while ddi < curMultiDup.length {
                dups.append(offsetElement(curMultiDup[ddi].element, 20, 20));
                ddi = ddi + 1;
            }
            elementsHook.addMultipleElements(dups);
            dupSel = [];
            dsi = 0;
            while dsi < len(dups) {
                dupSel.append({"element": dups[dsi], "id": dups[dsi].id});
                dsi = dsi + 1;
            }
            selectionHook.setSelectedElements(dupSel);
            selectionHook.setSelectedElement(None);
        } elif curSingleDup and curSingleDup.element {
            singleDup = offsetElement(curSingleDup.element, 20, 20);
            elementsHook.addElement(singleDup);
        }
        contextMenu = None;
    }

    def handleBringToFront() -> None {
        if selectionHook.selectedElement {
            selId = selectionHook.selectedElement.id;
            element = selectionHook.selectedElement.element;
            elementsHook.removeElement(selId);
            elementsHook.addElement(element);
            selectionHook.clearSelection();
        }
        contextMenu = None;
    }

    def handleSendToBack() -> None {
        if selectionHook.selectedElement {
            selId = selectionHook.selectedElement.id;
            element = selectionHook.selectedElement.element;
            otherElements = [];
            bfi = 0;
            while bfi < elementsHook.elements.length {
                if elementsHook.elements[bfi].id != selId {
                    otherElements.append(elementsHook.elements[bfi]);
                }
                bfi = bfi + 1;
            }
            newElements = [element] + otherElements;
            elementsHook.setElements(newElements);
            selectionHook.clearSelection();
        }
        contextMenu = None;
    }

    def handleGroup() -> None {
        allSelected = [];
        if selectionHook.selectedElements.length > 1 {
            allSelected = selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            # Single selected, nothing to group
            contextMenu = None;
            return;
        }
        if len(allSelected) < 2 {
            contextMenu = None;
            return;
        }
        groupId = "g_" + str(Date.now()) + "_" + str(Math.floor(Math.random() * 10000));
        newElements = elementsHook.elements[:];
        gi = 0;
        while gi < len(allSelected) {
            selElId = allSelected[gi].id;
            # Find element in sliced array by id
            gfi = 0;
            while gfi < newElements.length {
                if newElements[gfi].id == selElId {
                    updated = {**newElements[gfi]};
                    updated.groupId = groupId;
                    newElements[gfi] = updated;
                }
                gfi = gfi + 1;
            }
            gi = gi + 1;
        }
        elementsHook.setElements(newElements);
        # Refresh selectedElements with updated elements
        newSel = [];
        gsi = 0;
        while gsi < len(allSelected) {
            selElId2 = allSelected[gsi].id;
            # Find updated element in newElements by id
            gsi2 = 0;
            while gsi2 < newElements.length {
                if newElements[gsi2].id == selElId2 {
                    newSel.append({"element": newElements[gsi2], "id": selElId2});
                }
                gsi2 = gsi2 + 1;
            }
            gsi = gsi + 1;
        }
        selectionHook.setSelectedElements(newSel);
        contextMenu = None;
    }

    def handleUngroup() -> None {
        allSelected = [];
        if selectionHook.selectedElements.length > 0 {
            allSelected = selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            allSelected = [selectionHook.selectedElement];
        }
        if len(allSelected) == 0 {
            contextMenu = None;
            return;
        }
        # Collect all groupIds from selected elements
        groupIdsToRemove = {};
        ugi = 0;
        while ugi < len(allSelected) {
            el = allSelected[ugi].element;
            if el.groupId {
                groupIdsToRemove[el.groupId] = True;
            }
            ugi = ugi + 1;
        }
        # Remove groupId from ALL elements that share those groupIds
        newElements = elementsHook.elements[:];
        rei = 0;
        while rei < newElements.length {
            if newElements[rei].groupId and groupIdsToRemove[newElements[rei].groupId] {
                updated = {**newElements[rei]};
                updated.groupId = None;
                newElements[rei] = updated;
            }
            rei = rei + 1;
        }
        elementsHook.setElements(newElements);
        # Refresh selection
        newSel = [];
        ursi = 0;
        while ursi < len(allSelected) {
            selElId3 = allSelected[ursi].id;
            # Find updated element in newElements by id
            urfi = 0;
            while urfi < newElements.length {
                if newElements[urfi].id == selElId3 {
                    newSel.append({"element": newElements[urfi], "id": selElId3});
                }
                urfi = urfi + 1;
            }
            ursi = ursi + 1;
        }
        if len(newSel) > 1 {
            selectionHook.setSelectedElements(newSel);
        } elif len(newSel) == 1 {
            selectionHook.setSelectedElement(newSel[0]);
            selectionHook.setSelectedElements([]);
        }
        contextMenu = None;
    }

    def handleClearCanvas() -> None {
        elementsHook.clearElements();
        selectionHook.clearSelection();
        contextMenu = None;
    }

    def getExportElements() -> list {
        if selectionHook.selectedElements.length > 0 {
            return selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            return [selectionHook.selectedElement];
        }
        return [];
    }

    def handleExportPNG() -> None {
        exportSelectionAsPNG(getExportElements(), canvasRef);
        contextMenu = None;
    }

    def handleExportSVG() -> None {
        exportSelectionAsSVG(getExportElements(), canvasRef);
        contextMenu = None;
    }

    def handleCopySelectionPNG() -> None {
        copySelectionAsPNG(getExportElements(), canvasRef, lambda {
            showToast("Copied as PNG");
        });
        contextMenu = None;
    }

    def pasteInternalClipboard() -> None {
        if clipboardRef.current.length > 0 {
            newElements = [];
            pi = 0;
            while pi < clipboardRef.current.length {
                newElements.append(offsetElement(clipboardRef.current[pi], 20, 20));
                pi = pi + 1;
            }
            elementsHook.addMultipleElements(newElements);
            pastedSelection = [];
            psi = 0;
            while psi < len(newElements) {
                pastedSelection.append({"element": newElements[psi], "id": newElements[psi].id});
                psi = psi + 1;
            }
            selectionHook.setSelectedElements(pastedSelection);
            if len(pastedSelection) == 1 {
                selectionHook.setSelectedElement(pastedSelection[0]);
            } else {
                selectionHook.setSelectedElement(None);
            }
        }
    }

    def pasteFromSystemClipboard() -> None {
        if clipboardRef.current.length > 0 {
            pasteInternalClipboard();
            return;
        }
        navigator.clipboard.read()
            .then(lambda (clipItems: any) {
                foundImage = False;
                foundText = False;
                ci = 0;
                while ci < clipItems.length {
                    clipItem = clipItems[ci];
                    clipTypes = clipItem.types;
                    ti = 0;
                    while ti < clipTypes.length {
                        if clipTypes[ti] == "image/png" or clipTypes[ti] == "image/jpeg" {
                            foundImage = True;
                            clipItem.getType(clipTypes[ti]).then(lambda (blob: any) {
                                reader = Reflect.construct(FileReader, []);
                                reader.onload = lambda (event: any) {
                                    img = Reflect.construct(Image, []);
                                    img.onload = lambda {
                                        pasteImgElement = {
                                            "type": "image",
                                            "x": 100,
                                            "y": 100,
                                            "width": img.width,
                                            "height": img.height,
                                            "src": event.target.result
                                        };
                                        elementsHook.addElement(pasteImgElement);
                                    };
                                    img.src = event.target.result;
                                };
                                reader.readAsDataURL(blob);
                            });
                            return;
                        }
                        ti = ti + 1;
                    }
                    ci = ci + 1;
                }
                if not foundImage {
                    ci = 0;
                    while ci < clipItems.length {
                        clipItem = clipItems[ci];
                        clipTypes = clipItem.types;
                        ti = 0;
                        while ti < clipTypes.length {
                            if clipTypes[ti] == "text/plain" {
                                foundText = True;
                                clipItem.getType("text/plain").then(lambda (blob: any) {
                                    blob.text().then(lambda (txt: str) {
                                        if txt.length > 0 {
                                            pasteTxtElement = {
                                                "type": "text",
                                                "x": 100,
                                                "y": 100,
                                                "text": txt,
                                                "fontSize": 20,
                                                "fontFamily": "sans-serif",
                                                "color": "#000000",
                                                "strokeWidth": 1
                                            };
                                            elementsHook.addElement(pasteTxtElement);
                                        }
                                    });
                                });
                                return;
                            }
                            ti = ti + 1;
                        }
                        ci = ci + 1;
                    }
                }
            })
            .catch(lambda (err: any) {
                console.log("System clipboard not available");
            });
    }

    def handlePasteFromMenu() -> None {
        contextMenu = None;
        pasteFromSystemClipboard();
    }

    def showToast(msg: str) -> None {
        toastMessage = msg;
        setTimeout(lambda { toastMessage = None; }, 2000);
    }

    def handleCopyCanvasAsPNG() -> None {
        copyCanvasAsPNG(elementsHook.elements, canvasRef, lambda {
            showToast("Copied as PNG");
        });
        contextMenu = None;
    }

    def handleCopyCanvasAsSVG() -> None {
        copyCanvasAsSVG(elementsHook.elements, canvasRef, lambda {
            showToast("Copied as SVG");
        });
        contextMenu = None;
    }

    def handleSelectAll() -> None {
        allElements = [];
        idx = 0;
        while idx < elementsHook.elements.length {
            allElements.append({"element": elementsHook.elements[idx], "id": elementsHook.elements[idx].id});
            idx = idx + 1;
        }
        selectionHook.setSelectedElements(allElements);
        contextMenu = None;
    }

    def handleMouseDown(e: MouseEvent) -> None {
        contextMenu = None;
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

            if selectionHook.selectedElement and selectionHook.selectedElement.element {
                selEl = selectionHook.selectedElement.element;
                # Check vertex handles (start/end) before bend handle
                vertexHandle = getLineEndpointAtPoint(pos, selEl);
                if vertexHandle {
                    isDraggingVertex = True;
                    draggingVertexHandle = vertexHandle;
                    selectionHook.setResizeStartElement({**selEl});
                    return;
                }
                if selEl.type == "line" or selEl.type == "arrow" {
                    selCurveStyle2 = selEl.curveStyle or "curved";
                    if selCurveStyle2 == "elbow" {
                        elbowSegIdx = get_elbow_segment_at_point(pos, selEl);
                        if elbowSegIdx >= 1 {
                            isDraggingElbowSegment = True;
                            draggingElbowSegIndex = elbowSegIdx;
                            selectionHook.setResizeStartElement({**selEl});
                            return;
                        }
                    } else {
                        if getBendHandleAtPoint(pos, selEl) {
                            isDraggingBend = True;
                            selectionHook.setDragStartPos(pos);
                            return;
                        }
                    }
                }

                canvas = canvasRef.current;
                if canvas {
                    ctx = canvas.getContext("2d");
                    bounds = getElementBounds(ctx, selEl);

                    # Check for rotation handle click
                    if get_rotation_handle_at_point(pos, bounds, selEl) {
                        isRotating = True;
                        rotatingElementId = selectionHook.selectedElement.id;
                        rotatingCenter = {"x": bounds.x + bounds.width / 2, "y": bounds.y + bounds.height / 2};
                        return;
                    }

                    handle = getResizeHandleAtPoint(pos, bounds);
                    if handle {
                        selectionHook.setIsResizing(True);
                        selectionHook.setResizeHandle(handle);
                        selectionHook.setResizeStartElement({**selEl});
                        selectionHook.setDragStartPos(pos);
                        return;
                    }
                }
            }

            elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);
            if elementInfo {
                altDragCopiedRef.current = False;

                if e.shiftKey {
                    # Shift+Click: toggle element in multi-selection
                    isAlreadySelected = False;
                    si = 0;
                    while si < selectionHook.selectedElements.length {
                        if selectionHook.selectedElements[si].id == elementInfo.id {
                            isAlreadySelected = True;
                        }
                        si = si + 1;
                    }

                    if isAlreadySelected {
                        selectionHook.removeFromSelection(elementInfo.id);
                    } else {
                        # Build the full list in one go to avoid stale state
                        newMulti = selectionHook.selectedElements[:];
                        # If there's a single selectedElement not yet in the list, include it
                        if selectionHook.selectedElement and newMulti.length == 0 {
                            newMulti.push(selectionHook.selectedElement);
                        }
                        newMulti.push(elementInfo);
                        selectionHook.setSelectedElements(newMulti);
                        selectionHook.setSelectedElement(None);
                    }
                } else {
                    # Normal click (no Shift)
                    isInMulti = False;
                    if selectionHook.selectedElements.length > 0 {
                        mi = 0;
                        while mi < selectionHook.selectedElements.length {
                            if selectionHook.selectedElements[mi].id == elementInfo.id {
                                isInMulti = True;
                            }
                            mi = mi + 1;
                        }
                    }

                    if isInMulti {
                        # Clicking on element already in multi-selection: start group drag
                        selectionHook.setIsDragging(True);
                        selectionHook.setDragStartPos(pos);
                    } elif elementInfo.element.groupId {
                        # Clicking on a grouped element: select all group members
                        clickedGroupId = elementInfo.element.groupId;
                        groupMembers = [];
                        gmi = 0;
                        while gmi < elementsHook.elements.length {
                            if elementsHook.elements[gmi].groupId == clickedGroupId {
                                groupMembers.append({"element": elementsHook.elements[gmi], "id": elementsHook.elements[gmi].id});
                            }
                            gmi = gmi + 1;
                        }
                        selectionHook.setSelectedElements(groupMembers);
                        selectionHook.setSelectedElement(None);
                        selectionHook.setIsDragging(True);
                        selectionHook.setDragStartPos(pos);
                    } else {
                        # Clicking on new element: single-select it
                        selectionHook.startDragging(elementInfo, pos);
                    }
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

        if currentTool == "line" or currentTool == "arrow" {
            if drawingState.isDrawing and drawingState.startPoint {
                endPos = pos;
                endBinding = None;
                endSnap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if endSnap {
                    endPos = endSnap.point;
                    endBinding = {"elementId": endSnap.elementId, "side": endSnap.side};
                }
                lineElement = {
                    "type": currentTool,
                    "x1": drawingState.startPoint.x,
                    "y1": drawingState.startPoint.y,
                    "x2": endPos.x,
                    "y2": endPos.y,
                    "color": currentColor,
                    "strokeWidth": currentStrokeWidth,
                    "lineStyle": currentLineStyle,
                    "curveStyle": currentCurveStyle,
                    "opacity": currentOpacity,
                    "startBinding": pendingStartBinding,
                    "endBinding": endBinding
                };
                pendingStartBinding = None;
                elementsHook.addElement(lineElement);
                drawingState.setIsDrawing(False);
                drawingState.setStartPoint(None);
                selectionHook.setSelectedElement({"element": lineElement, "id": lineElement.id});
                if onToolChange {
                    onToolChange("select");
                }
            } else {
                startSnap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if startSnap {
                    drawingState.setStartPoint(startSnap.point);
                    pendingStartBinding = {"elementId": startSnap.elementId, "side": startSnap.side};
                } else {
                    drawingState.setStartPoint(pos);
                    pendingStartBinding = None;
                }
                drawingState.setIsDrawing(True);
            }
            return;
        }

        drawingState.setIsDrawing(True);
        drawingState.setStartPoint(pos);

        if currentTool == "freehand" {
            drawingState.setCurrentPath([pos]);
        }
    }

    def handleMouseMove(e: MouseEvent) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

        # Throttled cursor broadcast (50ms) — only when in a room
        cur_now = Date.now();
        if cur_now - lastCursorBroadcastRef.current > 50 {
            lastCursorBroadcastRef.current = cur_now;
            cur_ws_hook = wsHookRef.current;
            if cur_ws_hook and cur_ws_hook.sendCursorBroadcastRef and cur_ws_hook.sendCursorBroadcastRef.current {
                cur_stored_name = localStorage.getItem("jasketch_username") or "Anonymous";
                cur_ws_hook.sendCursorBroadcastRef.current(pos.x, pos.y, cur_stored_name);
            }
        }

        if viewportHook.isPanning {
            viewportHook.handlePan(e.movementX, e.movementY);
            return;
        }

        if isDraggingBend and selectionHook.selectedElement {
            selId = selectionHook.selectedElement.id;
            updatedEl = {**selectionHook.selectedElement.element};
            updatedEl.bendX = pos.x;
            updatedEl.bendY = pos.y;
            elementsHook.updateElement(selId, updatedEl);
            return;
        }

        if isDraggingElbowSegment and selectionHook.selectedElement and selectionHook.resizeStartElement {
            selId = selectionHook.selectedElement.id;
            fullPts = get_elbow_full_points(selectionHook.resizeStartElement);
            newPts = move_elbow_segment(fullPts, draggingElbowSegIndex, pos);
            updatedEl = {**selectionHook.resizeStartElement};
            # Extract intermediate bends (exclude first and last = start/end endpoints)
            newBends = [];
            bi2 = 1;
            while bi2 < newPts.length - 1 {
                newBends.append({"x": newPts[bi2].x, "y": newPts[bi2].y});
                bi2 = bi2 + 1;
            }
            updatedEl.elbowBends = newBends;
            elementsHook.updateElementSilent(selId, updatedEl);
            selectionHook.setSelectedElement({"element": updatedEl, "id": selId});
            return;
        }

        if isDraggingVertex and selectionHook.selectedElement and selectionHook.resizeStartElement {
            selId = selectionHook.selectedElement.id;
            updatedEl = {**selectionHook.resizeStartElement};
            vertexPos = pos;
            # Snap to connection points
            vertexSnap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
            if vertexSnap {
                vertexPos = vertexSnap.point;
            }
            if draggingVertexHandle == "start" {
                updatedEl.x1 = vertexPos.x;
                updatedEl.y1 = vertexPos.y;
                if vertexSnap {
                    updatedEl.startBinding = {"elementId": vertexSnap.elementId, "side": vertexSnap.side};
                } else {
                    updatedEl.startBinding = None;
                }
            } else {
                updatedEl.x2 = vertexPos.x;
                updatedEl.y2 = vertexPos.y;
                if vertexSnap {
                    updatedEl.endBinding = {"elementId": vertexSnap.elementId, "side": vertexSnap.side};
                } else {
                    updatedEl.endBinding = None;
                }
            }
            elementsHook.updateElementSilent(selId, updatedEl);
            selectionHook.setSelectedElement({"element": updatedEl, "id": selId});
            return;
        }

        if isRotating and rotatingElementId and rotatingCenter {
            dx = pos.x - rotatingCenter["x"];
            dy = pos.y - rotatingCenter["y"];
            angle_rad = Math.atan2(dy, dx);
            # +90° offset so 0° = upright (handle points up), +360 to keep positive
            new_rotation = (angle_rad * 180 / 3.14159265359 + 90 + 360) % 360;
            # Shift key: snap to 15° increments
            if e.shiftKey {
                new_rotation = Math.round(new_rotation / 15) * 15;
            }
            if selectionHook.selectedElement {
                updatedEl = {**selectionHook.selectedElement.element};
                updatedEl.rotation = new_rotation;

                connLineUpdates = find_bound_line_updates_for_shape(updatedEl, elementsHook.elements);
                if connLineUpdates.length > 0 {
                    connLineUpdates.push({"id": rotatingElementId, "element": updatedEl});
                    elementsHook.updateMultipleElementsSilent(connLineUpdates);
                } else {
                    elementsHook.updateElementSilent(rotatingElementId, updatedEl);
                }

                selectionHook.setSelectedElement({"element": updatedEl, "id": rotatingElementId});
            }
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
            newElement = {**origEl};

            if origEl.type == "rectangle" or origEl.type == "circle" or origEl.type == "image" or origEl.type == "diamond" {
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
                    if origEl.bendX != None and origEl.bendX != undefined {
                        newElement.bendX = origEl.bendX + deltaX * 0.5;
                        newElement.bendY = origEl.bendY + deltaY * 0.5;
                    }
                } elif handle == "ne" or handle == "e" or handle == "se" {
                    newElement.x2 = origEl.x2 + deltaX;
                    newElement.y2 = origEl.y2 + deltaY;
                    if origEl.bendX != None and origEl.bendX != undefined {
                        newElement.bendX = origEl.bendX + deltaX * 0.5;
                        newElement.bendY = origEl.bendY + deltaY * 0.5;
                    }
                } elif handle == "n" {
                    newElement.y1 = origEl.y1 + deltaY;
                    newElement.y2 = origEl.y2 + deltaY;
                    if origEl.bendX != None and origEl.bendX != undefined {
                        newElement.bendY = origEl.bendY + deltaY;
                    }
                } elif handle == "s" {
                    newElement.y1 = origEl.y1 + deltaY;
                    newElement.y2 = origEl.y2 + deltaY;
                    if origEl.bendX != None and origEl.bendX != undefined {
                        newElement.bendY = origEl.bendY + deltaY;
                    }
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
                        scaledPoints: list = [];
                        for point in origEl.points {
                            scaledPoints.append({"x": minX + (point.x - minX) * scaleX, "y": minY + (point.y - minY) * scaleY});
                        }
                        newElement.points = scaledPoints;
                    }
                }
            }

            resizeConnUpdates = find_bound_line_updates_for_shape(newElement, elementsHook.elements);
            if resizeConnUpdates.length > 0 {
                resizeConnUpdates.push({"id": selectionHook.selectedElement.id, "element": newElement});
                elementsHook.updateMultipleElementsSilent(resizeConnUpdates);
            } else {
                elementsHook.updateElementSilent(selectionHook.selectedElement.id, newElement);
            }
            selectionHook.setSelectedElement({"element": newElement, "id": selectionHook.selectedElement.id});
            return;
        }

        if selectionHook.isDragging and currentTool == "select" {
            # Alt+Drag to duplicate: clone originals in place, then drag copies
            if e.altKey and not altDragCopiedRef.current {
                if selectionHook.selectedElements.length > 1 {
                    clones = [];
                    aci = 0;
                    while aci < selectionHook.selectedElements.length {
                        clone = {**selectionHook.selectedElements[aci].element};
                        clone.id = None;
                        clones.append(clone);
                        aci = aci + 1;
                    }
                    elementsHook.addMultipleElements(clones);
                    # Point selection to the new copies
                    newSel = [];
                    nsi = 0;
                    while nsi < len(clones) {
                        newSel.append({"element": clones[nsi], "id": clones[nsi].id});
                        nsi = nsi + 1;
                    }
                    selectionHook.setSelectedElements(newSel);
                    selectionHook.setDragStartPos(pos);
                    altDragCopiedRef.current = True;
                    return;
                } elif selectionHook.selectedElement {
                    singleClone = {**selectionHook.selectedElement.element};
                    singleClone.id = None;
                    elementsHook.addElement(singleClone);
                    selectionHook.setSelectedElement({"element": singleClone, "id": singleClone.id});
                    selectionHook.setSelectedElements([]);
                    altDragCopiedRef.current = True;
                    return;
                }
            }

            if selectionHook.selectedElements.length > 1 and selectionHook.dragStartPos {
                multiDx = pos.x - selectionHook.dragStartPos.x;
                multiDy = pos.y - selectionHook.dragStartPos.y;

                updates = [];
                i = 0;
                while i < selectionHook.selectedElements.length {
                    selectedInfo = selectionHook.selectedElements[i];
                    originalElement = selectedInfo.element;
                    newElement = {**originalElement};

                    if originalElement.type == "text" or originalElement.type == "rectangle" or originalElement.type == "circle" or originalElement.type == "image" or originalElement.type == "diamond" {
                        newElement.x = originalElement.x + multiDx;
                        newElement.y = originalElement.y + multiDy;
                    } elif originalElement.type == "line" or originalElement.type == "arrow" {
                        newElement.x1 = originalElement.x1 + multiDx;
                        newElement.y1 = originalElement.y1 + multiDy;
                        newElement.x2 = originalElement.x2 + multiDx;
                        newElement.y2 = originalElement.y2 + multiDy;
                        if originalElement.bendX != None and originalElement.bendX != undefined {
                            newElement.bendX = originalElement.bendX + multiDx;
                            newElement.bendY = originalElement.bendY + multiDy;
                        }
                        if originalElement.elbowBends and originalElement.elbowBends.length > 0 {
                            multiTransBends = [];
                            mebi = 0;
                            while mebi < originalElement.elbowBends.length {
                                multiTransBends.append({"x": originalElement.elbowBends[mebi].x + multiDx, "y": originalElement.elbowBends[mebi].y + multiDy});
                                mebi = mebi + 1;
                            }
                            newElement.elbowBends = multiTransBends;
                        }
                    } elif originalElement.type == "freehand" {
                        multiPoints: list = [];
                        for point in originalElement.points {
                            multiPoints.append({"x": point.x + multiDx, "y": point.y + multiDy});
                        }
                        newElement.points = multiPoints;
                    }

                    updates.append({"id": selectedInfo.id, "element": newElement});
                    i = i + 1;
                }
                # Find connected lines/arrows not in the selection and move them too
                selectedIdSet = {};
                msi = 0;
                while msi < selectionHook.selectedElements.length {
                    selectedIdSet[selectionHook.selectedElements[msi].id] = True;
                    msi = msi + 1;
                }
                mci = 0;
                while mci < selectionHook.selectedElements.length {
                    mcSelInfo = selectionHook.selectedElements[mci];
                    # Find the already-computed updated element for this id
                    mcUpdatedEl = mcSelInfo.element;
                    ui2 = 0;
                    while ui2 < len(updates) {
                        if updates[ui2].id == mcSelInfo.id {
                            mcUpdatedEl = updates[ui2].element;
                        }
                        ui2 = ui2 + 1;
                    }
                    mcLineUpdates = find_bound_line_updates_for_shape(mcUpdatedEl, elementsHook.elements);
                    mcli = 0;
                    while mcli < mcLineUpdates.length {
                        if not selectedIdSet[mcLineUpdates[mcli].id] {
                            updates.append(mcLineUpdates[mcli]);
                            selectedIdSet[mcLineUpdates[mcli].id] = True;
                        }
                        mcli = mcli + 1;
                    }
                    mci = mci + 1;
                }

                elementsHook.updateMultipleElementsSilent(updates);
                # Update selectedElements so selection boxes move with the elements
                newSelectedElements = [];
                ui = 0;
                while ui < selectionHook.selectedElements.length {
                    selElId4 = selectionHook.selectedElements[ui].id;
                    # Find the updated element for this selection id
                    ufi = 0;
                    foundUpdate = None;
                    while ufi < len(updates) {
                        if updates[ufi].id == selElId4 {
                            foundUpdate = updates[ufi];
                        }
                        ufi = ufi + 1;
                    }
                    if foundUpdate {
                        newSelectedElements.append({"element": foundUpdate.element, "id": foundUpdate.id});
                    }
                    ui = ui + 1;
                }
                selectionHook.setSelectedElements(newSelectedElements);
                # Update dragStartPos so delta is incremental, not cumulative
                selectionHook.setDragStartPos(pos);
                return;
            } elif selectionHook.selectedElement {
                element = selectionHook.selectedElement.element;
                newElement = {**element};

                if element.type == "text" or element.type == "rectangle" or element.type == "circle" or element.type == "image" or element.type == "diamond" {
                    newElement.x = pos.x - selectionHook.dragOffset.x;
                    newElement.y = pos.y - selectionHook.dragOffset.y;
                } elif element.type == "line" or element.type == "arrow" {
                    lineDx = pos.x - selectionHook.dragOffset.x - element.x1;
                    lineDy = pos.y - selectionHook.dragOffset.y - element.y1;
                    newElement.x1 = element.x1 + lineDx;
                    newElement.y1 = element.y1 + lineDy;
                    newElement.x2 = element.x2 + lineDx;
                    newElement.y2 = element.y2 + lineDy;
                    if element.bendX != None and element.bendX != undefined {
                        newElement.bendX = element.bendX + lineDx;
                        newElement.bendY = element.bendY + lineDy;
                    }
                    if element.elbowBends and element.elbowBends.length > 0 {
                        translatedBends = [];
                        ebi = 0;
                        while ebi < element.elbowBends.length {
                            translatedBends.append({"x": element.elbowBends[ebi].x + lineDx, "y": element.elbowBends[ebi].y + lineDy});
                            ebi = ebi + 1;
                        }
                        newElement.elbowBends = translatedBends;
                    }
                } elif element.type == "freehand" {
                    fhDx = pos.x - selectionHook.dragOffset.x - element.points[0].x;
                    fhDy = pos.y - selectionHook.dragOffset.y - element.points[0].y;
                    fhPoints: list = [];
                    for point in element.points {
                        fhPoints.append({"x": point.x + fhDx, "y": point.y + fhDy});
                    }
                    newElement.points = fhPoints;
                }

                # Move connected lines/arrows along with the shape
                hasXY = element.type == "rectangle" or element.type == "circle" or element.type == "diamond" or element.type == "text" or element.type == "image";
                if hasXY {
                    connLineUpdates = find_bound_line_updates_for_shape(newElement, elementsHook.elements);
                    if connLineUpdates.length > 0 {
                        connLineUpdates.push({"id": selectionHook.selectedElement.id, "element": newElement});
                        elementsHook.updateMultipleElementsSilent(connLineUpdates);
                    } else {
                        elementsHook.updateElementSilent(selectionHook.selectedElement.id, newElement);
                    }
                } else {
                    elementsHook.updateElementSilent(selectionHook.selectedElement.id, newElement);
                }
                selectionHook.setSelectedElement({"element": newElement, "id": selectionHook.selectedElement.id});
                return;
            }
        }

        if not drawingState.isDrawing {
            return;
        }

        if currentTool == "freehand" {
            newPath = drawingState.currentPath + [pos];
            drawingState.setCurrentPath(newPath);

            canvas = canvasRef.current;
            ctx = canvas.getContext("2d");

            # Redraw everything first (clears canvas)
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd);

            # Draw the in-progress freehand path on top
            ctx.save();
            ctx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
            ctx.scale(viewportHook.zoom, viewportHook.zoom);

            ctx.strokeStyle = currentColor;
            ctx.lineWidth = currentStrokeWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.setLineDash([]);
            ctx.beginPath();

            if newPath.length >= 2 {
                ctx.moveTo(newPath[0].x, newPath[0].y);
                fpi = 1;
                while fpi < newPath.length {
                    fpMidX = (newPath[fpi - 1].x + newPath[fpi].x) / 2;
                    fpMidY = (newPath[fpi - 1].y + newPath[fpi].y) / 2;
                    ctx.quadraticCurveTo(newPath[fpi - 1].x, newPath[fpi - 1].y, fpMidX, fpMidY);
                    fpi = fpi + 1;
                }
                ctx.stroke();
            } elif newPath.length == 1 {
                ctx.arc(newPath[0].x, newPath[0].y, currentStrokeWidth / 2, 0, Math.PI * 2);
                ctx.fill();
            }

            ctx.restore();
        } else {
            previewCanvas = canvasRef.current;
            previewCtx = previewCanvas.getContext("2d");
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd);

            previewCtx.save();
            previewCtx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
            previewCtx.scale(viewportHook.zoom, viewportHook.zoom);

            # For line/arrow, show connection points and snap endpoint (only while actively drawing)
            previewEnd = pos;
            if currentTool == "line" or currentTool == "arrow" {
                # Draw connection points on all shapes when line/arrow tool is active
                ei = 0;
                while ei < elementsHook.elements.length {
                    el = elementsHook.elements[ei];
                    if el.type == "rectangle" or el.type == "circle" or el.type == "text" or el.type == "diamond" {
                        drawConnectionPoints(previewCtx, el);
                    }
                    ei = ei + 1;
                }

                # Snap end point (only when actively drawing)
                if drawingState.isDrawing {
                    snap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                    if snap {
                        previewEnd = snap.point;
                        drawSnapIndicator(previewCtx, snap.point);
                    }
                }
            }

            drawPreview(previewCtx, currentTool, drawingState.startPoint, previewEnd, currentColor, currentStrokeWidth);
            previewCtx.restore();
        }

        # Throttled live drawing broadcast (80ms) — sends in-progress element as __draft__
        if drawingState.isDrawing {
            draw_now = Date.now();
            if draw_now - lastDrawBroadcastRef.current > 80 {
                lastDrawBroadcastRef.current = draw_now;
                preview_ws_hook = wsHookRef.current;
                if preview_ws_hook and preview_ws_hook.sendRoomPreviewRef and preview_ws_hook.sendRoomPreviewRef.current {
                    live_draft_el = None;
                    if currentTool == "freehand" and drawingState.currentPath and drawingState.currentPath.length > 0 {
                        live_draft_el = {"type": "freehand", "id": "__draft__", "points": drawingState.currentPath, "color": currentColor, "strokeWidth": currentStrokeWidth, "lineStyle": "solid", "opacity": currentOpacity};
                    } elif currentTool == "rectangle" and drawingState.startPoint {
                        ldraft_rw = pos.x - drawingState.startPoint.x;
                        ldraft_rh = pos.y - drawingState.startPoint.y;
                        live_draft_el = {"type": "rectangle", "id": "__draft__", "x": drawingState.startPoint.x, "y": drawingState.startPoint.y, "width": ldraft_rw, "height": ldraft_rh, "color": currentColor, "strokeWidth": currentStrokeWidth, "fillColor": currentFillColor, "lineStyle": currentLineStyle, "opacity": currentOpacity};
                    } elif currentTool == "circle" and drawingState.startPoint {
                        ldraft_cw = pos.x - drawingState.startPoint.x;
                        ldraft_ch = pos.y - drawingState.startPoint.y;
                        live_draft_el = {"type": "circle", "id": "__draft__", "x": drawingState.startPoint.x, "y": drawingState.startPoint.y, "width": ldraft_cw, "height": ldraft_ch, "color": currentColor, "strokeWidth": currentStrokeWidth, "fillColor": currentFillColor, "lineStyle": currentLineStyle, "opacity": currentOpacity};
                    } elif currentTool == "diamond" and drawingState.startPoint {
                        ldraft_dw = pos.x - drawingState.startPoint.x;
                        ldraft_dh = pos.y - drawingState.startPoint.y;
                        live_draft_el = {"type": "diamond", "id": "__draft__", "x": drawingState.startPoint.x, "y": drawingState.startPoint.y, "width": ldraft_dw, "height": ldraft_dh, "color": currentColor, "strokeWidth": currentStrokeWidth, "fillColor": currentFillColor, "lineStyle": currentLineStyle, "opacity": currentOpacity};
                    } elif (currentTool == "line" or currentTool == "arrow") and drawingState.startPoint {
                        live_draft_el = {"type": currentTool, "id": "__draft__", "x1": drawingState.startPoint.x, "y1": drawingState.startPoint.y, "x2": pos.x, "y2": pos.y, "color": currentColor, "strokeWidth": currentStrokeWidth, "lineStyle": currentLineStyle, "curveStyle": currentCurveStyle, "opacity": currentOpacity};
                    }
                    if live_draft_el {
                        preview_ws_hook.sendRoomPreviewRef.current(elementsHook.elements + [live_draft_el]);
                    }
                }
            }
        }
    }

    def handleMouseUp(e: MouseEvent) -> None {
        if isRotating {
            elementsHook.commitToHistory();
            isRotating = False;
            rotatingElementId = None;
            rotatingCenter = {"x": 0, "y": 0};
            return;
        }

        if isDraggingElbowSegment {
            elementsHook.commitToHistory();
            isDraggingElbowSegment = False;
            draggingElbowSegIndex = 0;
            return;
        }

        if isDraggingVertex {
            elementsHook.commitToHistory();
            isDraggingVertex = False;
            draggingVertexHandle = "";
            return;
        }

        if isDraggingBend {
            elementsHook.commitToHistory();
            isDraggingBend = False;
            if selectionHook.selectedElement {
                bendId = selectionHook.selectedElement.id;
                updatedBendEl = selectionHook.selectedElement.element;
                selectionHook.setSelectedElement({"element": updatedBendEl, "id": bendId});
            }
            return;
        }

        if selectionHook.isResizing {
            elementsHook.commitToHistory();
            selectionHook.stopResizing();
            return;
        }

        if selectionHook.isBoxSelecting and currentTool == "select" {
            selectionHook.finishBoxSelection(elementsHook.elements);
            return;
        }

        if selectionHook.isDragging {
            elementsHook.commitToHistory();
        }
        selectionHook.stopDragging();
        viewportHook.stopPanning();

        if not drawingState.isDrawing {
            return;
        }

        if currentTool == "line" or currentTool == "arrow" {
            # If user dragged far enough from start, finalize as drag-to-draw
            if drawingState.startPoint {
                dragEndPos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
                dragDist = Math.sqrt(Math.pow(dragEndPos.x - drawingState.startPoint.x, 2) + Math.pow(dragEndPos.y - drawingState.startPoint.y, 2));
                if dragDist > 5 {
                    dragEndBinding = None;
                    dragEndSnap = findNearestConnectionPoint(dragEndPos, elementsHook.elements, 20.0);
                    if dragEndSnap {
                        dragEndPos = dragEndSnap.point;
                        dragEndBinding = {"elementId": dragEndSnap.elementId, "side": dragEndSnap.side};
                    }
                    dragLineEl = {
                        "type": currentTool,
                        "x1": drawingState.startPoint.x,
                        "y1": drawingState.startPoint.y,
                        "x2": dragEndPos.x,
                        "y2": dragEndPos.y,
                        "color": currentColor,
                        "strokeWidth": currentStrokeWidth,
                        "lineStyle": currentLineStyle,
                        "curveStyle": currentCurveStyle,
                        "opacity": currentOpacity,
                        "startBinding": pendingStartBinding,
                        "endBinding": dragEndBinding
                    };
                    pendingStartBinding = None;
                    elementsHook.addElement(dragLineEl);
                    drawingState.setIsDrawing(False);
                    drawingState.setStartPoint(None);
                    selectionHook.setSelectedElement({"element": dragLineEl, "id": dragLineEl.id});
                    if onToolChange {
                        onToolChange("select");
                    }
                }
            }
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
                    "strokeWidth": currentStrokeWidth,
                    "lineStyle": "solid",
                    "opacity": currentOpacity
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
                "fillColor": currentFillColor,
                "lineStyle": currentLineStyle,
                "opacity": currentOpacity
            };
        } elif currentTool == "diamond" {
            dw = pos.x - drawingState.startPoint.x;
            dh = pos.y - drawingState.startPoint.y;
            newElement = {
                "type": "diamond",
                "x": drawingState.startPoint.x,
                "y": drawingState.startPoint.y,
                "width": dw,
                "height": dh,
                "color": currentColor,
                "strokeWidth": currentStrokeWidth,
                "fillColor": currentFillColor,
                "lineStyle": currentLineStyle,
                "opacity": currentOpacity
            };
        } elif currentTool == "circle" {
            cw = pos.x - drawingState.startPoint.x;
            ch = pos.y - drawingState.startPoint.y;
            newElement = {
                "type": "circle",
                "x": drawingState.startPoint.x,
                "y": drawingState.startPoint.y,
                "width": cw,
                "height": ch,
                "color": currentColor,
                "strokeWidth": currentStrokeWidth,
                "fillColor": currentFillColor,
                "lineStyle": currentLineStyle,
                "opacity": currentOpacity
            };
        }

        if newElement {
            elementsHook.addElement(newElement);
            if currentTool != "freehand" {
                selectionHook.setSelectedElement({"element": newElement, "id": newElement.id});
            }
            if onToolChange and currentTool != "freehand" {
                onToolChange("select");
            }
        }
    }

    def handleMouseLeave() -> None {
        if not (currentTool == "line" or currentTool == "arrow") {
            drawingState.setIsDrawing(False);
        }
        selectionHook.stopDragging();
        selectionHook.stopResizing();
        viewportHook.stopPanning();
        isDraggingBend = False;
        isDraggingVertex = False;
        draggingVertexHandle = "";
        isDraggingElbowSegment = False;
        draggingElbowSegIndex = 0;
        isRotating = False;
    }

    cursorClass = "cursor-crosshair";
    if spacePressed or viewportHook.isPanning {
        cursorClass = "cursor-grab";
    } elif currentTool == "text" {
        cursorClass = "cursor-text";
    } elif currentTool == "select" {
        if isRotating {
            cursorClass = "cursor-grabbing";
        } elif selectionHook.isResizing {
            cursorClass = "cursor-grabbing";
        } elif selectionHook.isDragging {
            cursorClass = "cursor-grabbing";
        } else {
            cursorClass = "cursor-default";
        }
    }

    return (
        <div ref={containerRef} className="relative w-full h-full flex items-center justify-center overflow-hidden bg-gray-50/50 canvas-dotgrid" onContextMenu={handleContextMenu}>
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

            <CollaboratorCursors
                cursor_states={wsHook.cursorStates or {}}
                zoom={viewportHook.zoom}
                pan_x={viewportHook.panOffset.x}
                pan_y={viewportHook.panOffset.y}
            />

            <TextInput
                textInput={textInputHook.textInput}
                textInputRef={textInputRef}
                currentColor={currentColor}
                currentFontSize={currentFontSize}
                currentFontFamily={currentFontFamily}
                zoom={viewportHook.zoom}
                panOffset={viewportHook.panOffset}
                onTextChange={lambda (e: any) {
                    textInputHook.updateTextContent(e.target.value);
                }}
                onKeyDown={handleTextKeyDown}
                onBlur={handleTextSubmit}
            />

            <ContextMenu
                visible={contextMenu != None}
                x={contextMenu and contextMenu.x or 0}
                y={contextMenu and contextMenu.y or 0}
                hasSelection={contextMenu and contextMenu.hasSelection or False}
                canGroup={contextMenu and contextMenu.canGroup or False}
                canUngroup={contextMenu and contextMenu.canUngroup or False}
                onClose={lambda { contextMenu = None; }}
                onDelete={handleDeleteFromMenu}
                onDuplicate={handleDuplicate}
                onBringToFront={handleBringToFront}
                onSendToBack={handleSendToBack}
                onGroup={handleGroup}
                onUngroup={handleUngroup}
                onClearCanvas={handleClearCanvas}
                onExportPNG={handleExportPNG}
                onExportSVG={handleExportSVG}
                onCopySelectionPNG={handleCopySelectionPNG}
                onPaste={handlePasteFromMenu}
                onCopyCanvasPNG={handleCopyCanvasAsPNG}
                onCopyCanvasSVG={handleCopyCanvasAsSVG}
                onSelectAll={handleSelectAll}
            />

            <div className="absolute bottom-4 left-4 flex items-center bg-white/90 backdrop-blur-xl border border-gray-200/80 rounded-xl shadow-lg z-40 select-none">
                <button
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-l-xl text-base font-medium transition-colors"
                    onClick={lambda {
                        zoomCanvas = canvasRef.current;
                        if zoomCanvas {
                            zoomRect = zoomCanvas.getBoundingClientRect();
                            viewportHook.handleZoom(1, zoomRect.left + zoomRect.width / 2, zoomRect.top + zoomRect.height / 2, zoomCanvas);
                        }
                    }}
                >-</button>
                <button
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 text-sm font-medium min-w-[56px] text-center transition-colors"
                    onClick={lambda {
                        viewportHook.setZoom(1);
                        viewportHook.setPanOffset({"x": 0, "y": 0});
                    }}
                >{str(Math.round(viewportHook.zoom * 100)) + "%"}</button>
                <button
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-r-xl text-base font-medium transition-colors"
                    onClick={lambda {
                        ziCanvas = canvasRef.current;
                        if ziCanvas {
                            ziRect = ziCanvas.getBoundingClientRect();
                            viewportHook.handleZoom(-1, ziRect.left + ziRect.width / 2, ziRect.top + ziRect.height / 2, ziCanvas);
                        }
                    }}
                >+</button>
            </div>

            {toastMessage and <div className="fixed bottom-6 left-1/2 -translate-x-1/2 bg-gray-800 text-white px-4 py-2 rounded-lg shadow-lg text-sm z-50 pointer-events-none animate-fade-in">
                {toastMessage}
            </div> or None}

            {(showShortcuts or False) and <ShortcutHelp onClose={lambda { if onToggleShortcuts { onToggleShortcuts(); } }} /> or None}

            {showResetConfirm and <ConfirmDialog
                title="Reset Canvas"
                message="Reset the canvas? This will clear all elements."
                onConfirm={lambda {
                    elementsHook.clearElements();
                    selectionHook.clearSelection();
                    showResetConfirm = False;
                }}
                onCancel={lambda { showResetConfirm = False; }}
                confirmText="Reset"
                cancelText="Cancel"
                isDangerous={True}
            /> or None}
        </div>
    );
}
