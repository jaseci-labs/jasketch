def:pub TOOLS() -> list {
    return [
        {"id": "select", "label": "Select"},
        {"id": "freehand", "label": "Pencil"},
        {"id": "line", "label": "Line"},
        {"id": "arrow", "label": "Arrow"},
        {"id": "rectangle", "label": "Rectangle"},
        {"id": "diamond", "label": "Diamond"},
        {"id": "circle", "label": "Ellipse"},
        {"id": "text", "label": "Text"},
        {"id": "image", "label": "Image"}
    ];
}

"""Single-key tool shortcuts.

Two spellings reach every tool. The digits are JaSketch's own, in toolbar
order, and are unchanged. The letters are Excalidraw's, matched exactly --
V select, R rectangle, D diamond, O ellipse, A arrow, L line, P pencil,
T text -- because a letter that lands on a DIFFERENT tool than the one the
user's hand expects is worse than no letter at all. Before this, none of the
letters did anything."""
def:pub TOOL_SHORTCUTS() -> dict {
    return {
        "1": "select",     "v": "select",
        "2": "freehand",   "p": "freehand",
        "3": "line",       "l": "line",
        "4": "arrow",      "a": "arrow",
        "5": "rectangle",  "r": "rectangle",
        "6": "diamond",    "d": "diamond",
        "7": "circle",     "o": "circle",
        "8": "text",       "t": "text"
    };
}

def:pub LINE_STYLES() -> list {
    return [
        {"id": "solid", "label": "Solid", "dash": []},
        {"id": "dashed", "label": "Dashed", "dash": [12, 6]},
        {"id": "dotted", "label": "Dotted", "dash": [3, 6]}
    ];
}

def:pub CURVE_STYLES() -> list {
    return [
        {"id": "sharp", "label": "Sharp"},
        {"id": "curved", "label": "Curved"},
        {"id": "elbow", "label": "Elbow"}
    ];
}
