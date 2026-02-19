def:pub ContextMenu(props: dict) -> JsxElement {
    visible = props.visible or False;
    x = props.x or 0;
    y = props.y or 0;
    onClose = props.onClose;
    onDelete = props.onDelete;
    onDuplicate = props.onDuplicate;
    onBringToFront = props.onBringToFront;
    onSendToBack = props.onSendToBack;
    onClearCanvas = props.onClearCanvas;
    onExportPNG = props.onExportPNG;
    onExportSVG = props.onExportSVG;
    onExportPDF = props.onExportPDF;
    onPaste = props.onPaste;
    onCopyCanvasPNG = props.onCopyCanvasPNG;
    onCopyCanvasSVG = props.onCopyCanvasSVG;
    onSelectAll = props.onSelectAll;
    hasSelection = props.hasSelection or False;

    if not visible {
        return None;
    }

    return <div
        className="fixed bg-white rounded-lg shadow-xl border border-gray-200 py-1 min-w-[180px] z-50"
        style={{"left": String(x) + "px", "top": String(y) + "px"}}
        onMouseLeave={onClose}
    >
        {hasSelection and <div>
            <button
                onClick={onDelete}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2 text-red-600"
            >
                <span>🗑️</span>
                <span>Delete</span>
            </button>
            <button
                onClick={onDuplicate}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>📋</span>
                <span>Duplicate</span>
            </button>
            <div className="h-px bg-gray-200 my-1"></div>
            <button
                onClick={onBringToFront}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>⬆️</span>
                <span>Bring to Front</span>
            </button>
            <button
                onClick={onSendToBack}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>⬇️</span>
                <span>Send to Back</span>
            </button>
            <div className="h-px bg-gray-200 my-1"></div>
            <button
                onClick={onExportPNG}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>🖼️</span>
                <span>Export as PNG</span>
            </button>
            <button
                onClick={onExportSVG}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>📐</span>
                <span>Export as SVG</span>
            </button>
            <button
                onClick={onExportPDF}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2"
            >
                <span>📄</span>
                <span>Export as PDF</span>
            </button>
            <div className="h-px bg-gray-200 my-1"></div>
            <button
                onClick={onClearCanvas}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2 text-red-600"
            >
                <span>🗑️</span>
                <span>Clear Canvas</span>
            </button>
        </div> or None}
        {not hasSelection and <div>
            <button
                onClick={onPaste}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center justify-between"
            >
                <span>Paste</span>
                <span className="text-xs text-gray-400">Ctrl+V</span>
            </button>
            <div className="h-px bg-gray-200 my-1"></div>
            <button
                onClick={onCopyCanvasPNG}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center justify-between"
            >
                <span>Copy to clipboard as PNG</span>
                <span className="text-xs text-gray-400">Shift+Alt+C</span>
            </button>
            <button
                onClick={onCopyCanvasSVG}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center justify-between"
            >
                <span>Copy to clipboard as SVG</span>
            </button>
            <div className="h-px bg-gray-200 my-1"></div>
            <button
                onClick={onSelectAll}
                className="w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center justify-between"
            >
                <span>Select all</span>
                <span className="text-xs text-gray-400">Ctrl+A</span>
            </button>
        </div> or None}
    </div>;
}
