import from react { useState }

def:pub useElements() -> dict {
    [elements, setElements] = useState([]);

    def addElement(element: dict) -> None {
        setElements(elements.concat([element]));
    }

    def updateElement(index: int, newElement: dict) -> None {
        newElements = elements.slice();
        newElements[index] = newElement;
        setElements(newElements);
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

    return {
        "elements": elements,
        "setElements": setElements,
        "addElement": addElement,
        "updateElement": updateElement,
        "updateMultipleElements": updateMultipleElements,
        "removeElement": removeElement,
        "removeMultipleElements": removeMultipleElements,
        "clearElements": clearElements
    };
}
