import from react { useState }

def:pub useTextInput() -> dict {
    [textInput, setTextInput] = useState(None);

    def startTextInput(x: float, y: float, initialText: str = "") -> None {
        setTextInput({
            "x": x,
            "y": y,
            "text": initialText
        });
    }

    def updateTextContent(text: str) -> None {
        if textInput {
            setTextInput({
                "x": textInput.x,
                "y": textInput.y,
                "text": text
            });
        }
    }

    def cancelTextInput() -> None {
        setTextInput(None);
    }

    def hasContent() -> bool {
        return textInput and textInput.text and textInput.text.trim() != "";
    }

    return {
        "textInput": textInput,
        "setTextInput": setTextInput,
        "startTextInput": startTextInput,
        "updateTextContent": updateTextContent,
        "cancelTextInput": cancelTextInput,
        "hasContent": hasContent
    };
}
