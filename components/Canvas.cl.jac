import from react { useRef, useEffect, useState }
import from "..hooks.useCanvas" { useCanvas }
import from "..hooks.useDrawingState" { useDrawingState }
import from "..hooks.useElements" { useElements }
import from "..hooks.useSelection" { useSelection }
import from "..hooks.useViewport" { useViewport }
import from "..hooks.useTextInput" { useTextInput }
import from "..services.geometry" { getMousePosition, findNearestConnectionPoint }
import from "..services.canvas" { drawPreview, getElementBounds, drawConnectionPoints, drawSnapIndicator }
import from "..services.collision" { getResizeHandleAtPoint, getBendHandleAtPoint }
import from "..services.export" { exportSelectionAsPNG, exportSelectionAsSVG, copySelectionAsPNG, copyCanvasAsPNG, copyCanvasAsSVG }
import from "..constants.tools" { TOOL_SHORTCUTS }
import from .canvas.CanvasRenderer { CanvasRenderer }
import from .canvas.TextInput { TextInput }
import from .canvas.ContextMenu { ContextMenu }

def:pub Canvas(props: dict) -> JsxElement {
    currentTool = props.currentTool or "select";
    currentColor = props.currentColor or "#000000";
    currentStrokeWidth = props.currentStrokeWidth or 2;
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Virgil";
    currentOpacity = props.currentOpacity or 1.0;
    currentLineStyle = props.currentLineStyle or "solid";
    currentFillColor = props.currentFillColor or "transparent";

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
    [contextMenu, setContextMenu] = useState(None);
    [toastMessage, setToastMessage] = useState(None);
    clipboardRef = useRef([]);
    selectedElementRef = useRef(None);
    selectedElementsRef = useRef([]);
    altDragCopiedRef = useRef(False);
    drawingStateRef = useRef(drawingState);
    [isDraggingBend, setIsDraggingBend] = useState(False);
    [bendDragElement, setBendDragElement] = useState(None);

    selectedElementRef.current = selectionHook.selectedElement;
    selectedElementsRef.current = selectionHook.selectedElements;
    drawingStateRef.current = drawingState;

    # Get the editing shape index to suppress its shapeText during editing
    editingShapeIdx = None;
    if textInputHook.textInput and textInputHook.textInput.editingShapeIndex != None and textInputHook.textInput.editingShapeIndex != undefined {
        editingShapeIdx = textInputHook.textInput.editingShapeIndex;
    }

    can with [elementsHook.elements, canvasHook.canvasSize, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, drawingState.isDrawing, textInputHook.textInput] entry {
        canvas = canvasRef.current;
        if canvas {
            canvasHook.redrawCanvas(elementsHook.elements, viewportHook.zoom, viewportHook.panOffset, selectionHook.selectedElement, selectionHook.selectedElements, selectionHook.isBoxSelecting, selectionHook.boxStart, selectionHook.boxEnd, editingShapeIdx);
        }
        if props.onSelectionChange {
            props.onSelectionChange(selectionHook.selectedElement);
        }
    }

    def triggerImageUpload() -> None {
        imgInput = document.createElement("input");
        imgInput.type = "file";
        imgInput.accept = "image/*";
        imgInput.onchange = lambda evt: any -> None {
            imgFile = evt.target.files[0];
            if imgFile {
                imgReader = Reflect.construct(FileReader, []);
                imgReader.onload = lambda loadEvt: any -> None {
                    imgObj = Reflect.construct(Image, []);
                    imgObj.onload = lambda -> None {
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
                        imgIdx = elementsHook.elements.length;
                        selectionHook.setSelectedElement({"element": imgElement, "index": imgIdx});
                        if props.onToolChange {
                            props.onToolChange("select");
                        }
                    };
                    imgObj.src = loadEvt.target.result;
                };
                imgReader.readAsDataURL(imgFile);
            }
        };
        imgInput.click();
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
                copyCanvasAsPNG(elementsHook.elements, canvasRef, lambda -> None {
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
                        copied.push(Object.assign({}, curMulti[ci].element));
                        ci = ci + 1;
                    }
                    clipboardRef.current = copied;
                } elif curSingle and curSingle.element {
                    clipboardRef.current = [Object.assign({}, curSingle.element)];
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
                    viewportHook.handleZoom(-1, rect.left + rect.width / 2, rect.top + rect.height / 2, canvas);
                }
            }
            if not textInputHook.textInput and e.key == "-" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                canvas = canvasRef.current;
                if canvas {
                    rect = canvas.getBoundingClientRect();
                    viewportHook.handleZoom(1, rect.left + rect.width / 2, rect.top + rect.height / 2, canvas);
                }
            }
            if not textInputHook.textInput and e.key == "0" and (e.ctrlKey or e.metaKey) {
                e.preventDefault();
                viewportHook.setZoom(1);
                viewportHook.setPanOffset({"x": 0, "y": 0});
            }
            if not textInputHook.textInput and not e.ctrlKey and not e.metaKey and not e.shiftKey and not e.altKey {
                if e.key == "9" {
                    triggerImageUpload();
                } else {
                    shortcuts = TOOL_SHORTCUTS();
                    toolForKey = shortcuts[e.key];
                    if toolForKey and props.onToolChange {
                        props.onToolChange(toolForKey);
                    }
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
    }, [textInputHook.textInput, elementsHook.elements]);

    useEffect(lambda -> any {
        canvas = canvasRef.current;
        if not canvas {
            return None;
        }

        def handleWheel(e: dict) -> None {
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
        return lambda -> None {
            canvas.removeEventListener("wheel", handleWheel);
        };
    }, [viewportHook.zoom, viewportHook.panOffset]);

    useEffect(lambda -> None {
        if props.clearCanvasRef {
            props.clearCanvasRef.current = lambda -> None {
                elementsHook.clearElements();
                selectionHook.clearSelection();
            };
        }
        if props.addElementRef {
            props.addElementRef.current = lambda element: any -> None {
                elementsHook.addElement(element);
            };
        }
        if props.updateElementRef {
            props.updateElementRef.current = lambda index: any, changes: any -> None {
                element = elementsHook.elements[index];
                if element {
                    newElement = Object.assign({}, element, changes);
                    elementsHook.updateElement(index, newElement);
                    selectionHook.setSelectedElement({"element": newElement, "index": index});
                }
            };
        }
    }, [elementsHook.elements]);

    def handleCanvasClick(e: dict) -> None {
        if currentTool == "text" {
            if textInputHook.textInput {
                handleTextSubmit();
                if props.onToolChange {
                    props.onToolChange("select");
                }
                return;
            }
            pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

            elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);
            if elementInfo and elementInfo.element.type == "text" {
                element = elementInfo.element;
                textInputHook.startTextInput(element.x, element.y, element.text, None, None);
                elementsHook.removeElement(elementInfo.index);
                selectionHook.clearSelection();
                setTimeout(lambda -> None {
                    if textInputRef.current {
                        textInputRef.current.focus();
                        textInputRef.current.select();
                    }
                }, 10);
            } else {
                textInputHook.startTextInput(pos.x, pos.y, "", None, None);
                setTimeout(lambda -> None {
                    if textInputRef.current {
                        textInputRef.current.focus();
                    }
                }, 10);
            }
        }
    }

    def handleCanvasDoubleClick(e: dict) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);
        elementInfo = selectionHook.findElementAtPoint(pos, elementsHook.elements);

        if elementInfo and elementInfo.element.type == "text" {
            element = elementInfo.element;
            textInputHook.startTextInput(element.x, element.y, element.text, None, None);
            elementsHook.removeElement(elementInfo.index);
            selectionHook.clearSelection();

            setTimeout(lambda -> None {
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
            textInputHook.startTextInput(shapeCenterX, shapeCenterY, existingShapeText, elementInfo.index, shapeEl);
            selectionHook.clearSelection();
            setTimeout(lambda -> None {
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
            setTimeout(lambda -> None {
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
        shapeIdx = textInputHook.textInput.editingShapeIndex;
        if shapeIdx != None and shapeIdx != undefined {
            # Updating text inside a shape
            shapeElement = elementsHook.elements[shapeIdx];
            updatedShape = Object.assign({}, shapeElement);
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
            elementsHook.updateElement(shapeIdx, updatedShape);
            selectionHook.setSelectedElement({"element": updatedShape, "index": shapeIdx});
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
            newTextIdx = elementsHook.elements.length;
            selectionHook.setSelectedElement({"element": textEl, "index": newTextIdx});
        }
        textInputHook.cancelTextInput();
        if props.onToolChange {
            props.onToolChange("select");
        }
    }

    def handleTextKeyDown(e: dict) -> None {
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
            delIndices = [];
            di = 0;
            while di < curMulti.length {
                delIndices.push(curMulti[di].index);
                di = di + 1;
            }
            elementsHook.removeMultipleElements(delIndices);
            selectionHook.clearSelection();
        } elif curSingle {
            elementsHook.removeElement(curSingle.index);
            selectionHook.clearSelection();
        }
    }

    def handleContextMenu(e: dict) -> None {
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
        while ctxi < ctxAllSelected.length {
            if ctxAllSelected[ctxi].element and ctxAllSelected[ctxi].element.groupId {
                ctxCanUngroup = True;
            }
            ctxi = ctxi + 1;
        }
        setContextMenu({
            "x": e.clientX,
            "y": e.clientY,
            "hasSelection": hasSel,
            "canGroup": ctxCanGroup,
            "canUngroup": ctxCanUngroup
        });
    }

    def handleDeleteFromMenu() -> None {
        deleteSelected();
        setContextMenu(None);
    }

    def offsetElement(original: dict, dx: float, dy: float) -> dict {
        dup = Object.assign({}, original);
        if original.type == "text" or original.type == "rectangle" or original.type == "circle" or original.type == "image" or original.type == "diamond" {
            dup.x = original.x + dx;
            dup.y = original.y + dy;
        } elif original.type == "line" or original.type == "arrow" {
            dup.x1 = original.x1 + dx;
            dup.y1 = original.y1 + dy;
            dup.x2 = original.x2 + dx;
            dup.y2 = original.y2 + dy;
            if original.bendX != None and original.bendX != undefined {
                dup.bendX = original.bendX + dx;
                dup.bendY = original.bendY + dy;
            }
        } elif original.type == "freehand" {
            dup.points = original.points.map(lambda p: dict -> dict {
                return {"x": p.x + dx, "y": p.y + dy};
            });
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
                dups.push(offsetElement(curMultiDup[ddi].element, 20, 20));
                ddi = ddi + 1;
            }
            dupBase = elementsHook.elements.length;
            elementsHook.addMultipleElements(dups);
            dupSel = [];
            dsi = 0;
            while dsi < dups.length {
                dupSel.push({"element": dups[dsi], "index": dupBase + dsi});
                dsi = dsi + 1;
            }
            selectionHook.setSelectedElements(dupSel);
            selectionHook.setSelectedElement(None);
        } elif curSingleDup and curSingleDup.element {
            singleDup = offsetElement(curSingleDup.element, 20, 20);
            elementsHook.addElement(singleDup);
        }
        setContextMenu(None);
    }

    def handleBringToFront() -> None {
        if selectionHook.selectedElement {
            idx = selectionHook.selectedElement.index;
            element = selectionHook.selectedElement.element;
            elementsHook.removeElement(idx);
            elementsHook.addElement(element);
            selectionHook.clearSelection();
        }
        setContextMenu(None);
    }

    def handleSendToBack() -> None {
        if selectionHook.selectedElement {
            idx = selectionHook.selectedElement.index;
            element = selectionHook.selectedElement.element;
            newElements = [element].concat(elementsHook.elements.filter(lambda _: any, i: any -> bool {
                return i != idx;
            }));
            elementsHook.setElements(newElements);
            selectionHook.clearSelection();
        }
        setContextMenu(None);
    }

    def handleGroup() -> None {
        allSelected = [];
        if selectionHook.selectedElements.length > 1 {
            allSelected = selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            # Single selected, nothing to group
            setContextMenu(None);
            return;
        }
        if allSelected.length < 2 {
            setContextMenu(None);
            return;
        }
        groupId = "g_" + String(Date.now()) + "_" + String(Math.floor(Math.random() * 10000));
        newElements = elementsHook.elements.slice();
        gi = 0;
        while gi < allSelected.length {
            idx = allSelected[gi].index;
            updated = Object.assign({}, newElements[idx]);
            updated.groupId = groupId;
            newElements[idx] = updated;
            gi = gi + 1;
        }
        elementsHook.setElements(newElements);
        # Refresh selectedElements with updated elements
        newSel = [];
        gsi = 0;
        while gsi < allSelected.length {
            selIdx = allSelected[gsi].index;
            newSel.push({"element": newElements[selIdx], "index": selIdx});
            gsi = gsi + 1;
        }
        selectionHook.setSelectedElements(newSel);
        setContextMenu(None);
    }

    def handleUngroup() -> None {
        allSelected = [];
        if selectionHook.selectedElements.length > 0 {
            allSelected = selectionHook.selectedElements;
        } elif selectionHook.selectedElement {
            allSelected = [selectionHook.selectedElement];
        }
        if allSelected.length == 0 {
            setContextMenu(None);
            return;
        }
        # Collect all groupIds from selected elements
        groupIdsToRemove = {};
        ugi = 0;
        while ugi < allSelected.length {
            el = allSelected[ugi].element;
            if el.groupId {
                groupIdsToRemove[el.groupId] = True;
            }
            ugi = ugi + 1;
        }
        # Remove groupId from ALL elements that share those groupIds
        newElements = elementsHook.elements.slice();
        rei = 0;
        while rei < newElements.length {
            if newElements[rei].groupId and groupIdsToRemove[newElements[rei].groupId] {
                updated = Object.assign({}, newElements[rei]);
                updated.groupId = None;
                newElements[rei] = updated;
            }
            rei = rei + 1;
        }
        elementsHook.setElements(newElements);
        # Refresh selection
        newSel = [];
        ursi = 0;
        while ursi < allSelected.length {
            selIdx = allSelected[ursi].index;
            newSel.push({"element": newElements[selIdx], "index": selIdx});
            ursi = ursi + 1;
        }
        if newSel.length > 1 {
            selectionHook.setSelectedElements(newSel);
        } elif newSel.length == 1 {
            selectionHook.setSelectedElement(newSel[0]);
            selectionHook.setSelectedElements([]);
        }
        setContextMenu(None);
    }

    def handleClearCanvas() -> None {
        elementsHook.clearElements();
        selectionHook.clearSelection();
        setContextMenu(None);
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
        setContextMenu(None);
    }

    def handleExportSVG() -> None {
        exportSelectionAsSVG(getExportElements(), canvasRef);
        setContextMenu(None);
    }

    def handleCopySelectionPNG() -> None {
        copySelectionAsPNG(getExportElements(), canvasRef, lambda -> None {
            showToast("Copied as PNG");
        });
        setContextMenu(None);
    }

    def pasteInternalClipboard() -> None {
        if clipboardRef.current.length > 0 {
            newElements = [];
            pi = 0;
            while pi < clipboardRef.current.length {
                newElements.push(offsetElement(clipboardRef.current[pi], 20, 20));
                pi = pi + 1;
            }
            baseIndex = elementsHook.elements.length;
            elementsHook.addMultipleElements(newElements);
            pastedSelection = [];
            psi = 0;
            while psi < newElements.length {
                pastedSelection.push({"element": newElements[psi], "index": baseIndex + psi});
                psi = psi + 1;
            }
            selectionHook.setSelectedElements(pastedSelection);
            if pastedSelection.length == 1 {
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
            .then(lambda clipItems: any -> None {
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
                            clipItem.getType(clipTypes[ti]).then(lambda blob: any -> None {
                                reader = Reflect.construct(FileReader, []);
                                reader.onload = lambda event: any -> None {
                                    img = Reflect.construct(Image, []);
                                    img.onload = lambda -> None {
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
                                clipItem.getType("text/plain").then(lambda blob: any -> None {
                                    blob.text().then(lambda txt: str -> None {
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
            .catch(lambda err: any -> None {
                console.log("System clipboard not available");
            });
    }

    def handlePasteFromMenu() -> None {
        setContextMenu(None);
        pasteFromSystemClipboard();
    }

    def showToast(msg: str) -> None {
        setToastMessage(msg);
        setTimeout(lambda -> None { setToastMessage(None); }, 2000);
    }

    def handleCopyCanvasAsPNG() -> None {
        copyCanvasAsPNG(elementsHook.elements, canvasRef, lambda -> None {
            showToast("Copied as PNG");
        });
        setContextMenu(None);
    }

    def handleCopyCanvasAsSVG() -> None {
        copyCanvasAsSVG(elementsHook.elements, canvasRef, lambda -> None {
            showToast("Copied as SVG");
        });
        setContextMenu(None);
    }

    def handleSelectAll() -> None {
        allElements = [];
        idx = 0;
        while idx < elementsHook.elements.length {
            allElements.push({"element": elementsHook.elements[idx], "index": idx});
            idx = idx + 1;
        }
        selectionHook.setSelectedElements(allElements);
        setContextMenu(None);
    }

    def handleMouseDown(e: dict) -> None {
        setContextMenu(None);
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
                if (selEl.type == "line" or selEl.type == "arrow") and getBendHandleAtPoint(pos, selEl) {
                    setIsDraggingBend(True);
                    setBendDragElement(Object.assign({}, selEl));
                    selectionHook.setDragStartPos(pos);
                    return;
                }

                canvas = canvasRef.current;
                if canvas {
                    ctx = canvas.getContext("2d");
                    bounds = getElementBounds(ctx, selEl);
                    handle = getResizeHandleAtPoint(pos, bounds);
                    if handle {
                        selectionHook.setIsResizing(True);
                        selectionHook.setResizeHandle(handle);
                        selectionHook.setResizeStartElement(Object.assign({}, selEl));
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
                        if selectionHook.selectedElements[si].index == elementInfo.index {
                            isAlreadySelected = True;
                        }
                        si = si + 1;
                    }

                    if isAlreadySelected {
                        selectionHook.removeFromSelection(elementInfo.index);
                    } else {
                        # Build the full list in one go to avoid stale state
                        newMulti = selectionHook.selectedElements.slice();
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
                            if selectionHook.selectedElements[mi].index == elementInfo.index {
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
                                groupMembers.push({"element": elementsHook.elements[gmi], "index": gmi});
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
                endSnap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if endSnap {
                    endPos = endSnap.point;
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
                    "opacity": currentOpacity
                };
                elementsHook.addElement(lineElement);
                drawingState.setIsDrawing(False);
                drawingState.setStartPoint(None);
                newLineIdx = elementsHook.elements.length;
                selectionHook.setSelectedElement({"element": lineElement, "index": newLineIdx});
                if props.onToolChange {
                    props.onToolChange("select");
                }
            } else {
                startSnap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if startSnap {
                    drawingState.setStartPoint(startSnap.point);
                } else {
                    drawingState.setStartPoint(pos);
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

    def handleMouseMove(e: dict) -> None {
        pos = getMousePosition(e, canvasRef.current, viewportHook.panOffset, viewportHook.zoom);

        if viewportHook.isPanning {
            viewportHook.handlePan(e.movementX, e.movementY);
            return;
        }

        if isDraggingBend and selectionHook.selectedElement {
            selIdx = selectionHook.selectedElement.index;
            updatedEl = Object.assign({}, elementsHook.elements[selIdx]);
            updatedEl.bendX = pos.x;
            updatedEl.bendY = pos.y;
            elementsHook.updateElement(selIdx, updatedEl);
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
                        newElement.points = origEl.points.map(lambda point: dict -> dict {
                            return {
                                "x": minX + (point.x - minX) * scaleX,
                                "y": minY + (point.y - minY) * scaleY
                            };
                        });
                    }
                }
            }

            elementsHook.updateElementSilent(selectionHook.selectedElement.index, newElement);
            selectionHook.setSelectedElement({"element": newElement, "index": selectionHook.selectedElement.index});
            return;
        }

        if selectionHook.isDragging and currentTool == "select" {
            # Alt+Drag to duplicate: clone originals in place, then drag copies
            if e.altKey and not altDragCopiedRef.current {
                if selectionHook.selectedElements.length > 1 {
                    clones = [];
                    aci = 0;
                    while aci < selectionHook.selectedElements.length {
                        clones.push(Object.assign({}, selectionHook.selectedElements[aci].element));
                        aci = aci + 1;
                    }
                    altBase = elementsHook.elements.length;
                    elementsHook.addMultipleElements(clones);
                    # Point selection to the new copies (at end of array)
                    newSel = [];
                    nsi = 0;
                    while nsi < clones.length {
                        newSel.push({"element": clones[nsi], "index": altBase + nsi});
                        nsi = nsi + 1;
                    }
                    selectionHook.setSelectedElements(newSel);
                    selectionHook.setDragStartPos(pos);
                    altDragCopiedRef.current = True;
                    return;
                } elif selectionHook.selectedElement {
                    singleClone = Object.assign({}, selectionHook.selectedElement.element);
                    altSingleBase = elementsHook.elements.length;
                    elementsHook.addElement(singleClone);
                    selectionHook.setSelectedElement({"element": singleClone, "index": altSingleBase});
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
                    newElement = Object.assign({}, originalElement);

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
                    } elif originalElement.type == "freehand" {
                        newElement.points = originalElement.points.map(lambda point: dict -> dict {
                            return {"x": point.x + multiDx, "y": point.y + multiDy};
                        });
                    }

                    updates.push({"index": selectedInfo.index, "element": newElement});
                    i = i + 1;
                }
                elementsHook.updateMultipleElementsSilent(updates);
                # Update selectedElements so selection boxes move with the elements
                newSelectedElements = [];
                ui = 0;
                while ui < updates.length {
                    newSelectedElements.push({"element": updates[ui].element, "index": updates[ui].index});
                    ui = ui + 1;
                }
                selectionHook.setSelectedElements(newSelectedElements);
                # Update dragStartPos so delta is incremental, not cumulative
                selectionHook.setDragStartPos(pos);
                return;
            } elif selectionHook.selectedElement {
                element = selectionHook.selectedElement.element;
                newElement = Object.assign({}, element);

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
                } elif element.type == "freehand" {
                    fhDx = pos.x - selectionHook.dragOffset.x - element.points[0].x;
                    fhDy = pos.y - selectionHook.dragOffset.y - element.points[0].y;
                    newElement.points = element.points.map(lambda point: dict -> dict {
                        return {"x": point.x + fhDx, "y": point.y + fhDy};
                    });
                }

                elementsHook.updateElementSilent(selectionHook.selectedElement.index, newElement);
                selectionHook.setSelectedElement({"element": newElement, "index": selectionHook.selectedElement.index});
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

            # For line/arrow, show connection points and snap endpoint
            previewEnd = pos;
            if currentTool == "line" or currentTool == "arrow" {
                # Draw connection points on all shapes
                ei = 0;
                while ei < elementsHook.elements.length {
                    el = elementsHook.elements[ei];
                    if el.type == "rectangle" or el.type == "circle" or el.type == "text" or el.type == "diamond" {
                        drawConnectionPoints(previewCtx, el);
                    }
                    ei = ei + 1;
                }

                # Snap end point
                snap = findNearestConnectionPoint(pos, elementsHook.elements, 20.0);
                if snap {
                    previewEnd = snap.point;
                    drawSnapIndicator(previewCtx, snap.point);
                }
            }

            drawPreview(previewCtx, currentTool, drawingState.startPoint, previewEnd, currentColor, currentStrokeWidth);
            previewCtx.restore();
        }
    }

    def handleMouseUp(e: dict) -> None {
        if isDraggingBend {
            elementsHook.commitToHistory();
            setIsDraggingBend(False);
            setBendDragElement(None);
            if selectionHook.selectedElement {
                bendIdx = selectionHook.selectedElement.index;
                updatedBendEl = elementsHook.elements[bendIdx];
                selectionHook.setSelectedElement({"element": updatedBendEl, "index": bendIdx});
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
                    dragEndSnap = findNearestConnectionPoint(dragEndPos, elementsHook.elements, 20.0);
                    if dragEndSnap {
                        dragEndPos = dragEndSnap.point;
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
                        "opacity": currentOpacity
                    };
                    elementsHook.addElement(dragLineEl);
                    drawingState.setIsDrawing(False);
                    drawingState.setStartPoint(None);
                    dragLineIdx = elementsHook.elements.length;
                    selectionHook.setSelectedElement({"element": dragLineEl, "index": dragLineIdx});
                    if props.onToolChange {
                        props.onToolChange("select");
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
            newElIdx = elementsHook.elements.length;
            selectionHook.setSelectedElement({"element": newElement, "index": newElIdx});
            if props.onToolChange {
                props.onToolChange("select");
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
        setIsDraggingBend(False);
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

            <TextInput
                textInput={textInputHook.textInput}
                textInputRef={textInputRef}
                currentColor={currentColor}
                currentFontSize={currentFontSize}
                currentFontFamily={currentFontFamily}
                zoom={viewportHook.zoom}
                panOffset={viewportHook.panOffset}
                onTextChange={lambda e: any -> None {
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
                onClose={lambda -> None { setContextMenu(None); }}
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
                    onClick={lambda -> None {
                        zoomCanvas = canvasRef.current;
                        if zoomCanvas {
                            zoomRect = zoomCanvas.getBoundingClientRect();
                            viewportHook.handleZoom(1, zoomRect.left + zoomRect.width / 2, zoomRect.top + zoomRect.height / 2, zoomCanvas);
                        }
                    }}
                >-</button>
                <button
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 text-sm font-medium min-w-[56px] text-center transition-colors"
                    onClick={lambda -> None {
                        viewportHook.setZoom(1);
                        viewportHook.setPanOffset({"x": 0, "y": 0});
                    }}
                >{String(Math.round(viewportHook.zoom * 100)) + "%"}</button>
                <button
                    className="px-3 py-2 text-gray-600 hover:bg-gray-100 rounded-r-xl text-base font-medium transition-colors"
                    onClick={lambda -> None {
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
        </div>
    );
}
