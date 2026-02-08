import from react { useState }
import from "..constants.canvas" { CANVAS_DEFAULTS }

def:pub useViewport() -> dict {
    canvasDefaults = CANVAS_DEFAULTS();
    [zoom, setZoom] = useState(1);
    [panOffset, setPanOffset] = useState({"x": 0, "y": 0});
    [isPanning, setIsPanning] = useState(False);

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

            setZoom(newZoom);
            setPanOffset({"x": newPanX, "y": newPanY});
        }
    }

    def handlePan(deltaX: float, deltaY: float) -> None {
        setPanOffset({
            "x": panOffset.x + deltaX,
            "y": panOffset.y + deltaY
        });
    }

    def startPanning() -> None {
        setIsPanning(True);
    }

    def stopPanning() -> None {
        setIsPanning(False);
    }

    def resetViewport() -> None {
        setZoom(1);
        setPanOffset({"x": 0, "y": 0});
    }

    def screenToWorld(screenX: float, screenY: float) -> dict {
        return {
            "x": (screenX - panOffset.x) / zoom,
            "y": (screenY - panOffset.y) / zoom
        };
    }

    def worldToScreen(worldX: float, worldY: float) -> dict {
        return {
            "x": worldX * zoom + panOffset.x,
            "y": worldY * zoom + panOffset.y
        };
    }

    return {
        "zoom": zoom,
        "panOffset": panOffset,
        "isPanning": isPanning,
        "setZoom": setZoom,
        "setPanOffset": setPanOffset,
        "setIsPanning": setIsPanning,
        "handleZoom": handleZoom,
        "handlePan": handlePan,
        "startPanning": startPanning,
        "stopPanning": stopPanning,
        "resetViewport": resetViewport,
        "screenToWorld": screenToWorld,
        "worldToScreen": worldToScreen
    };
}
