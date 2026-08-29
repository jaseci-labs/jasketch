import from react { useEffect }

def:pub ShortcutHelp(onClose: Callable[[], None]) -> JsxElement {

    toolShortcuts = [
        {"action": "Hand (pan)", "key": "Space"},
        {"action": "Select", "key": "V or 1"},
        {"action": "Pencil", "key": "P or 2"},
        {"action": "Line", "key": "L or 3"},
        {"action": "Arrow", "key": "A or 4"},
        {"action": "Rectangle", "key": "R or 5"},
        {"action": "Diamond", "key": "D or 6"},
        {"action": "Ellipse", "key": "O or 7"},
        {"action": "Text", "key": "T or 8"},
        {"action": "Image", "key": "9"},
        {"action": "Keep tool selected", "key": "Q"},
    ];

    editorShortcuts = [
        {"action": "Delete", "key": "Delete"},
        {"action": "Cut", "key": "Ctrl+X"},
        {"action": "Copy", "key": "Ctrl+C"},
        {"action": "Paste", "key": "Ctrl+V"},
        {"action": "Duplicate", "key": "Ctrl+D or Alt+drag"},
        {"action": "Select All", "key": "Ctrl+A"},
        {"action": "Add to selection", "key": "Shift+click"},
        {"action": "Undo", "key": "Ctrl+Z"},
        {"action": "Redo", "key": "Ctrl+Y or Ctrl+Shift+Z"},
        {"action": "Group", "key": "Ctrl+G"},
        {"action": "Ungroup", "key": "Ctrl+Shift+G"},
        {"action": "Bring to front", "key": "Ctrl+]"},
        {"action": "Send to back", "key": "Ctrl+["},
        {"action": "Zoom in", "key": "Ctrl++"},
        {"action": "Zoom out", "key": "Ctrl+-"},
        {"action": "Reset zoom", "key": "Ctrl+0"},
        {"action": "Zoom to fit", "key": "Shift+1"},
        {"action": "Nudge selection", "key": "Arrow keys"},
        {"action": "Nudge by 10px", "key": "Shift+Arrow"},
        {"action": "Constrain / keep proportions", "key": "Hold Shift"},
        {"action": "Reset canvas", "key": "Ctrl+Delete"},
        {"action": "Increase font size", "key": "Ctrl+Shift+>"},
        {"action": "Decrease font size", "key": "Ctrl+Shift+<"},
        {"action": "Save", "key": "Ctrl+S"},
        {"action": "Open", "key": "Ctrl+O"},
        {"action": "Copy as PNG", "key": "Shift+Alt+C"},
        {"action": "Keyboard shortcuts", "key": "?"},
    ];

    def handleBackdropClick(e: MouseEvent) -> None {
        if e.target == e.currentTarget {
            onClose();
        }
    }

    def handleEscape(e: KeyboardEvent) -> None {
        if e.key == "Escape" {
            onClose();
        }
    }

    # Acquire-and-release in ONE effect: `can with entry`/`can with exit` compile
    # to separate useEffect closures, so a handle created in entry is invisible to
    # exit and the removeEventListener would silently no-op.
    useEffect(lambda () -> any {
        window.addEventListener("keydown", handleEscape);
        return lambda {
            window.removeEventListener("keydown", handleEscape);
        };
    }, []);


    return <div
        className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50"
        onClick={handleBackdropClick}
    >
        <div className="bg-white rounded-xl shadow-2xl max-w-4xl w-11/12 max-h-[85vh] overflow-auto">
            <div className="sticky top-0 bg-white border-b border-gray-200 px-8 py-6 flex items-center justify-between">
                <h2 className="text-2xl font-bold text-gray-800">Keyboard Shortcuts</h2>
                <button
                    onClick={onClose}
                    className="text-gray-400 hover:text-gray-600 transition-colors"
                    title="Close (Esc)"
                >
                    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <line x1="18" y1="6" x2="6" y2="18" />
                        <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                </button>
            </div>

            <div className="px-8 py-8">
                <div className="grid grid-cols-2 gap-12">
                    <div>
                        <h3 className="text-lg font-semibold text-gray-700 mb-4">Tools</h3>
                        <div className="space-y-3">
                            {[
                                <div key={item["action"]} className="flex items-center justify-between text-sm">
                                    <span className="text-gray-700">{item["action"]}</span>
                                    <kbd className="bg-gray-100 text-gray-800 px-3 py-1 rounded-lg font-mono text-xs font-medium border border-gray-300">
                                        {item["key"]}
                                    </kbd>
                                </div>
                                for item in toolShortcuts
                            ]}
                        </div>
                    </div>

                    <div>
                        <h3 className="text-lg font-semibold text-gray-700 mb-4">Editor</h3>
                        <div className="space-y-3">
                            {[
                                <div key={item["action"]} className="flex items-center justify-between text-sm">
                                    <span className="text-gray-700">{item["action"]}</span>
                                    <kbd className="bg-gray-100 text-gray-800 px-3 py-1 rounded-lg font-mono text-xs font-medium border border-gray-300">
                                        {item["key"]}
                                    </kbd>
                                </div>
                                for item in editorShortcuts
                            ]}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>;
}
