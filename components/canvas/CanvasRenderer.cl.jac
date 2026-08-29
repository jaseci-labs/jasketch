def:pub CanvasRenderer(
    canvasRef: any,
    canvasSize: dict,
    onClick: Callable[[MouseEvent], None],
    onDoubleClick: Callable[[MouseEvent], None],
    onMouseDown: Callable[[MouseEvent], None],
    onMouseMove: Callable[[MouseEvent], None],
    onMouseUp: Callable[[MouseEvent], None],
    onMouseLeave: Callable[[MouseEvent], None],
    cursorClass: str = "cursor-crosshair"
) -> JsxElement {

    return <canvas
        ref={canvasRef}
        className={"w-full h-full " + cursorClass}
        style={{
            "backgroundColor": "#ffffff",
            "display": "block",
            "width": str(canvasSize["width"]) + "px",
            "height": str(canvasSize["height"]) + "px"
        }}
        onClick={onClick}
        onDoubleClick={onDoubleClick}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
        onMouseLeave={onMouseLeave}
        onContextMenu={lambda (e: any) {
            e.preventDefault();
        }}
    />;
}
