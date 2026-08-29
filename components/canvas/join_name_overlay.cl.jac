"""JoinNameOverlay — name prompt shown when opening a collaboration link."""

def:pub JoinNameOverlay(on_join: Callable[[str], None]) -> JsxElement {
    has name_value: str = "";

    def handle_join() -> None {
        name = name_value.strip() or "Anonymous";
        localStorage.setItem("jasketch_username", name);
        on_join(name);
    }

    return <div className="fixed inset-0 z-50 flex items-center justify-center">
        <div className="bg-white rounded-2xl shadow-2xl ring-1 ring-slate-900/5 w-full max-w-sm mx-4">
            <div className="border-b px-6 py-4">
                <h2 className="text-lg font-semibold">{"Join Collaboration Session"}</h2>
            </div>
            <div className="p-6 space-y-4">
                <p className="text-sm text-gray-600">
                    {"You've been invited to collaborate. Set your display name before joining."}
                </p>
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                        {"Display Name"}
                    </label>
                    <input
                        type="text"
                        value={name_value}
                        onChange={lambda (e: any) { name_value = e.target.value; }}
                        onKeyDown={lambda (e: any) {
                            if e.key == "Enter" { handle_join(); }
                        }}
                        className="w-full px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-orange-500/20 focus:border-orange-400"
                        placeholder="Enter your name (optional)"
                        autoFocus={True}
                    />
                </div>
                <button
                    onClick={lambda { handle_join(); }}
                    className="w-full bg-orange-500 hover:bg-orange-600 text-white font-medium py-2 rounded-md transition"
                >
                    {"Join"}
                </button>
            </div>
        </div>
    </div>;
}
