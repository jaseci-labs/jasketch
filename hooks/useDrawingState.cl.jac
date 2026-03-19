def:pub useDrawingState() -> dict {
    has isDrawing: bool = False;
    has startPoint: any = None;
    has currentPath: list = [];

    def updateIsDrawing(val: bool) -> None {
        isDrawing = val;
    }

    def updateStartPoint(val: any) -> None {
        startPoint = val;
    }

    def updateCurrentPath(val: list) -> None {
        currentPath = val;
    }

    return {
        "isDrawing": isDrawing,
        "startPoint": startPoint,
        "currentPath": currentPath,
        "setIsDrawing": updateIsDrawing,
        "setStartPoint": updateStartPoint,
        "setCurrentPath": updateCurrentPath
    };
}
