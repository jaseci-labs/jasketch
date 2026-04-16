def:pub ConfirmDialog(props: dict) -> JsxElement {
    def _noop() -> None {}
    title = props.title or "Confirm";
    message = props.message or "Are you sure?";
    onConfirm = props.onConfirm or _noop;
    onCancel = props.onCancel or _noop;
    confirmText = props.confirmText or "Confirm";
    cancelText = props.cancelText or "Cancel";
    isDangerous = props.isDangerous or False;

    def handleBackdropClick(e: dict) -> None {
        if e.target == e.currentTarget {
            onCancel();
        }
    }

    def handleEscape(e: dict) -> None {
        if e.key == "Escape" {
            onCancel();
        }
    }

    can with entry {
        window.addEventListener("keydown", handleEscape);
        return lambda -> None {
            window.removeEventListener("keydown", handleEscape);
        };
    }

    return <div
        className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50"
        onClick={handleBackdropClick}
    >
        <div className="bg-white rounded-xl shadow-2xl max-w-sm w-full mx-4">
            <div className="px-6 py-4 border-b border-gray-200">
                <h2 className="text-lg font-semibold text-gray-800">{title}</h2>
            </div>

            <div className="px-6 py-4">
                <p className="text-sm text-gray-600">{message}</p>
            </div>

            <div className="px-6 py-4 border-t border-gray-200 flex gap-3 justify-end">
                <button
                    onClick={onCancel}
                    className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
                >
                    {cancelText}
                </button>
                <button
                    onClick={onConfirm}
                    className={"px-4 py-2 text-sm font-medium text-white rounded-lg transition-colors " + (isDangerous and "bg-red-600 hover:bg-red-700" or "bg-blue-600 hover:bg-blue-700")}
                >
                    {confirmText}
                </button>
            </div>
        </div>
    </div>;
}
