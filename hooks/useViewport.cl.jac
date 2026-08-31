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

            worldX = (canvasX - panOffset["x"]) / zoom;
            worldY = (canvasY - panOffset["y"]) / zoom;

            newPanX = canvasX - worldX * newZoom;
            newPanY = canvasY - worldY * newZoom;

            zoom = newZoom;
            panOffset = {"x": newPanX, "y": newPanY};
        }
    }

    def handlePan(deltaX: float, deltaY: float) -> None {
        panOffset = {
            "x": panOffset["x"] + deltaX,
            "y": panOffset["y"] + deltaY
        };
    }

    def startPanning() -> None {
        isPanning = True;
    }

    def stopPanning() -> None {
        isPanning = False;
    }

    """Frame every element with a margin. No-op on an empty canvas.

    Without this, finding work you have scrolled away from means hunting with
    the scroll wheel -- the canvas is infinite, so there is no edge to hit."""
    def zoomToFit(bounds: any, canvasWidth: float, canvasHeight: float) -> None {
        if not bounds or not canvasWidth or not canvasHeight {
            return;
        }
        margin = 80.0;
        bw = Math.max(bounds["width"], 1.0);
        bh = Math.max(bounds["height"], 1.0);
        # Never zoom past 100% on fit: blowing a single small shape up to fill
        # the screen is disorienting rather than helpful.
        next_zoom = Math.min(
            Math.min((canvasWidth - margin * 2) / bw, (canvasHeight - margin * 2) / bh),
            1.0
        );
        next_zoom = Math.max(next_zoom, 0.1);
        updateZoom(next_zoom);
        updatePanOffset({
            "x": canvasWidth / 2 - (bounds["x"] + bw / 2) * next_zoom,
            "y": canvasHeight / 2 - (bounds["y"] + bh / 2) * next_zoom
        });
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
        "stopPanning": stopPanning,
        "zoomToFit": zoomToFit
    };
}
