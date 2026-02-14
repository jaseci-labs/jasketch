import from react { useState }
import from "..services.collision" { isPointInElement }

def:pub useSelection() -> dict {
    [selectedElement, setSelectedElement] = useState(None);
    [selectedElements, setSelectedElements] = useState([]);
    [isDragging, setIsDragging] = useState(False);
    [dragOffset, setDragOffset] = useState({"x": 0, "y": 0});
    [dragStartPos, setDragStartPos] = useState(None);
    [isBoxSelecting, setIsBoxSelecting] = useState(False);
    [boxStart, setBoxStart] = useState(None);
    [boxEnd, setBoxEnd] = useState(None);
    [isResizing, setIsResizing] = useState(False);
    [resizeHandle, setResizeHandle] = useState(None);
    [resizeStartElement, setResizeStartElement] = useState(None);

    def findElementAtPoint(point: dict, elements: list) -> dict {
        i = elements.length - 1;
        while i >= 0 {
            if isPointInElement(point, elements[i]) {
                return {"element": elements[i], "index": i};
            }
            i = i - 1;
        }
        return None;
    }

    def startDragging(elementInfo: dict, mousePos: dict) -> None {
        setSelectedElement(elementInfo);
        setSelectedElements([]);
        setIsDragging(True);
        setDragStartPos(mousePos);

        element = elementInfo.element;

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

        offsetX = mousePos.x - elementX;
        offsetY = mousePos.y - elementY;

        setDragOffset({"x": offsetX, "y": offsetY});
    }

    def stopDragging() -> None {
        setIsDragging(False);
    }

    def stopResizing() -> None {
        setIsResizing(False);
        setResizeHandle(None);
        setResizeStartElement(None);
    }

    def clearSelection() -> None {
        setSelectedElement(None);
        setSelectedElements([]);
        setIsDragging(False);
        stopResizing();
    }

    def addToSelection(elementInfo: dict) -> None {
        newList = selectedElements.slice();
        newList.push(elementInfo);
        setSelectedElements(newList);
        setSelectedElement(None);
    }

    def removeFromSelection(index: int) -> None {
        newList = selectedElements.filter(lambda sel: dict -> bool {
            return sel.index != index;
        });
        setSelectedElements(newList);
        if newList.length == 1 {
            setSelectedElement(newList[0]);
        } elif newList.length == 0 {
            setSelectedElement(None);
        }
    }

    def startBoxSelection(point: dict) -> None {
        setIsBoxSelecting(True);
        setBoxStart(point);
        setBoxEnd(point);
    }

    def updateBoxSelection(point: dict) -> None {
        setBoxEnd(point);
    }

    def finishBoxSelection(elements: list) -> None {
        if boxStart and boxEnd {
            minX = Math.min(boxStart.x, boxEnd.x);
            minY = Math.min(boxStart.y, boxEnd.y);
            maxX = Math.max(boxStart.x, boxEnd.x);
            maxY = Math.max(boxStart.y, boxEnd.y);

            selected = [];
            i = 0;
            while i < elements.length {
                element = elements[i];
                if isElementInBox(element, minX, minY, maxX, maxY) {
                    selected.push({"element": element, "index": i});
                }
                i = i + 1;
            }

            setSelectedElements(selected);
            if selected.length == 1 {
                setSelectedElement(selected[0]);
            } else {
                setSelectedElement(None);
            }
        }

        setIsBoxSelecting(False);
        setBoxStart(None);
        setBoxEnd(None);
    }

    def isElementInBox(element: dict, boxMinX: float, boxMinY: float, boxMaxX: float, boxMaxY: float) -> bool {
        # Check if element's bounding box overlaps with selection box
        if element.type == "text" or element.type == "rectangle" or element.type == "circle" or element.type == "diamond" or element.type == "image" {
            shL = Math.min(element.x, element.x + (element.width or 0));
            shR = Math.max(element.x, element.x + (element.width or 0));
            shT = Math.min(element.y, element.y + (element.height or 0));
            shB = Math.max(element.y, element.y + (element.height or 0));
            return shL <= boxMaxX and shR >= boxMinX and shT <= boxMaxY and shB >= boxMinY;
        } elif element.type == "line" or element.type == "arrow" {
            lnL = Math.min(element.x1, element.x2);
            lnR = Math.max(element.x1, element.x2);
            lnT = Math.min(element.y1, element.y2);
            lnB = Math.max(element.y1, element.y2);
            return lnL <= boxMaxX and lnR >= boxMinX and lnT <= boxMaxY and lnB >= boxMinY;
        } elif element.type == "freehand" {
            if not element.points or element.points.length == 0 {
                return False;
            }
            fhL = element.points[0].x;
            fhR = element.points[0].x;
            fhT = element.points[0].y;
            fhB = element.points[0].y;
            fi = 1;
            while fi < element.points.length {
                pt = element.points[fi];
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
        "setSelectedElement": setSelectedElement,
        "setSelectedElements": setSelectedElements,
        "setIsDragging": setIsDragging,
        "setDragStartPos": setDragStartPos,
        "setIsResizing": setIsResizing,
        "setResizeHandle": setResizeHandle,
        "setResizeStartElement": setResizeStartElement,
        "findElementAtPoint": findElementAtPoint,
        "startDragging": startDragging,
        "stopDragging": stopDragging,
        "stopResizing": stopResizing,
        "clearSelection": clearSelection,
        "addToSelection": addToSelection,
        "removeFromSelection": removeFromSelection,
        "startBoxSelection": startBoxSelection,
        "updateBoxSelection": updateBoxSelection,
        "finishBoxSelection": finishBoxSelection
    };
}
