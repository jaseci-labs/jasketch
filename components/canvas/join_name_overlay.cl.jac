"""JoinNameOverlay — name prompt shown when opening a collaboration link."""

def:pub JoinNameOverlay(on_join: any) -> any {
    has name_value: str = localStorage.getItem("jasketch_username") or "";

    def handle_join() -> None {
        name = name_value.strip() or "Anonymous";
        localStorage.setItem("jasketch_username", name);
        on_join(name);
    }

    return <div className="fixed inset-0 z-50 flex items-center justify-center">
        <div className="bg-white rounded-lg shadow-lg w-full max-w-sm mx-4">
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
                        onChange={lambda e: any -> None { name_value = e.target.value; }}
                        onKeyDown={lambda e: any -> None {
                            if e.key == "Enter" { handle_join(); }
                        }}
                        className="w-full px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                        placeholder="Enter your name (optional)"
                        autoFocus={True}
                    />
                </div>
                <button
                    onClick={lambda -> None { handle_join(); }}
                    className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 rounded-md transition"
                >
                    {"Join"}
                </button>
            </div>
        </div>
    </div>;
}
