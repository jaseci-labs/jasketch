import from react { useState, useRef }

def:pub useElements() -> dict {
    [elements, setElementsInternal] = useState([]);
    historyRef = useRef([]);
    historyIndexRef = useRef(-1);

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

    def setElements(newElements: list) -> None {
        pushHistory(newElements);
        setElementsInternal(newElements);
    }

    def addElement(element: dict) -> None {
        newElements = elements.concat([element]);
        setElements(newElements);
    }

    def updateElement(index: int, newElement: dict) -> None {
        newElements = elements.slice();
        newElements[index] = newElement;
        setElements(newElements);
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
        setElements(newElements);
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
        setElements(newElements);
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
        setElements(newElements);
    }

    def clearElements() -> None {
        setElements([]);
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
        "setElements": setElements,
        "addElement": addElement,
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
