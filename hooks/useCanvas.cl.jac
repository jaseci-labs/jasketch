import from react { useRef, useEffect, useState }
import from "..services.canvas" { drawElement, clearCanvas, applyViewportTransform, drawSelectionBox, drawBoxSelectionRect }
import from "..constants.canvas" { CANVAS_DEFAULTS }

def:pub useCanvas() -> dict {
    canvasRef = useRef(None);
    containerRef = useRef(None);
    canvasDefaults = CANVAS_DEFAULTS();
    [canvasSize, setCanvasSize] = useState({
        "width": canvasDefaults.width,
        "height": canvasDefaults.height
    });

    def redrawCanvas(elements: list, zoom: float, panOffset: dict, selectedElement: any = None, selectedElements: list = [], isBoxSelecting: bool = False, boxStart: any = None, boxEnd: any = None) -> None {
        canvas = canvasRef.current;
        if not canvas {
            return;
        }

        ctx = canvas.getContext("2d");
        clearCanvas(ctx, canvas.width, canvas.height);

        ctx.save();
        applyViewportTransform(ctx, zoom, panOffset);

        elements.forEach(lambda element: any -> None {
            drawElement(ctx, element);
        });

        if selectedElement and selectedElement.element {
            drawSelectionBox(ctx, selectedElement.element);
        }

        if selectedElements and selectedElements.length > 0 {
            selectedElements.forEach(lambda sel: dict -> None {
                if sel.element {
                    drawSelectionBox(ctx, sel.element);
                }
            });
        }

        if isBoxSelecting and boxStart and boxEnd {
            drawBoxSelectionRect(ctx, boxStart, boxEnd);
        }

        ctx.restore();
    }

    def getContext() -> any {
        canvas = canvasRef.current;
        if canvas {
            return canvas.getContext("2d");
        }
        return None;
    }

    def initializeCanvas() -> None {
        if containerRef.current {
            rect = containerRef.current.getBoundingClientRect();
            setCanvasSize({
                "width": rect.width,
                "height": rect.height
            });
        }
    }

    useEffect(lambda -> None {
        def handleResize() -> None {
            initializeCanvas();
        }

        handleResize();
        window.addEventListener("resize", handleResize);
        return lambda -> None {
            window.removeEventListener("resize", handleResize);
        };
    }, []);

    return {
        "canvasRef": canvasRef,
        "containerRef": containerRef,
        "canvasSize": canvasSize,
        "setCanvasSize": setCanvasSize,
        "redrawCanvas": redrawCanvas,
        "getContext": getContext,
        "initializeCanvas": initializeCanvas
    };
}
