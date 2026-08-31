import from react { useRef }
import from "..hooks.useCanvas" { useCanvas }
import from "..hooks.useDrawingState" { useDrawingState }
import from "..hooks.useElements" { useElements }
import from "..hooks.useSelection" { useSelection }
import from "..hooks.useViewport" { useViewport }
import from "..hooks.useTextInput" { useTextInput }
import from "..hooks.useWebSocket" { useWebSocket }
import from "..services.geometry" { normalize_box, constrain_drag_point, shift_element, getMousePosition, findNearestConnectionPoint, find_bound_line_updates_for_shape, get_elbow_full_points, move_elbow_segment }
import from "..services.snapping" { element_bounds, union_bounds, compute_snap, draw_snap_guides, snap_threshold_for }
import from "..services.canvas" { draw_hover_outline, shape_text_min_height, drawPreview, getElementBounds, drawConnectionPoints, drawSnapIndicator }
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
    onSelectionChange: Callable[[any, any], None],
    onToolChange: Callable[[str], None],
    onToggleShortcuts: Callable[[], None],
    onToolLockChange: Callable[[bool], None],
    showShortcuts: bool = False,
    toolLocked: bool = False,
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
    # The keydown listener is registered once, so it would capture the value of
    # toolLocked from the first render forever.
    # Guides are pure feedback for the gesture in flight, so they live in a ref
    # rather than state: they must not cause a re-render of their own.
    snapGuidesRef = useRef([]);
    # Which element the pointer is over.
    #
    # This is state rather than a ref on purpose. It began as a ref that
    # repainted the canvas itself, which meant TWO independent things were
    # drawing the same surface -- the redraw effect and the hover handler -- and
    # whichever ran last won. Right after a drag that produced a frame painted
    # from the pre-drag selection, leaving a second selection box behind at the
    # old position. One painter only.
    #
    # It changes when the pointer crosses a shape boundary, not on every mouse
    # move, so the re-render is rare.
    has hoveredId: any = None;

    toolLockedRef = useRef(toolLocked);
    toolLockedRef.current = toolLocked;

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

    can with [elementsHook.elements, canvasHook.canvasSize, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, drawingState.isDrawing, textInputHook.textInput, hoveredId] entry {
        canvas = canvasRef.current;
        if canvas {
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, editingShapeId);
            # Hover outline, on top of the finished frame.
            if hoveredId {
                hovered = None;
                hvi = 0;
                while hvi < elementsHook.elements.length {
                    if elementsHook.elements[hvi] and elementsHook.elements[hvi].id == hoveredId {
                        hovered = elementsHook.elements[hvi];
                    }
                    hvi = hvi + 1;
                }
                if hovered {
                    hoverCtx = canvas.getContext("2d");
                    hoverCtx.save();
                    hoverCtx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
                    hoverCtx.scale(viewportHook.zoom, viewportHook.zoom);
                    draw_hover_outline(hoverCtx, getElementBounds(hoverCtx, hovered), viewportHook.zoom);
                    hoverCtx.restore();
                }
            }

            # Alignment guides sit on top of the finished frame; a drag updates
            # the elements on every move, so this runs for each frame of it.
            if snapGuidesRef.current and len(snapGuidesRef.current) > 0 {
                guideCtx = canvas.getContext("2d");
                guideCtx.save();
                guideCtx.translate(viewportHook.panOffset.x, viewportHook.panOffset.y);
                guideCtx.scale(viewportHook.zoom, viewportHook.zoom);
                draw_snap_guides(guideCtx, snapGuidesRef.current, viewportHook.zoom);
                guideCtx.restore();
            }
        }
        if onSelectionChange {
            # The whole selection, not only the primary: the inspector has to
            # know whether ANY selected shape carries a label before it can
            # decide whether to offer the text controls.
            onSelectionChange(selectionHook.selectedElement, selectionHook.selectedElements);
        }
    }

    def triggerImageUpload() -> None {
        imgInput = document.createElement("input");
        imgInput.type = "file";
        imgInput.accept = "image/*";
        imgInput.onchange = lambda (evt: any) {
            imgFile = evt.target.files[0];
            if imgFile {
                imgReader = new(FileReader);
                imgReader.onload = lambda (loadEvt: any) {
                    imgObj = new(Image);
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
                            if not toolLockedRef.current { onToolChange("select"); }
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
            # Shift+1 frames everything -- the standard zoom-to-fit chord.
            if not textInputHook.textInput and e.shiftKey and (e.key == "!" or e.key == "1") {
                fitToContent();
                e.preventDefault();
            }

            # Q locks the active tool, matching every other whiteboard.
            if not textInputHook.textInput and (e.key == "q" or e.key == "Q")
                and not e.ctrlKey and not e.metaKey and not e.altKey {
                onToolLockChange(not toolLockedRef.current);
                e.preventDefault();
            }

            # Arrow keys nudge the selection: 1px for precision, 10px with Shift
            # for moving something across without reaching for the mouse.
            if not textInputHook.textInput and e.key.startswith("Arrow") {
                nudge_step = 10 if e.shiftKey else 1;
                nudge_dx = 0;
                nudge_dy = 0;
                if e.key == "ArrowLeft"  { nudge_dx = -nudge_step; }
                if e.key == "ArrowRight" { nudge_dx = nudge_step; }
                if e.key == "ArrowUp"    { nudge_dy = -nudge_step; }
                if e.key == "ArrowDown"  { nudge_dy = nudge_step; }
                if nudge_dx != 0 or nudge_dy != 0 {
                    if nudgeSelection(nudge_dx, nudge_dy) {
                        e.preventDefault();
                    }
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
                bumpFontSize(-2);
            }
            if not textInputHook.textInput and (e.key == ">" or e.key == ".") and (e.ctrlKey or e.metaKey) and e.shiftKey {
                e.preventDefault();
                bumpFontSize(2);
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
                # Elements arriving from the MCP tools or the agent never went
                # through the editor, so nothing has checked that a labelled
                # shape is tall enough to hold its label. Same containment as
                # the UI paths, applied at the boundary.
                elementsHook.addElement(fit_shape_to_label(element));
            };
        }
        if updateElementRef {
            updateElementRef.current = lambda (id: any, changes: any) {
                # A style change applies to EVERY selected shape, not just the
                # one the sidebar happens to hold. The panel has a single id to
                # hand back, so without this a user who selects six boxes and
                # picks a colour watches exactly one of them change, with
                # nothing on screen explaining why the rest were ignored.
                styleTargets = [id];
                # Read the selection through the ref, not the closure: this
                # lambda is installed by an effect that only re-runs when the
                # ELEMENT list changes, so selecting shapes does not refresh it
                # and the captured selection would still be the empty one from
                # before Ctrl+A.
                multiSel = selectedElementsRef.current;
                if multiSel and multiSel.length > 1 {
                    inSel = False;
                    mi = 0;
                    while mi < multiSel.length {
                        if multiSel[mi] and multiSel[mi].id == id { inSel = True; }
                        mi = mi + 1;
                    }
                    # Only widen when the sidebar's element really is part of the
                    # selection; otherwise this is some other caller's update.
                    if inSel {
                        styleTargets = [];
                        mi = 0;
                        while mi < multiSel.length {
                            if multiSel[mi] and multiSel[mi].id {
                                styleTargets.append(multiSel[mi].id);
                            }
                            mi = mi + 1;
                        }
                    }
                }

                styleBatch = [];
                stillSelected = [];
                primaryEl = None;
                ti = 0;
                while ti < styleTargets.length {
                    wantId = styleTargets[ti];
                    liveEls = (elementsHook.elementsRef and elementsHook.elementsRef.current)
                        or elementsHook.elements;
                    fi = 0;
                    foundEl = None;
                    while fi < liveEls.length {
                        if liveEls[fi] and liveEls[fi].id == wantId {
                            foundEl = liveEls[fi];
                        }
                        fi = fi + 1;
                    }
                    if foundEl {
                        # A bigger label needs a bigger box, so restyling can
                        # change geometry too.
                        newElement = fit_shape_to_label({**foundEl, **changes});
                        styleBatch.append({"id": wantId, "element": newElement});
                        stillSelected.append({"element": newElement, "id": wantId});
                        if wantId == id { primaryEl = newElement; }
                    }
                    ti = ti + 1;
                }
                if styleBatch.length == 0 {
                    return;
                }
                # One write for the whole selection: N separate updateElement
                # calls would each rebuild from the same list and only the last
                # would survive.
                elementsHook.updateMultipleElements(styleBatch);
                if primaryEl {
                    selectionHook.setSelectedElement({"element": primaryEl, "id": id});
                }
                if stillSelected.length > 1 {
                    selectionHook.setSelectedElements(stillSelected);
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
                fitted = [];
                si = 0;
                while si < elements.length {
                    fitted.append(fit_shape_to_label(elements[si]));
                    si = si + 1;
                }
                elementsHook.setElements(fitted);
                selectionHook.clearSelection();
            };
        }
    }

    def handleCanvasClick(e: MouseEvent) -> None {
        if currentTool == "text" {
            if textInputHook.textInput {
                handleTextSubmit();
                if onToolChange {
                    if not toolLockedRef.current { onToolChange("select"); }
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
        } elif elementInfo and (elementInfo.element.type == "line" or elementInfo.element.type == "arrow") {
            # A label on the connector itself. In a flowchart most of the
            # meaning lives on the arrows ("yes", "no", "on failure"), and
            # without this the only way to write it was a floating text element
            # that did not travel with the arrow.
            lineEl = elementInfo.element;
            labelX = (lineEl.x1 + lineEl.x2) / 2;
            labelY = (lineEl.y1 + lineEl.y2) / 2;
            # A curved connector reads from its bend, not the straight midpoint.
            if lineEl.bendX != None and lineEl.bendX != undefined {
                labelX = lineEl.bendX;
                labelY = lineEl.bendY;
            }
            existingLineText = lineEl.shapeText or "";
            textInputHook.startTextInput(labelX, labelY, existingLineText, elementInfo.id, lineEl);
            selectionHook.clearSelection();
            setTimeout(lambda {
                if textInputRef.current {
                    textInputRef.current.focus();
                    if existingLineText != "" {
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
            updatedShape = fit_shape_to_label(updatedShape);
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
            if not toolLockedRef.current { onToolChange("select"); }
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

    """Grow a shape so its label fits inside it, and return the adjusted copy.

    The label wraps to the shape's width, so a shape can always be made too
    short for its own text. Excalidraw grows the container instead of letting
    the words escape it, and so do we: a label rendered outside its own box
    looks like a rendering fault, and nothing in the UI tells the user that
    making the box taller would fix it."""
    def fit_shape_to_label(el: any) -> any {
        if not el or not el.shapeText {
            return el;
        }
        # Boxes only. A line or arrow carries a label too, but it has no width
        # or height to grow -- without this guard the arithmetic below runs on
        # undefined and writes a NaN height onto the line.
        kind = el.type or "";
        if kind != "rectangle" and kind != "circle" and kind != "diamond" and kind != "image" {
            return el;
        }
        fit_canvas = canvasRef.current;
        if not fit_canvas {
            return el;
        }
        needed = shape_text_min_height(fit_canvas.getContext("2d"), el);
        if needed <= 0 {
            return el;
        }
        # Height can be negative when the shape was drawn bottom-up; grow it
        # along whichever direction it already runs so it does not flip.
        if Math.abs(el.height) >= needed {
            return el;
        }
        grown = {**el};
        grown.height = needed if el.height >= 0 else -needed;
        return grown;
    }

    """Grow the shape being labelled as the user types.

    The box otherwise only caught up on commit, so a long label spilled out of
    it for the whole time it was being written -- which is exactly when the user
    is looking at it. Silent: this is one continuous edit, not a stack of undo
    steps, and the commit records the history entry."""
    def growEditingShape(draft: str) -> None {
        live_edit = textInputHook.textInput;
        if not live_edit {
            return;
        }
        shape_id = live_edit.editingShapeId;
        if shape_id == None or shape_id == undefined {
            return;
        }
        host = live_edit.editingShapeElement;
        if not host {
            return;
        }
        probe = {**host};
        probe.shapeText = draft;
        probe.shapeTextFontSize = currentFontSize;
        probe.shapeTextFontFamily = currentFontFamily;
        grown = fit_shape_to_label(probe);
        if Math.abs(grown.height) != Math.abs(host.height) {
            # Keep the stored label as it was; only the geometry moves while
            # typing, so an abandoned edit does not leave half a word behind.
            resized = {**host};
            resized.height = grown.height;
            # Grow about the CENTRE, not downward. The editing overlay is
            # centred on the shape, so growing one-sided slides the box out from
            # under the very text being typed.
            resized.y = host.y + (host.height - grown.height) / 2;
            elementsHook.updateElementSilent(shape_id, resized);
            textInputHook.textInput.editingShapeElement = resized;
        }
    }

    # One normalisation pass on mount, so a drawing SAVED before shapes learned
    # to hold their labels heals itself on open rather than staying broken
    # forever. Idempotent: a drawing that is already correct is left untouched
    # and nothing is written.
    can with entry {
        heal_canvas = canvasRef.current;
        if heal_canvas {
            heal_src = (elementsHook.elementsRef and elementsHook.elementsRef.current)
                or elementsHook.elements;
            heal_out = [];
            heal_changed = False;
            hi = 0;
            while hi < heal_src.length {
                heal_el = heal_src[hi];
                heal_fit = fit_shape_to_label(heal_el);
                if heal_fit != heal_el {
                    heal_changed = True;
                }
                heal_out.append(heal_fit);
                hi = hi + 1;
            }
            if heal_changed {
                elementsHook.setElementsReplaceAll(heal_out);
            }
        }
    }

    """Resize the selected element's text by `delta` points.

    A label living inside a shape is stored as shapeText/shapeTextFontSize, not
    as a text element, so keying off type == "text" alone silently ignored every
    labelled box -- while the help dialog went on advertising the shortcut."""
    def bumpFontSize(delta: float) -> None {
        curSel = selectedElementRef.current;
        if not curSel or not curSel.element {
            return;
        }
        element = curSel.element;
        is_label = element.type != "text";
        if is_label and not element.shapeText {
            return;
        }
        current = (element.shapeTextFontSize or 16) if is_label else (element.fontSize or 16);
        newSize = current + delta;
        if newSize < 8 {
            newSize = 8;
        }
        if newSize > 120 {
            newSize = 120;
        }
        # Written out per field rather than with a computed key: a dict literal
        # keyed by a variable does not survive the client compile, and fails
        # silently -- the update is applied to a key nothing ever reads.
        updated = {**element};
        if is_label {
            updated.shapeTextFontSize = newSize;
        } else {
            updated.fontSize = newSize;
        }
        # A bigger label needs a bigger box.
        updated = fit_shape_to_label(updated);
        elementsHook.updateElement(element.id, updated);
        selectionHookRef.current.setSelectedElement({"element": updated, "id": element.id});
    }

    """Say what a click here would do, through the cursor.

    Without this the pointer stayed a plain arrow everywhere in select mode, so
    nothing distinguished "you will move this", "you will resize it" and "you
    will start a selection box" until after you had committed to the gesture.

    Written straight onto the element rather than held in state: this runs on
    every mouse move, and a re-render per move would be paid for nothing."""
    def updateHoverCursor(pos: any) -> None {
        target = canvasRef.current;
        if not target {
            return;
        }
        if currentTool != "select" or spacePressed {
            target.style.cursor = "";
            return;
        }

        sel = selectedElementRef.current;
        if sel and sel.element {
            hoverCtx = target.getContext("2d");
            hb = getElementBounds(hoverCtx, sel.element);
            if hb {
                if get_rotation_handle_at_point(pos, hb, sel.element) {
                    target.style.cursor = "grab";
                    return;
                }
                hoverHandle = getResizeHandleAtPoint(pos, hb);
                if hoverHandle {
                    # The arrow points the way the corner will travel.
                    if hoverHandle == "nw" or hoverHandle == "se" {
                        target.style.cursor = "nwse-resize";
                    } elif hoverHandle == "ne" or hoverHandle == "sw" {
                        target.style.cursor = "nesw-resize";
                    } elif hoverHandle == "n" or hoverHandle == "s" {
                        target.style.cursor = "ns-resize";
                    } else {
                        target.style.cursor = "ew-resize";
                    }
                    return;
                }
            }
        }

        over = selectionHook.findElementAtPoint(pos, elementsHook.elements);
        if over {
            target.style.cursor = "move";
        } else {
            target.style.cursor = "";
        }

        # Outline what would be picked, but only when it CHANGES -- redrawing on
        # every mouse move would be work done for nothing.
        nextHover = None;
        if over and over.id {
            selNow = selectedElementRef.current;
            # The selected element already has its own outline and handles.
            if not (selNow and selNow.id == over.id) {
                nextHover = over.id;
            }
        }
        if nextHover != hoveredId {
            hoveredId = nextHover;
        }
    }

    """Nudge a drag so the selection lines up with its neighbours.

    Returns the pointer position to actually use, and records the guides that
    justify it. Holding Ctrl/Cmd suppresses snapping, for the times you want a
    shape exactly where you put it."""
    def snapDragPosition(raw: any, disabled: bool) -> any {
        snapGuidesRef.current = [];
        if disabled {
            return raw;
        }

        sel = selectedElementsRef.current;
        single = selectedElementRef.current;
        movers = [];
        dx = 0.0;
        dy = 0.0;

        if sel and sel.length > 1 and selectionHook.dragStartPos {
            dx = raw.x - selectionHook.dragStartPos.x;
            dy = raw.y - selectionHook.dragStartPos.y;
            si = 0;
            while si < sel.length {
                movers.append(sel[si].element);
                si = si + 1;
            }
        } elif single and single.element and selectionHook.dragOffset {
            moved_el = single.element;
            # Freehand is dragged by its own point list rather than an origin,
            # so there is no single delta to correct here.
            if moved_el.type == "freehand" {
                return raw;
            }
            movers.append(moved_el);
            if moved_el.type == "line" or moved_el.type == "arrow" {
                dx = raw.x - selectionHook.dragOffset.x - moved_el.x1;
                dy = raw.y - selectionHook.dragOffset.y - moved_el.y1;
            } else {
                dx = raw.x - selectionHook.dragOffset.x - moved_el.x;
                dy = raw.y - selectionHook.dragOffset.y - moved_el.y;
            }
        } else {
            return raw;
        }

        moving_parts = [];
        moving_ids = {};
        mi = 0;
        while mi < len(movers) {
            mb = element_bounds(movers[mi]);
            if mb {
                moving_parts.append({
                    "left": mb["left"] + dx, "right": mb["right"] + dx,
                    "top": mb["top"] + dy, "bottom": mb["bottom"] + dy
                });
            }
            moving_ids[movers[mi].id] = True;
            mi = mi + 1;
        }
        moving = union_bounds(moving_parts);
        if not moving {
            return raw;
        }

        others = [];
        pool = (elementsHook.elementsRef and elementsHook.elementsRef.current) or elementsHook.elements;
        pi = 0;
        while pi < pool.length {
            cand = pool[pi];
            if cand and not moving_ids[cand.id] {
                ob = element_bounds(cand);
                if ob {
                    others.append(ob);
                }
            }
            pi = pi + 1;
        }

        # The threshold is a SCREEN distance, so zooming in does not make the
        # snap grabbier in world terms.
        snap = compute_snap(moving, others, snap_threshold_for(viewportHook.zoom));
        snapGuidesRef.current = snap["guides"];
        return {"x": raw.x + snap["dx"], "y": raw.y + snap["dy"]};
    }

    """Move the selection by (dx, dy) world units. False when nothing is selected.

    Arrows are the fine-adjustment tool: nothing else lets you move a shape by
    exactly one unit, and reaching for the mouse to fix a 2px misalignment is
    the kind of friction that makes a canvas feel unfinished."""
    def nudgeSelection(dx: float, dy: float) -> bool {
        nudge_multi = selectedElementsRef.current;
        nudge_single = selectedElementRef.current;

        # Re-read each element from the live list rather than trusting the
        # selection snapshot: holding an arrow key fires many keydowns before
        # React re-renders, and shifting the same stale copy each time makes
        # every repeat land in exactly the same place.
        live = (elementsHook.elementsRef and elementsHook.elementsRef.current) or elementsHook.elements;
        def current_by_id(want_id: str) -> any {
            for cand in live {
                if cand and cand.id == want_id {
                    return cand;
                }
            }
            return None;
        }

        if nudge_multi and len(nudge_multi) > 0 {
            # One batched write, not one per element: each updateElement rebuilds
            # the list from the CURRENT render's `elements`, so N calls in a
            # single keydown would leave only the last one's change standing.
            batch = [];
            ni = 0;
            while ni < len(nudge_multi) {
                nel = current_by_id(nudge_multi[ni].id);
                if nel {
                    batch.append({"id": nel.id, "element": shift_element(nel, dx, dy)});
                }
                ni = ni + 1;
            }
            if len(batch) == 0 {
                return False;
            }
            elementsHook.updateMultipleElements(batch);
            return True;
        }
        if nudge_single and nudge_single.element {
            nsel = current_by_id(nudge_single.id) or nudge_single.element;
            moved = shift_element(nsel, dx, dy);
            # The shape AND the arrows bound to it go out as one write, for the
            # same reason as above: two updateElement calls in a single keydown
            # both rebuild from the same list, so the second discards the first
            # and the arrow would be left behind by its own shape.
            single_batch = [{"id": nsel.id, "element": moved}];
            for bound in find_bound_line_updates_for_shape(moved, live) {
                single_batch.append({"id": bound.id, "element": bound.element});
            }
            elementsHook.updateMultipleElements(single_batch);
            selectionHook.setSelectedElement({"element": moved, "id": nsel.id});
            return True;
        }
        return False;
    }

    """Frame everything on the canvas."""
    def fitToContent() -> None {
        fit_els = elementsHook.elements;
        if not fit_els or len(fit_els) == 0 {
            return;
        }
        fit_canvas = canvasRef.current;
        if not fit_canvas {
            return;
        }
        fit_ctx = fit_canvas.getContext("2d");
        fit_minx = None; fit_miny = None; fit_maxx = None; fit_maxy = None;
        for fel in fit_els {
            fb = getElementBounds(fit_ctx, fel);
            if not fb { continue; }
            if fit_minx == None or fb.x < fit_minx { fit_minx = fb.x; }
            if fit_miny == None or fb.y < fit_miny { fit_miny = fb.y; }
            if fit_maxx == None or fb.x + fb.width > fit_maxx { fit_maxx = fb.x + fb.width; }
            if fit_maxy == None or fb.y + fb.height > fit_maxy { fit_maxy = fb.y + fb.height; }
        }
        if fit_minx == None { return; }
        fit_rect = fit_canvas.getBoundingClientRect();
        viewportHook.zoomToFit(
            {"x": fit_minx, "y": fit_miny, "width": fit_maxx - fit_minx, "height": fit_maxy - fit_miny},
            fit_rect.width, fit_rect.height
        );
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

    """Move the selection to the very front or the very back of the stack.

    ONE setElements call, not a remove followed by an add: both rebuild the list
    from the CURRENT render, so that pair cancelled out and bring-to-front did
    nothing at all. The selection is also kept -- clearing it meant you could not
    layer twice in a row and lost your place after a single press."""
    def _reorder_selection(to_front: bool) -> None {
        picked = [];
        multi = selectedElementsRef.current;
        single = selectedElementRef.current;
        if multi and multi.length > 1 {
            mi = 0;
            while mi < multi.length {
                picked.append(multi[mi].id);
                mi = mi + 1;
            }
        } elif single {
            picked.append(single.id);
        }
        if len(picked) == 0 {
            contextMenu = None;
            return;
        }

        pool = (elementsHook.elementsRef and elementsHook.elementsRef.current) or elementsHook.elements;
        moving = [];
        staying = [];
        pi = 0;
        while pi < pool.length {
            cand = pool[pi];
            isPicked = False;
            ci = 0;
            while ci < len(picked) {
                if cand.id == picked[ci] {
                    isPicked = True;
                }
                ci = ci + 1;
            }
            # Order WITHIN the moved set is preserved, so sending three shapes
            # back does not shuffle them against each other.
            if isPicked {
                moving.append(cand);
            } else {
                staying.append(cand);
            }
            pi = pi + 1;
        }
        if len(moving) == 0 {
            contextMenu = None;
            return;
        }
        if to_front {
            elementsHook.setElements(staying + moving);
        } else {
            elementsHook.setElements(moving + staying);
        }
        contextMenu = None;
    }

    def handleBringToFront() -> None {
        _reorder_selection(True);
    }

    def handleSendToBack() -> None {
        _reorder_selection(False);
    }

    # The handlers below are reached from the keydown listener, which is
    # installed by an effect that only re-runs when the ELEMENT list changes.
    # Selecting shapes does not change that list, so reading the selection from
    # the closure returned whatever it was BEFORE the selection was made --
    # Ctrl+A then Ctrl+G grouped nothing at all. They read the refs instead.
    def handleGroup() -> None {
        allSelected = [];
        if selectedElementsRef.current.length > 1 {
            allSelected = selectedElementsRef.current;
        } elif selectedElementRef.current {
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
        if selectedElementsRef.current.length > 0 {
            allSelected = selectedElementsRef.current;
        } elif selectedElementRef.current {
            allSelected = [selectedElementRef.current];
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
                                reader = new(FileReader);
                                reader.onload = lambda (event: any) {
                                    img = new(Image);
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
                    if not toolLockedRef.current { onToolChange("select"); }
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

            # Shift on a CORNER handle locks the aspect ratio, so a square stays
            # square and a circle stays round while it is resized. This mirrors
            # the way Shift already constrains a shape while it is being drawn;
            # without it the two gestures disagree about what Shift means.
            # Width leads and height follows, so the pointer never fights the
            # shape along one axis.
            is_corner_handle = handle == "se" or handle == "sw" or handle == "ne" or handle == "nw";
            is_box_shape = origEl.type == "rectangle" or origEl.type == "circle"
                or origEl.type == "image" or origEl.type == "diamond";
            if e.shiftKey and is_corner_handle and is_box_shape and origEl.height {
                lock_ratio = origEl.width / origEl.height;
                if lock_ratio {
                    locked_w = (origEl.width + deltaX)
                        if (handle == "se" or handle == "ne")
                        else (origEl.width - deltaX);
                    locked_h = locked_w / lock_ratio;
                    deltaY = (locked_h - origEl.height)
                        if (handle == "se" or handle == "sw")
                        else (origEl.height - locked_h);
                }
            }

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
                # A labelled shape cannot be dragged smaller than its own text.
                # The label re-wraps to the new width, so shrinking the width
                # makes the text TALLER -- without this the words spill out of
                # the box entirely and the diagram falls apart in the user's
                # hands with no way to undo it except undo.
                newElement = fit_shape_to_label(newElement);
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

        # Idle hover: keep the cursor honest about what a click would do.
        if not selectionHook.isDragging and not selectionHook.isResizing
            and not selectionHook.isBoxSelecting and not viewportHook.isPanning
            and not drawingState.isDrawing and not isRotating {
            updateHoverCursor(pos);
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

            # Line the drag up with the neighbours before anything is moved, so
            # both the single and multi paths below inherit the correction.
            pos = snapDragPosition(pos, e.ctrlKey or e.metaKey);

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
            # Shift constrains the shape being previewed, so what you see while
            # dragging is what you get on release.
            if e.shiftKey and drawingState.startPoint and currentTool in ["rectangle", "diamond", "circle", "line", "arrow"] {
                previewEnd = constrain_drag_point(drawingState.startPoint, pos, currentTool);
            }
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
            # Dragging a handle past the opposite edge flips the box; put it
            # back the right way round before the change is committed.
            resized = selectionHook.selectedElement;
            if resized and resized.element {
                straight = normalize_box(resized.element);
                if straight != resized.element {
                    elementsHook.updateElementSilent(resized.id, straight);
                    selectionHook.setSelectedElement({"element": straight, "id": resized.id});
                }
            }
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
        # The guides belong to the gesture, so they go when it does.
        snapGuidesRef.current = [];
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
                    # Constrain BEFORE snapping: Shift decides the angle, and the
                    # search for a shape to bind to then starts from the endpoint
                    # the user actually sees. Snapping first would let a nearby
                    # shape drag the line back off its 45 and undo the gesture.
                    if e.shiftKey {
                        dragEndPos = constrain_drag_point(drawingState.startPoint, dragEndPos, currentTool);
                    }
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
                        if not toolLockedRef.current { onToolChange("select"); }
                    }
                }
            }
            return;
        }

        drawingState.setIsDrawing(False);
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
        # Same Shift constraint the preview used, so release matches the preview.
        if e.shiftKey and drawingState.isDrawing and drawingState.startPoint
            and currentTool in ["rectangle", "diamond", "circle", "line", "arrow"] {
            pos = constrain_drag_point(drawingState.startPoint, pos, currentTool);
        }

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

        # A click rather than a drag leaves a shape with no size. Keeping it
        # littered the canvas with invisible elements that could still be
        # selected, counted and exported.
        if newElement and newElement.width != None and newElement.width != undefined {
            if Math.abs(newElement.width) < 3 and Math.abs(newElement.height) < 3 {
                newElement = None;
            }
        }

        if newElement {
            # Drawn bottom-up or right-to-left? Store it the right way round.
            newElement = normalize_box(newElement);
            elementsHook.addElement(newElement);
            if currentTool != "freehand" {
                selectionHook.setSelectedElement({"element": newElement, "id": newElement.id});
            }
            if onToolChange and currentTool != "freehand" {
                if not toolLockedRef.current { onToolChange("select"); }
            }
        }
    }

    # A gesture belongs to the pointer, not to the element it started on.
    #
    # Mouse events are bound to the canvas, so the moment the pointer crossed
    # onto the sidebar mid-drag the moves stopped arriving and the release was
    # never seen at all -- the shape froze part-way and the drag stayed
    # half-open. While a gesture is in flight these listeners follow the pointer
    # anywhere on the page, and they stand down again the moment it ends.
    gestureActive = selectionHook.isDragging or selectionHook.isResizing
        or selectionHook.isBoxSelecting or viewportHook.isPanning
        or drawingState.isDrawing or isRotating or isDraggingBend
        or isDraggingVertex or isDraggingElbowSegment;

    can with gestureActive entry {
        def forwardMove(ev: any) -> None {
            # The canvas already handles what happens over itself; this is only
            # for the part of the gesture that strays off it.
            if ev.target != canvasRef.current {
                handleMouseMove(ev);
            }
        }
        def forwardUp(ev: any) -> None {
            if ev.target != canvasRef.current {
                handleMouseUp(ev);
            }
        }
        if gestureActive {
            window.addEventListener("mousemove", forwardMove);
            window.addEventListener("mouseup", forwardUp);
        }
        # Always hand back a cleanup, on both branches: returning null on one of
        # them makes React try to CALL null when the effect is torn down.
        return lambda {
            window.removeEventListener("mousemove", forwardMove);
            window.removeEventListener("mouseup", forwardUp);
        };
    }

    def handleMouseLeave() -> None {
        hoveredId = None;
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
        <div ref={containerRef} className="relative w-full h-full flex items-center justify-center overflow-hidden canvas-dotgrid" onContextMenu={handleContextMenu}>
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
                    growEditingShape(e.target.value);
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

            <div className="absolute bottom-4 left-4 flex items-center gap-2 z-40 select-none">
              <div className="jsk-glass flex items-center rounded-xl">
                <button
                    title="Undo (Ctrl+Z)"
                    aria-label="Undo"
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 rounded-l-xl transition-colors"
                    onClick={lambda { elementsHook.undo(); selectionHook.clearSelection(); }}
                >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M9 14 4 9l5-5" /><path d="M4 9h10a6 6 0 0 1 0 12h-3" />
                    </svg>
                </button>
                <button
                    title="Redo (Ctrl+Shift+Z)"
                    aria-label="Redo"
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 rounded-r-xl transition-colors"
                    onClick={lambda { elementsHook.redo(); selectionHook.clearSelection(); }}
                >
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="m15 14 5-5-5-5" /><path d="M20 9H10a6 6 0 0 0 0 12h3" />
                    </svg>
                </button>
              </div>
              <div className="jsk-glass flex items-center rounded-xl">
                <button
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 rounded-l-xl text-base font-medium transition-colors"
                    onClick={lambda {
                        zoomCanvas = canvasRef.current;
                        if zoomCanvas {
                            zoomRect = zoomCanvas.getBoundingClientRect();
                            viewportHook.handleZoom(1, zoomRect.left + zoomRect.width / 2, zoomRect.top + zoomRect.height / 2, zoomCanvas);
                        }
                    }}
                >-</button>
                <button
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 text-sm font-medium min-w-[56px] text-center transition-colors"
                    onClick={lambda {
                        viewportHook.setZoom(1);
                        viewportHook.setPanOffset({"x": 0, "y": 0});
                    }}
                >{str(Math.round(viewportHook.zoom * 100)) + "%"}</button>
                <button
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 text-base font-medium transition-colors"
                    onClick={lambda {
                        ziCanvas = canvasRef.current;
                        if ziCanvas {
                            ziRect = ziCanvas.getBoundingClientRect();
                            viewportHook.handleZoom(-1, ziRect.left + ziRect.width / 2, ziRect.top + ziRect.height / 2, ziCanvas);
                        }
                    }}
                >+</button>
                <button
                    title="Zoom to fit (Shift+1)"
                    aria-label="Zoom to fit"
                    className="px-3 py-2 text-slate-600 hover:bg-slate-900/10 rounded-r-xl border-l border-slate-900/10/80 transition-colors"
                    onClick={lambda { fitToContent(); }}
                >
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M3 8V5a2 2 0 0 1 2-2h3" /><path d="M16 3h3a2 2 0 0 1 2 2v3" />
                        <path d="M21 16v3a2 2 0 0 1-2 2h-3" /><path d="M8 21H5a2 2 0 0 1-2-2v-3" />
                    </svg>
                </button>
              </div>
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
