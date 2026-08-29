import from "..services.collision" { isPointInElement }

def:pub useSelection() -> dict {
    has selectedElement: any = None;
    has selectedElements: list = [];
    has isDragging: bool = False;
    has dragOffset: dict = {"x": 0, "y": 0};
    has dragStartPos: any = None;
    has isBoxSelecting: bool = False;
    has boxStart: any = None;
    has boxEnd: any = None;
    has isResizing: bool = False;
    has resizeHandle: any = None;
    has resizeStartElement: any = None;

    def updateSelectedElement(val: any) -> None {
        selectedElement = val;
    }

    def updateSelectedElements(val: list) -> None {
        selectedElements = val;
        # The primary tracks the group. Without this, Ctrl+A on a fresh canvas
        # left it null and the whole style panel stayed hidden -- it only looked
        # like it worked when a shape had been clicked beforehand.
        if val and len(val) > 0 {
            selectedElement = val[0];
        } else {
            selectedElement = None;
        }
    }

    def updateIsDragging(val: bool) -> None {
        isDragging = val;
    }

    def updateDragStartPos(val: any) -> None {
        dragStartPos = val;
    }

    def updateIsResizing(val: bool) -> None {
        isResizing = val;
    }

    def updateResizeHandle(val: any) -> None {
        resizeHandle = val;
    }

    def updateResizeStartElement(val: any) -> None {
        resizeStartElement = val;
    }

    def findElementAtPoint(point: dict, elems: list) -> dict {
        i = len(elems) - 1;
        while i >= 0 {
            if isPointInElement(point, elems[i]) {
                return {"element": elems[i], "id": elems[i].id};
            }
            i = i - 1;
        }
        return None;
    }

    def startDragging(elementInfo: dict, mousePos: dict) -> None {
        selectedElement = elementInfo;
        selectedElements = [];
        isDragging = True;
        dragStartPos = mousePos;

        element = elementInfo["element"];

        elementX = 0;
        elementY = 0;

        if element.type == "freehand" and element.points and element.points.length > 0 {
            elementX = element.points[0].x;
            elementY = element.points[0].y;
        } elif element.type == "line" or element.type == "arrow" {
            elementX = element.x1;
            elementY = element.y1;
        } else {
            elementX = element.x;
            elementY = element.y;
        }

        offsetX = mousePos["x"] - elementX;
        offsetY = mousePos["y"] - elementY;

        dragOffset = {"x": offsetX, "y": offsetY};
    }

    def stopDragging() -> None {
        isDragging = False;
    }

    def stopResizing() -> None {
        isResizing = False;
        resizeHandle = None;
        resizeStartElement = None;
    }

    def clearSelection() -> None {
        selectedElement = None;
        selectedElements = [];
        isDragging = False;
        stopResizing();
    }

    def removeFromSelection(id: str) -> None {
        newList = [sel for sel in selectedElements if sel.id != id];
        selectedElements = newList;
        # Always re-point the primary. Leaving it alone when two or more remain
        # could leave it pointing at the element that was just removed.
        if len(newList) > 0 {
            selectedElement = newList[0];
        } else {
            selectedElement = None;
        }
    }

    def startBoxSelection(point: dict) -> None {
        isBoxSelecting = True;
        boxStart = point;
        boxEnd = point;
    }

    def updateBoxSelection(point: dict) -> None {
        boxEnd = point;
    }

    def finishBoxSelection(elems: list) -> None {
        if boxStart and boxEnd {
            minX = Math.min(boxStart.x, boxEnd.x);
            minY = Math.min(boxStart.y, boxEnd.y);
            maxX = Math.max(boxStart.x, boxEnd.x);
            maxY = Math.max(boxStart.y, boxEnd.y);

            selected = [];
            i = 0;
            while i < len(elems) {
                element = elems[i];
                if isElementInBox(element, minX, minY, maxX, maxY) {
                    selected.append({"element": element, "id": element.id});
                }
                i = i + 1;
            }

            selectedElements = selected;
            # Keep a primary element even for a multi-selection, exactly as
            # updateSelectedElements does. The style panel keys off this, so
            # clearing it meant rubber-band selecting two shapes made every
            # colour and stroke control vanish -- while Ctrl+A kept them.
            if len(selected) > 0 {
                selectedElement = selected[0];
            } else {
                selectedElement = None;
            }
        }

        isBoxSelecting = False;
        boxStart = None;
        boxEnd = None;
    }

    def isElementInBox(element: dict, boxMinX: float, boxMinY: float, boxMaxX: float, boxMaxY: float) -> bool {
        # Check if element's bounding box overlaps with selection box
        if element["type"] == "text" or element["type"] == "rectangle" or element["type"] == "circle" or element["type"] == "diamond" or element["type"] == "image" {
            shL = Math.min(element["x"], element["x"] + (element["width"] or 0));
            shR = Math.max(element["x"], element["x"] + (element["width"] or 0));
            shT = Math.min(element["y"], element["y"] + (element["height"] or 0));
            shB = Math.max(element["y"], element["y"] + (element["height"] or 0));
            return shL <= boxMaxX and shR >= boxMinX and shT <= boxMaxY and shB >= boxMinY;
        } elif element["type"] == "line" or element["type"] == "arrow" {
            lnL = Math.min(element["x1"], element["x2"]);
            lnR = Math.max(element["x1"], element["x2"]);
            lnT = Math.min(element["y1"], element["y2"]);
            lnB = Math.max(element["y1"], element["y2"]);
            return lnL <= boxMaxX and lnR >= boxMinX and lnT <= boxMaxY and lnB >= boxMinY;
        } elif element["type"] == "freehand" {
            if not element["points"] or element["points"].length == 0 {
                return False;
            }
            fhL = element["points"][0].x;
            fhR = element["points"][0].x;
            fhT = element["points"][0].y;
            fhB = element["points"][0].y;
            fi = 1;
            while fi < element["points"].length {
                pt = element["points"][fi];
                if pt.x < fhL { fhL = pt.x; }
                if pt.x > fhR { fhR = pt.x; }
                if pt.y < fhT { fhT = pt.y; }
                if pt.y > fhB { fhB = pt.y; }
                fi = fi + 1;
            }
            return fhL <= boxMaxX and fhR >= boxMinX and fhT <= boxMaxY and fhB >= boxMinY;
        }
        return False;
    }

    return {
        "selectedElement": selectedElement,
        "selectedElements": selectedElements,
        "isDragging": isDragging,
        "dragOffset": dragOffset,
        "dragStartPos": dragStartPos,
        "isBoxSelecting": isBoxSelecting,
        "boxStart": boxStart,
        "boxEnd": boxEnd,
        "isResizing": isResizing,
        "resizeHandle": resizeHandle,
        "resizeStartElement": resizeStartElement,
        "setSelectedElement": updateSelectedElement,
        "setSelectedElements": updateSelectedElements,
        "setIsDragging": updateIsDragging,
        "setDragStartPos": updateDragStartPos,
        "setIsResizing": updateIsResizing,
        "setResizeHandle": updateResizeHandle,
        "setResizeStartElement": updateResizeStartElement,
        "findElementAtPoint": findElementAtPoint,
        "startDragging": startDragging,
        "stopDragging": stopDragging,
        "stopResizing": stopResizing,
        "clearSelection": clearSelection,
        "removeFromSelection": removeFromSelection,
        "startBoxSelection": startBoxSelection,
        "updateBoxSelection": updateBoxSelection,
        "finishBoxSelection": finishBoxSelection
    };
}
