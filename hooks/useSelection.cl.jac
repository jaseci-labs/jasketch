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
            } elif selected.length == 0 {
                setSelectedElement(None);
            } else {
                setSelectedElement(None);
            }
        }

        setIsBoxSelecting(False);
        setBoxStart(None);
        setBoxEnd(None);
    }

    def isElementInBox(element: dict, minX: float, minY: float, maxX: float, maxY: float) -> bool {
        if element.type == "text" or element.type == "rectangle" or element.type == "circle" {
            elemX = element.x;
            elemY = element.y;
            return elemX >= minX and elemX <= maxX and elemY >= minY and elemY <= maxY;
        } elif element.type == "line" or element.type == "arrow" {
            x1InBox = element.x1 >= minX and element.x1 <= maxX and element.y1 >= minY and element.y1 <= maxY;
            x2InBox = element.x2 >= minX and element.x2 <= maxX and element.y2 >= minY and element.y2 <= maxY;
            return x1InBox or x2InBox;
        } elif element.type == "freehand" {
            i = 0;
            while i < element.points.length {
                point = element.points[i];
                if point.x >= minX and point.x <= maxX and point.y >= minY and point.y <= maxY {
                    return True;
                }
                i = i + 1;
            }
            return False;
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
        "startBoxSelection": startBoxSelection,
        "updateBoxSelection": updateBoxSelection,
        "finishBoxSelection": finishBoxSelection
    };
}
