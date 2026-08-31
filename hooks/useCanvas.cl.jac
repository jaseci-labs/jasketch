import from react { useRef, useEffect }
import from "..services.canvas" { drawElement, applyViewportTransform, drawSelectionBox, drawGroupSelectionBox, drawBoxSelectionRect }
import from "..constants.canvas" { CANVAS_DEFAULTS }

def:pub useCanvas() -> dict {
    canvasRef = useRef(None);
    containerRef = useRef(None);
    canvasDefaults = CANVAS_DEFAULTS();
    has canvasSize: dict = {
        "width": canvasDefaults.width,
        "height": canvasDefaults.height
    };

    def updateCanvasSize(val: dict) -> None {
        canvasSize = val;
    }

    def redrawCanvas(elements: list, zoom: float, panOffset: dict, selectedElement: any = None, selectedElements: list = [], isBoxSelecting: bool = False, boxStart: any = None, boxEnd: any = None, editingShapeId: any = None) -> None {
        canvas = canvasRef.current;
        if not canvas {
            return;
        }

        ctx = canvas.getContext("2d");

        # HiDPI fix: scale canvas for sharp rendering
        dpr = window.devicePixelRatio or 1;
        canvas.width = Math.round(canvasSize["width"] * dpr);
        canvas.height = Math.round(canvasSize["height"] * dpr);
        ctx.scale(dpr, dpr);

        ctx.save();
        applyViewportTransform(ctx, zoom, panOffset);

        # Callback to redraw canvas when an image finishes loading
        imgLoadRedraw = lambda {
            redrawCanvas(elements, zoom, panOffset, selectedElement, selectedElements, isBoxSelecting, boxStart, boxEnd, editingShapeId);
        };

        drIdx = 0;
        while drIdx < len(elements) {
            drEl = elements[drIdx];
            if editingShapeId != None and editingShapeId != undefined and drEl.id == editingShapeId and drEl.shapeText {
                # Temporarily hide shapeText while editing this shape
                drCopy = {**drEl};
                drCopy.shapeText = None;
                drawElement(ctx, drCopy, imgLoadRedraw);
            } else {
                drawElement(ctx, drEl, imgLoadRedraw);
            }
            drIdx = drIdx + 1;
        }

        if selectedElement and selectedElement.element {
            drawSelectionBox(ctx, selectedElement.element);
        }

        if selectedElements and len(selectedElements) > 0 {
            # Check if all selected elements share the same groupId
            allGrouped = True;
            sharedGroupId = None;
            if selectedElements[0].element and selectedElements[0].element.groupId {
                sharedGroupId = selectedElements[0].element.groupId;
            } else {
                allGrouped = False;
            }
            if allGrouped {
                gci = 1;
                while gci < len(selectedElements) {
                    if not selectedElements[gci].element or selectedElements[gci].element.groupId != sharedGroupId {
                        allGrouped = False;
                    }
                    gci = gci + 1;
                }
            }
            if allGrouped and sharedGroupId {
                # Draw single combined selection box for group
                groupEls = [];
                gei = 0;
                while gei < len(selectedElements) {
                    if selectedElements[gei].element {
                        groupEls.append(selectedElements[gei].element);
                    }
                    gei = gei + 1;
                }
                drawGroupSelectionBox(ctx, groupEls);
            } else {
                # Draw individual selection boxes
                selBoxIdx = 0;
                while selBoxIdx < len(selectedElements) {
                    if selectedElements[selBoxIdx].element {
                        drawSelectionBox(ctx, selectedElements[selBoxIdx].element);
                    }
                    selBoxIdx = selBoxIdx + 1;
                }
            }
        }

        if isBoxSelecting and boxStart and boxEnd {
            drawBoxSelectionRect(ctx, boxStart, boxEnd);
        }

        ctx.restore();
    }

    def initializeCanvas() -> None {
        if containerRef.current {
            rect = containerRef.current.getBoundingClientRect();
            canvasSize = {
                "width": Math.round(rect.width),
                "height": Math.round(rect.height)
            };
        }
    }

    def handleResize() -> None {
        initializeCanvas();
    }

    # Acquire-and-release in ONE effect: `can with entry`/`can with exit` compile
    # to separate useEffect closures, so the listener added on mount would never
    # be the one removed on unmount.
    useEffect(lambda () -> any {
        handleResize();
        window.addEventListener("resize", handleResize);
        # The window is not the only thing that resizes the canvas: folding the
        # inspector away changes the container without any window event at all,
        # and the drawing surface kept its old width until something else
        # happened to trigger a redraw.
        watcher = None;
        if containerRef.current and window.ResizeObserver {
            watcher = new(ResizeObserver, lambda { handleResize(); });
            watcher.observe(containerRef.current);
        }
        return lambda {
            window.removeEventListener("resize", handleResize);
            if watcher {
                watcher.disconnect();
            }
        };
    }, []);

    return {
        "canvasRef": canvasRef,
        "containerRef": containerRef,
        "canvasSize": canvasSize,
        "setCanvasSize": updateCanvasSize,
        "redrawCanvas": redrawCanvas,
        "initializeCanvas": initializeCanvas
    };
}
