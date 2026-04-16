import from react { useRef }

def:pub useElements() -> dict {
    has elements: list = [];
    historyRef = useRef([]);
    historyIndexRef = useRef(-1);
    loadedRef = useRef(False);
    elementsRef = useRef([]);

    STORAGE_KEY = "jasketch_elements";

    def setElementsInternal(newElements: list) -> None {
        elements = newElements;
        elementsRef.current = newElements;
        # Strip non-serializable imageObj before saving to localStorage
        toStore = [
            el.type == "image" and el.imageObj and {
                "type": el.type, "x": el.x, "y": el.y,
                "width": el.width, "height": el.height,
                "src": el.src, "opacity": el.opacity, "groupId": el.groupId
            } or el
            for el in newElements
        ];
        localStorage.setItem(STORAGE_KEY, JSON.stringify(toStore));
    }

    # Load from localStorage on mount
    can with entry {
        stored = localStorage.getItem(STORAGE_KEY);
        if stored {
            parsed = JSON.parse(stored);
            if parsed and parsed.length > 0 {
                mi = 0;
                while mi < parsed.length {
                    if not parsed[mi].id {
                        parsed[mi].id = crypto.randomUUID();
                    }
                    mi = mi + 1;
                }
                elements = parsed;
                elementsRef.current = parsed;
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
        if not element.id {
            element.id = crypto.randomUUID();
        }
        newElements = elements.concat([element]);
        setElementsWithHistory(newElements);
    }

    def addMultipleElements(newItems: list) -> None {
        ni = 0;
        while ni < newItems.length {
            if not newItems[ni].id {
                newItems[ni].id = crypto.randomUUID();
            }
            ni = ni + 1;
        }
        newElements = elements.concat(newItems);
        setElementsWithHistory(newElements);
    }

    def _findIndex(id: str) -> int {
        fi = 0;
        while fi < elements.length {
            if elements[fi] and elements[fi].id == id {
                return fi;
            }
            fi = fi + 1;
        }
        return -1;
    }

    def updateElement(id: str, newElement: dict) -> None {
        idx = _findIndex(id);
        if idx >= 0 {
            newElements = elements.slice();
            newElements[idx] = newElement;
            setElementsWithHistory(newElements);
        }
    }

    def updateElementSilent(id: str, newElement: dict) -> None {
        idx = _findIndex(id);
        if idx >= 0 {
            newElements = elements.slice();
            newElements[idx] = newElement;
            setElementsInternal(newElements);
        }
    }

    def updateMultipleElements(updates: list) -> None {
        newElements = elements.slice();
        i = 0;
        while i < updates.length {
            idx = _findIndex(updates[i].id);
            if idx >= 0 {
                newElements[idx] = updates[i].element;
            }
            i = i + 1;
        }
        setElementsWithHistory(newElements);
    }

    def updateMultipleElementsSilent(updates: list) -> None {
        newElements = elements.slice();
        i = 0;
        while i < updates.length {
            idx = _findIndex(updates[i].id);
            if idx >= 0 {
                newElements[idx] = updates[i].element;
            }
            i = i + 1;
        }
        setElementsInternal(newElements);
    }

    def commitToHistory() -> None {
        pushHistory(elements);
    }

    def removeElement(id: str) -> None {
        newElements = [];
        ri = 0;
        while ri < elements.length {
            if elements[ri] and elements[ri].id != id {
                newElements.push(elements[ri]);
            }
            ri = ri + 1;
        }
        setElementsWithHistory(newElements);
    }

    def removeMultipleElements(ids: list) -> None {
        idSet = {};
        i = 0;
        while i < ids.length {
            idSet[ids[i]] = True;
            i = i + 1;
        }
        newElements = [];
        rmi = 0;
        while rmi < elements.length {
            if elements[rmi] and not idSet[elements[rmi].id] {
                newElements.push(elements[rmi]);
            }
            rmi = rmi + 1;
        }
        setElementsWithHistory(newElements);
    }

    def clearElements() -> None {
        setElementsWithHistory([]);
    }

    def setElementsReplaceAll(newElements: list) -> None {
        # Add IDs to any elements missing them
        i = 0;
        while i < newElements.length {
            if not newElements[i].id {
                newElements[i].id = crypto.randomUUID();
            }
            i = i + 1;
        }
        # Replace all elements and push to history
        setElementsWithHistory(newElements);
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
        "elementsRef": elementsRef,
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
        "setElementsReplaceAll": setElementsReplaceAll,
        "undo": undo,
        "redo": redo
    };
}
