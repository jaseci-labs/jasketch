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
        "1": "select",
        "2": "freehand",
        "3": "line",
        "4": "arrow",
        "5": "rectangle",
        "6": "diamond",
        "7": "circle",
        "8": "text"
    };
}

def:pub LINE_STYLES() -> list {
    return [
        {"id": "solid", "label": "Solid", "dash": []},
        {"id": "dashed", "label": "Dashed", "dash": [12, 6]},
        {"id": "dotted", "label": "Dotted", "dash": [3, 6]}
    ];
}
