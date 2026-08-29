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
            if parsed and len(parsed) > 0 {
                mi = 0;
                while mi < len(parsed) {
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

    """The element list as it stands RIGHT NOW.

    `elements` is React state and only changes at the next render, so two
    mutations inside one tick both built on the same stale list and the second
    silently discarded the first. Drawing quickly dropped shapes, nudging a
    multi-selection moved one element, restyling recoloured one shape, and
    bring-to-front cancelled itself out -- all the same bug wearing different
    clothes. `elementsRef` is written synchronously in setElementsInternal, so
    it is always current."""
    def _live() -> list {
        return elementsRef.current or elements;
    }

    def setElementsWithHistory(newElements: list) -> None {
        pushHistory(newElements);
        setElementsInternal(newElements);
    }

    def addElement(element: dict) -> None {
        if not element["id"] {
            element["id"] = crypto.randomUUID();
        }
        newElements = _live() + [element];
        setElementsWithHistory(newElements);
    }

    def addMultipleElements(newItems: list) -> None {
        ni = 0;
        while ni < len(newItems) {
            if not newItems[ni].id {
                newItems[ni].id = crypto.randomUUID();
            }
            ni = ni + 1;
        }
        newElements = _live() + newItems;
        setElementsWithHistory(newElements);
    }

    def _findIndex(id: str) -> int {
        fi = 0;
        scan = _live();
        while fi < len(scan) {
            if scan[fi] and scan[fi].id == id {
                return fi;
            }
            fi = fi + 1;
        }
        return -1;
    }

    def updateElement(id: str, newElement: dict) -> None {
        idx = _findIndex(id);
        if idx >= 0 {
            newElements = _live()[:];
            newElements[idx] = newElement;
            setElementsWithHistory(newElements);
        }
    }

    def updateElementSilent(id: str, newElement: dict) -> None {
        idx = _findIndex(id);
        if idx >= 0 {
            newElements = _live()[:];
            newElements[idx] = newElement;
            setElementsInternal(newElements);
        }
    }

    def updateMultipleElements(updates: list) -> None {
        newElements = _live()[:];
        i = 0;
        while i < len(updates) {
            idx = _findIndex(updates[i].id);
            if idx >= 0 {
                newElements[idx] = updates[i].element;
            }
            i = i + 1;
        }
        setElementsWithHistory(newElements);
    }

    def updateMultipleElementsSilent(updates: list) -> None {
        newElements = _live()[:];
        i = 0;
        while i < len(updates) {
            idx = _findIndex(updates[i].id);
            if idx >= 0 {
                newElements[idx] = updates[i].element;
            }
            i = i + 1;
        }
        setElementsInternal(newElements);
    }

    def commitToHistory() -> None {
        pushHistory(_live());
    }

    def removeElement(id: str) -> None {
        newElements = [];
        ri = 0;
        keep = _live();
        while ri < len(keep) {
            if keep[ri] and keep[ri].id != id {
                newElements.append(keep[ri]);
            }
            ri = ri + 1;
        }
        setElementsWithHistory(newElements);
    }

    def removeMultipleElements(ids: list) -> None {
        idSet = {};
        i = 0;
        while i < len(ids) {
            idSet[ids[i]] = True;
            i = i + 1;
        }
        newElements = [];
        rmi = 0;
        pool = _live();
        while rmi < len(pool) {
            if pool[rmi] and not idSet[pool[rmi].id] {
                newElements.append(pool[rmi]);
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
        while i < len(newElements) {
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
