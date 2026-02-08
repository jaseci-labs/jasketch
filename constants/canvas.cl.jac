def:pub CANVAS_DEFAULTS() -> dict {
    return {
        "width": 2000,
        "height": 1500,
        "backgroundColor": "#ffffff",
        "minZoom": 0.1,
        "maxZoom": 5.0,
        "zoomFactor": 0.1
    };
}

def:pub STROKE_WIDTHS() -> list {
    return [1, 2, 4, 6, 10];
}

def:pub DEFAULT_TOOL_SETTINGS() -> dict {
    return {
        "currentTool": "freehand",
        "currentColor": "#1e1e1e",
        "currentStrokeWidth": 2,
        "currentFontSize": 24,
        "currentFontFamily": "Inter"
    };
}
