def:pub CanvasRenderer(props: dict) -> any {
    canvasRef = props.canvasRef;
    canvasSize = props.canvasSize;
    cursorClass = props.cursorClass or "cursor-crosshair";

    onClick = props.onClick;
    onDoubleClick = props.onDoubleClick;
    onMouseDown = props.onMouseDown;
    onMouseMove = props.onMouseMove;
    onMouseUp = props.onMouseUp;
    onMouseLeave = props.onMouseLeave;

    can with canvasSize entry {
        canvas = canvasRef.current;
        if canvas {
            canvas.width = canvasSize.width;
            canvas.height = canvasSize.height;
        }
    }

    return <canvas
        ref={canvasRef}
        className={"w-full h-full " + cursorClass}
        style={{
            "backgroundColor": "#ffffff",
            "display": "block"
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
