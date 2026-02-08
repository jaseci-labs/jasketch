def:pub TextInput(props: dict) -> any {
    textInput = props.textInput;
    textInputRef = props.textInputRef;
    currentColor = props.currentColor or "#000000";
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Virgil";
    onTextChange = props.onTextChange;
    onKeyDown = props.onKeyDown;
    onBlur = props.onBlur;

    if not textInput {
        return None;
    }

    return <textarea
        ref={textInputRef}
        value={textInput.text or ""}
        onChange={onTextChange}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        className="absolute bg-transparent border-2 rounded-lg p-2 outline-none resize-none"
        style={{
            "left": (textInput.x or 0) + "px",
            "top": (textInput.y or 0) + "px",
            "color": currentColor,
            "fontSize": currentFontSize + "px",
            "fontFamily": currentFontFamily,
            "borderColor": "#8b5cf6",
            "minWidth": "100px",
            "minHeight": "40px",
            "zIndex": "10"
        }}
        placeholder="Type here..."
    />;
}
