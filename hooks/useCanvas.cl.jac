import from react { useRef, useEffect, useState }
import from "..services.canvas" { drawElement, applyViewportTransform, drawSelectionBox, drawGroupSelectionBox, drawBoxSelectionRect }
import from "..constants.canvas" { CANVAS_DEFAULTS }

def:pub useCanvas() -> dict {
    canvasRef = useRef(None);
    containerRef = useRef(None);
    canvasDefaults = CANVAS_DEFAULTS();
    [canvasSize, setCanvasSize] = useState({
        "width": canvasDefaults.width,
        "height": canvasDefaults.height
    });

    def redrawCanvas(elements: list, zoom: float, panOffset: dict, selectedElement: any = None, selectedElements: list = [], isBoxSelecting: bool = False, boxStart: any = None, boxEnd: any = None, editingShapeIndex: any = None) -> None {
        canvas = canvasRef.current;
        if not canvas {
            return;
        }

        ctx = canvas.getContext("2d");

        # HiDPI fix: scale canvas for sharp rendering
        dpr = window.devicePixelRatio or 1;
        canvas.width = Math.round(canvasSize.width * dpr);
        canvas.height = Math.round(canvasSize.height * dpr);
        ctx.scale(dpr, dpr);

        ctx.save();
        applyViewportTransform(ctx, zoom, panOffset);

        drIdx = 0;
        while drIdx < elements.length {
            drEl = elements[drIdx];
            if editingShapeIndex != None and editingShapeIndex != undefined and drIdx == editingShapeIndex and drEl.shapeText {
                # Temporarily hide shapeText while editing this shape
                drCopy = Object.assign({}, drEl);
                drCopy.shapeText = None;
                drawElement(ctx, drCopy);
            } else {
                drawElement(ctx, drEl);
            }
            drIdx = drIdx + 1;
        }

        if selectedElement and selectedElement.element {
            drawSelectionBox(ctx, selectedElement.element);
        }

        if selectedElements and selectedElements.length > 0 {
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
                while gci < selectedElements.length {
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
                while gei < selectedElements.length {
                    if selectedElements[gei].element {
                        groupEls.push(selectedElements[gei].element);
                    }
                    gei = gei + 1;
                }
                drawGroupSelectionBox(ctx, groupEls);
            } else {
                # Draw individual selection boxes
                selectedElements.forEach(lambda sel: dict -> None {
                    if sel.element {
                        drawSelectionBox(ctx, sel.element);
                    }
                });
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
            setCanvasSize({
                "width": Math.round(rect.width),
                "height": Math.round(rect.height)
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
        "initializeCanvas": initializeCanvas
    };
}
