def:pub TOOLS() -> list {
    return [
        {"id": "select", "label": "Select"},
        {"id": "freehand", "label": "Pencil"},
        {"id": "line", "label": "Line"},
        {"id": "arrow", "label": "Arrow"},
        {"id": "rectangle", "label": "Rectangle"},
        {"id": "diamond", "label": "Diamond"},
        {"id": "circle", "label": "Ellipse"},
        {"id": "text", "label": "Text"}
    ];
}

def:pub TOOL_SHORTCUTS() -> dict {
    return {
        "v": "select",
        "p": "freehand",
        "l": "line",
        "a": "arrow",
        "r": "rectangle",
        "d": "diamond",
        "o": "circle",
        "t": "text"
    };
}

def:pub LINE_STYLES() -> list {
    return [
        {"id": "solid", "label": "Solid", "dash": []},
        {"id": "dashed", "label": "Dashed", "dash": [12, 6]},
        {"id": "dotted", "label": "Dotted", "dash": [3, 6]}
    ];
}
