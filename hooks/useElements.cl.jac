import from react { useRef }

def:pub useElements() -> dict {
    has elements: list = [];
    historyRef = useRef([]);
    historyIndexRef = useRef(-1);
    loadedRef = useRef(False);

    STORAGE_KEY = "jasketch_elements";

    def setElementsInternal(newElements: list) -> None {
        elements = newElements;
        # Strip non-serializable imageObj before saving to localStorage
        toStore = newElements.map(lambda el: any -> any {
            if el.type == "image" and el.imageObj {
                return {
                    "type": el.type,
                    "x": el.x,
                    "y": el.y,
                    "width": el.width,
                    "height": el.height,
                    "src": el.src,
                    "opacity": el.opacity,
                    "groupId": el.groupId
                };
            }
            return el;
        });
        localStorage.setItem(STORAGE_KEY, JSON.stringify(toStore));
    }

    # Load from localStorage on mount
    can with entry {
        stored = localStorage.getItem(STORAGE_KEY);
        if stored {
            parsed = JSON.parse(stored);
            if parsed and parsed.length > 0 {
                elements = parsed;
                pushHistory(parsed);
            }
        }
        loadedRef.current = True;
    }

    def pushHistory(newElements: list) -> None {
        history = historyRef.current;
        idx = historyIndexRef.current;
        newHistory = history.slice(0, idx + 1);
        newHistory.push(newElements);
        if newHistory.length > 50 {
            newHistory = newHistory.slice(newHistory.length - 50);
        }
        historyRef.current = newHistory;
        historyIndexRef.current = newHistory.length - 1;
    }

    def setElementsWithHistory(newElements: list) -> None {
        pushHistory(newElements);
        setElementsInternal(newElements);
    }

    def addElement(element: dict) -> None {
        newElements = elements.concat([element]);
        setElementsWithHistory(newElements);
    }

    def addMultipleElements(newItems: list) -> None {
        newElements = elements.concat(newItems);
        setElementsWithHistory(newElements);
    }

    def updateElement(index: int, newElement: dict) -> None {
        newElements = elements.slice();
        newElements[index] = newElement;
        setElementsWithHistory(newElements);
    }

    def updateElementSilent(index: int, newElement: dict) -> None {
        newElements = elements.slice();
        newElements[index] = newElement;
        setElementsInternal(newElements);
    }

    def updateMultipleElements(updates: list) -> None {
        newElements = elements.slice();
        i = 0;
        while i < updates.length {
            newElements[updates[i].index] = updates[i].element;
            i = i + 1;
        }
        setElementsWithHistory(newElements);
    }

    def updateMultipleElementsSilent(updates: list) -> None {
        newElements = elements.slice();
        i = 0;
        while i < updates.length {
            newElements[updates[i].index] = updates[i].element;
            i = i + 1;
        }
        setElementsInternal(newElements);
    }

    def commitToHistory() -> None {
        pushHistory(elements);
    }

    def removeElement(index: int) -> None {
        newElements = elements.filter(lambda _: any, i: any -> bool {
            return i != index;
        });
        setElementsWithHistory(newElements);
    }

    def removeMultipleElements(indices: list) -> None {
        indexSet = {};
        i = 0;
        while i < indices.length {
            indexSet[indices[i]] = True;
            i = i + 1;
        }
        newElements = elements.filter(lambda _: any, i: any -> bool {
            return not indexSet[i];
        });
        setElementsWithHistory(newElements);
    }

    def clearElements() -> None {
        setElementsWithHistory([]);
    }

    def undo() -> None {
        idx = historyIndexRef.current;
        if idx > 0 {
            historyIndexRef.current = idx - 1;
            setElementsInternal(historyRef.current[idx - 1]);
        } elif idx == 0 {
            historyIndexRef.current = -1;
            setElementsInternal([]);
        }
    }

    def redo() -> None {
        idx = historyIndexRef.current;
        history = historyRef.current;
        if idx < history.length - 1 {
            historyIndexRef.current = idx + 1;
            setElementsInternal(history[idx + 1]);
        }
    }

    return {
        "elements": elements,
        "setElements": setElementsWithHistory,
        "addElement": addElement,
        "addMultipleElements": addMultipleElements,
        "updateElement": updateElement,
        "updateElementSilent": updateElementSilent,
        "updateMultipleElements": updateMultipleElements,
        "updateMultipleElementsSilent": updateMultipleElementsSilent,
        "commitToHistory": commitToHistory,
        "removeElement": removeElement,
        "removeMultipleElements": removeMultipleElements,
        "clearElements": clearElements,
        "undo": undo,
        "redo": redo
    };
}
