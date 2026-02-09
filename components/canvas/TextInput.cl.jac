def:pub TextInput(props: dict) -> any {
    textInput = props.textInput;
    textInputRef = props.textInputRef;
    currentColor = props.currentColor or "#000000";
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Virgil";
    zoom = props.zoom or 1;
    panOffset = props.panOffset or {"x": 0, "y": 0};
    onTextChange = props.onTextChange;
    onKeyDown = props.onKeyDown;
    onBlur = props.onBlur;

    if not textInput {
        return None;
    }

    # Transform world coordinates to screen coordinates
    screenX = textInput.x * zoom + panOffset.x;
    screenY = textInput.y * zoom + panOffset.y;
    scaledFontSize = currentFontSize * zoom;

    return <textarea
        ref={textInputRef}
        value={textInput.text or ""}
        onChange={onTextChange}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        autoFocus={True}
        className="absolute outline-none resize-none overflow-hidden canvas-text-input"
        style={{
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
        }}
    />;
}
