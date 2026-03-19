import from "..constants.canvas" { CANVAS_DEFAULTS }

def:pub useViewport() -> dict {
    canvasDefaults = CANVAS_DEFAULTS();
    has zoom: float = 1;
    has panOffset: dict = {"x": 0, "y": 0};
    has isPanning: bool = False;

    def updateZoom(val: float) -> None {
        zoom = val;
    }

    def updatePanOffset(val: dict) -> None {
        panOffset = val;
    }

    def updateIsPanning(val: bool) -> None {
        isPanning = val;
    }

    def handleZoom(deltaY: float, mouseX: float, mouseY: float, canvas: any) -> None {
        zoomFactor = 1;
        if deltaY > 0 {
            zoomFactor = 0.9;
        } else {
            zoomFactor = 1.1;
        }

        newZoom = zoom * zoomFactor;
        if newZoom >= canvasDefaults.minZoom and newZoom <= canvasDefaults.maxZoom {
            rect = canvas.getBoundingClientRect();
            canvasX = mouseX - rect.left;
            canvasY = mouseY - rect.top;

            worldX = (canvasX - panOffset.x) / zoom;
            worldY = (canvasY - panOffset.y) / zoom;

            newPanX = canvasX - worldX * newZoom;
            newPanY = canvasY - worldY * newZoom;

            zoom = newZoom;
            panOffset = {"x": newPanX, "y": newPanY};
        }
    }

    def handlePan(deltaX: float, deltaY: float) -> None {
        panOffset = {
            "x": panOffset.x + deltaX,
            "y": panOffset.y + deltaY
        };
    }

    def startPanning() -> None {
        isPanning = True;
    }

    def stopPanning() -> None {
        isPanning = False;
    }

    return {
        "zoom": zoom,
        "panOffset": panOffset,
        "isPanning": isPanning,
        "setZoom": updateZoom,
        "setPanOffset": updatePanOffset,
        "setIsPanning": updateIsPanning,
        "handleZoom": handleZoom,
        "handlePan": handlePan,
        "startPanning": startPanning,
        "stopPanning": stopPanning
    };
}
