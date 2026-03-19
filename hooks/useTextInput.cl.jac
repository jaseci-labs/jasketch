def:pub useTextInput() -> dict {
    has textInput: any = None;

    def startTextInput(x: float, y: float, initialText: str, shapeIndex: any, shapeElement: any) -> None {
        textInput = {
            "x": x,
            "y": y,
            "text": initialText or "",
            "editingShapeIndex": shapeIndex,
            "editingShapeElement": shapeElement
        };
    }

    def updateTextContent(text: str) -> None {
        if textInput {
            textInput = {
                "x": textInput.x,
                "y": textInput.y,
                "text": text,
                "editingShapeIndex": textInput.editingShapeIndex,
                "editingShapeElement": textInput.editingShapeElement
            };
        }
    }

    def cancelTextInput() -> None {
        textInput = None;
    }

    def hasContent() -> bool {
        return textInput and textInput.text and textInput.text.trim() != "";
    }

    return {
        "textInput": textInput,
        "startTextInput": startTextInput,
        "updateTextContent": updateTextContent,
        "cancelTextInput": cancelTextInput,
        "hasContent": hasContent
    };
}
