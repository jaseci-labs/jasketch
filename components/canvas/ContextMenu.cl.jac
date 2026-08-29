def:pub ContextMenu(
    onClose: Callable[[], None],
    onDelete: Callable[[], None],
    onDuplicate: Callable[[], None],
    onBringToFront: Callable[[], None],
    onSendToBack: Callable[[], None],
    onClearCanvas: Callable[[], None],
    onExportPNG: Callable[[], None],
    onExportSVG: Callable[[], None],
    onCopySelectionPNG: Callable[[], None],
    onPaste: Callable[[], None],
    onCopyCanvasPNG: Callable[[], None],
    onCopyCanvasSVG: Callable[[], None],
    onSelectAll: Callable[[], None],
    onGroup: Callable[[], None],
    onUngroup: Callable[[], None],
    visible: bool = False,
    x: float = 0,
    y: float = 0,
    hasSelection: bool = False,
    canGroup: bool = False,
    canUngroup: bool = False
) -> JsxElement | None {

    if not visible {
        return None;
    }

    itemClass = "w-full px-3 py-1.5 text-left text-[13px] text-gray-700 hover:bg-gray-50 flex items-center justify-between transition-colors";
    dangerClass = "w-full px-3 py-1.5 text-left text-[13px] text-red-600 hover:bg-red-50 flex items-center justify-between transition-colors";
    shortcutClass = "text-[11px] text-gray-400 ml-6";
    dividerClass = "h-px bg-gray-100 my-0.5";

    return <div
        className="fixed bg-white rounded-lg shadow-[0_6px_24px_rgba(0,0,0,0.15)] border border-gray-200/80 py-1 min-w-[200px] z-50"
        style={{"left": str(x) + "px", "top": str(y) + "px"}}
        onMouseLeave={onClose}
    >
        {hasSelection and <div>
            <button onClick={onDuplicate} className={itemClass}>
                <span>Duplicate</span>
                <span className={shortcutClass}>Ctrl+D</span>
            </button>
            <button onClick={onDelete} className={dangerClass}>
                <span>Delete</span>
                <span className={shortcutClass}>Del</span>
            </button>
            <div className={dividerClass}></div>
            <button onClick={onBringToFront} className={itemClass}>
                <span>Bring to front</span>
            </button>
            <button onClick={onSendToBack} className={itemClass}>
                <span>Send to back</span>
            </button>
            {(canGroup or canUngroup) and <div className={dividerClass}></div> or None}
            {canGroup and <button onClick={onGroup} className={itemClass}>
                <span>Group</span>
                <span className={shortcutClass}>Ctrl+G</span>
            </button> or None}
            {canUngroup and <button onClick={onUngroup} className={itemClass}>
                <span>Ungroup</span>
                <span className={shortcutClass}>Ctrl+Shift+G</span>
            </button> or None}
            <div className={dividerClass}></div>
            <button onClick={onExportPNG} className={itemClass}>
                <span>Export as PNG</span>
            </button>
            <button onClick={onExportSVG} className={itemClass}>
                <span>Export as SVG</span>
            </button>
            <button onClick={onCopySelectionPNG} className={itemClass}>
                <span>Copy as PNG</span>
            </button>
        </div> or None}
        {not hasSelection and <div>
            <button onClick={onPaste} className={itemClass}>
                <span>Paste</span>
                <span className={shortcutClass}>Ctrl+V</span>
            </button>
            <div className={dividerClass}></div>
            <button onClick={onCopyCanvasPNG} className={itemClass}>
                <span>Copy as PNG</span>
                <span className={shortcutClass}>Shift+Alt+C</span>
            </button>
            <button onClick={onCopyCanvasSVG} className={itemClass}>
                <span>Copy as SVG</span>
            </button>
            <div className={dividerClass}></div>
            <button onClick={onSelectAll} className={itemClass}>
                <span>Select all</span>
                <span className={shortcutClass}>Ctrl+A</span>
            </button>
        </div> or None}
    </div>;
}
