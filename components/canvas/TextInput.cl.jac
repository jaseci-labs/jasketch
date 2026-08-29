def:pub TextInput(
    textInput: any,
    textInputRef: any,
    onTextChange: Callable[[str], None],
    onKeyDown: Callable[[KeyboardEvent], None],
    onBlur: Callable[[], None],
    currentColor: str = "#000000",
    currentFontSize: float = 24,
    currentFontFamily: str = "Virgil",
    zoom: float = 1.0,
    panOffset: dict = {"x": 0, "y": 0}
) -> JsxElement | None {

    if not textInput {
        return None;
    }

    # Transform world coordinates to screen coordinates
    screenX = textInput.x * zoom + panOffset["x"];
    screenY = textInput.y * zoom + panOffset["y"];
    scaledFontSize = currentFontSize * zoom;

    isShapeEdit = textInput.editingShapeId != None and textInput.editingShapeId != undefined;

    baseStyle = {
        "left": screenX + "px",
        "top": screenY + "px",
        "color": currentColor,
        "fontSize": scaledFontSize + "px",
        "fontFamily": currentFontFamily,
        "lineHeight": "1.2",
        "background": "transparent",
        "border": "none",
        "padding": "0",
        "margin": "0",
        "minWidth": "4px",
        "minHeight": scaledFontSize * 1.2 + "px",
        "zIndex": "20",
        "caretColor": currentColor,
        "whiteSpace": "pre",
        "wordBreak": "keep-all"
    };

    if isShapeEdit {
        baseStyle.transform = "translate(-50%, -50%)";
        baseStyle.textAlign = "center";
    }

    return <textarea
        ref={textInputRef}
        value={textInput.text or ""}
        onChange={onTextChange}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        autoFocus={True}
        className="absolute outline-none resize-none overflow-hidden canvas-text-input"
        style={baseStyle}
    />;
}
