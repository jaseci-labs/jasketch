import from react { useEffect }
import from "...services.canvas" { measure_widest_line }

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

        # Wrap to the shape, exactly as the rendered label wraps. With
        # white-space:pre the words ran off the side and overflow:hidden clipped
        # them, so while typing a long label you could not see what you were
        # writing -- the text only became visible once you committed it.
        # 10px each side, matching SHAPE_TEXT_PADDING in services/canvas.
        shapeEl = textInput.editingShapeElement;
        if shapeEl and shapeEl.width {
            innerW = (Math.abs(shapeEl.width) - 20) * zoom;
            if innerW < 20 * zoom {
                innerW = 20 * zoom;
            }
            baseStyle.width = innerW + "px";
        } elif shapeEl and shapeEl.x1 != None and shapeEl.x1 != undefined {
            # A connector has no width; wrap to a share of its length, matching
            # drawLineLabel so the editor and the result agree.
            span = Math.sqrt(
                Math.pow(shapeEl.x2 - shapeEl.x1, 2) + Math.pow(shapeEl.y2 - shapeEl.y1, 2)
            );
            baseStyle.width = Math.max(150.0, span * 0.9) * zoom + "px";
        }
        baseStyle.whiteSpace = "pre-wrap";
        baseStyle.wordBreak = "break-word";
        baseStyle.overflow = "hidden";
    }

    # Grow the box to its content on every keystroke, so a label that wraps onto
    # a third line does not disappear under a fixed height.
    def growToContent() -> None {
        # Not `node`: that is an Object-Spatial keyword in Jac and will not parse
        # as a variable name.
        box = textInputRef.current;
        if not box {
            return;
        }

        # This used to run only for shape labels. Free canvas text got no
        # growth at all, and a bare <textarea> defaults to rows=2, so the
        # third line pushed the first out of sight behind overflow:hidden.
        # The text was never lost, it just could not be seen until commit.
        box.style.height = "auto";
        box.style.height = box.scrollHeight + "px";

        # Shape labels wrap to a width set from the shape, so they only ever
        # need to grow downward. Free text is white-space:pre and never wraps,
        # so it has to grow sideways too or a long line scrolls its own start
        # off the left. Collapse to 0 first so the box also shrinks back when
        # text is deleted, instead of sticking at the cols=20 default.
        if not isShapeEdit {
            # Measured with a canvas rather than read off the element:
            # a <textarea>'s scrollWidth reports the box's own width, not its
            # content, so it can grow a box but can never shrink one back.
            widest = measure_widest_line(
                textInput.text or "", scaledFontSize, currentFontFamily
            );
            # A little slack so the caret at the end of the longest line is
            # not sitting on the clipped edge.
            box.style.width = (widest + scaledFontSize * 0.4 + 4) + "px";
        }
    }

    useEffect(growToContent);

    return <textarea
        ref={textInputRef}
        value={textInput.text or ""}
        onChange={onTextChange}
        onKeyDown={onKeyDown}
        onBlur={onBlur}
        autoFocus={True}
        wrap={"soft" if isShapeEdit else "off"}
        spellCheck={False}
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        className="absolute outline-none resize-none overflow-hidden canvas-text-input"
        style={baseStyle}
    />;
}
