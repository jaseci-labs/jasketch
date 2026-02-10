def:pub CanvasRenderer(props: dict) -> JsxElement {
    canvasRef = props.canvasRef;
    canvasSize = props.canvasSize;
    cursorClass = props.cursorClass or "cursor-crosshair";

    onClick = props.onClick;
    onDoubleClick = props.onDoubleClick;
    onMouseDown = props.onMouseDown;
    onMouseMove = props.onMouseMove;
    onMouseUp = props.onMouseUp;
    onMouseLeave = props.onMouseLeave;

    return <canvas
        ref={canvasRef}
        className={"w-full h-full " + cursorClass}
        style={{
            "backgroundColor": "#ffffff",
            "display": "block",
            "width": String(canvasSize.width) + "px",
            "height": String(canvasSize.height) + "px"
        }}
        onClick={onClick}
        onDoubleClick={onDoubleClick}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
        onMouseLeave={onMouseLeave}
        onContextMenu={lambda e: any -> None {
            e.preventDefault();
        }}
    />;
}
