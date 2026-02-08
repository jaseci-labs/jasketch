import from react { useState }

def:pub useDrawingState() -> dict {
    [isDrawing, setIsDrawing] = useState(False);
    [startPoint, setStartPoint] = useState(None);
    [currentPath, setCurrentPath] = useState([]);

    return {
        "isDrawing": isDrawing,
        "startPoint": startPoint,
        "currentPath": currentPath,
        "setIsDrawing": setIsDrawing,
        "setStartPoint": setStartPoint,
        "setCurrentPath": setCurrentPath
    };
}
