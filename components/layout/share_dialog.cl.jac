"""ShareDialog — Two-tab dialog for static and live collaboration sharing."""

import from react { useState, useRef, useEffect }
import from ..layout.ConfirmDialog { ConfirmDialog }
import from ...services.scene_sharing { check_crypto_available, export_to_share_backend, generate_room_credentials }

def:pub ShareDialog(is_open: bool, on_close: any, elements_ref: any, room_state: dict, on_join_room: any, on_end_session: any, on_username_set: any = None, default_tab: str = "static") -> any {
    has active_tab: str = default_tab;
    has static_status: str = "idle";     # idle, loading, done, error
    has static_link: str = "";
    has error_message: str = "";
    has collab_status: str = "idle";      # idle, live
    has collab_link: str = "";
    has copied: bool = False;
    has crypto_available: bool = True;
    has username_input: str = localStorage.getItem("jasketch_username") or "Anonymous";
    has username_set: bool = False;
    has confirm_end_session: bool = False;
    has _generating: bool = False;

    useEffect(
        lambda -> any {
            crypto_available = check_crypto_available();
            return lambda -> None { };
        },
        []
    );

    useEffect(
        lambda -> any {
            if is_open {
                active_tab = default_tab;
                static_status = "idle";
                static_link = "";
                error_message = "";
                copied = False;
                _generating = False;
            }
            return lambda -> None { };
        },
        [is_open]
    );

    can with [room_state.room_id, is_open] entry {
        if is_open and room_state and room_state.room_id and not collab_link {
            origin = window.location.origin;
            pathname = window.location.pathname;
            collab_link = f"{origin}{pathname}#room={room_state.room_id},{room_state.room_key}";
        }
        return lambda -> None { };
    }

    def handle_generate_static_link() -> None {
        if _generating {
            return;
        }
        elements = elements_ref.current or [];
        if not elements {
            error_message = "Canvas is empty — draw something before sharing.";
            static_status = "error";
            return;
        }
        _generating = True;
        static_status = "loading";

        async def async_generate() {
            result: any = await export_to_share_backend(elements);

            if result["error"] {
                error_message = "Failed to generate link. Please try again.";
                static_status = "error";
                _generating = False;
                return;
            }

            share_id = result["share_id"] or "";
            key = result["key"] or "";
            origin = window.location.origin;
            pathname = window.location.pathname;
            link = f"{origin}{pathname}#json={share_id},{key}";
            static_link = link;
            static_status = "done";
            _generating = False;
        }

        async_generate();
    }

    def handle_start_collab_session() -> None {
        creds = generate_room_credentials();
        room_id = creds["room_id"] or "";
        room_key = creds["room_key"] or "";

        if room_id and room_key {
            origin = window.location.origin;
            pathname = window.location.pathname;
            link = f"{origin}{pathname}#room={room_id},{room_key}";
            collab_link = link;
            collab_status = "live";
            on_join_room(room_id, room_key);
            # Save username to localStorage and notify backend
            name = username_input or "Anonymous";
            localStorage.setItem("jasketch_username", name);
            if on_username_set {
                on_username_set(room_id, name);
            }
        }
    }

    def handle_copy_link(link: str) -> None {
        if link {
            navigator.clipboard.writeText(link).then(
                lambda -> None {
                    copied = True;
                    setTimeout(lambda -> None {
                        copied = False;
                    }, 2000);
                }
            );
        }
    }

    def handle_try_again() -> None {
        static_status = "idle";
        error_message = "";
    }

    def handle_username_change(new_username: str) -> None {
        username_input = new_username;
        username_set = False;
    }

    def handle_set_username() -> None {
        name = username_input or "Anonymous";
        localStorage.setItem("jasketch_username", name);
        if on_username_set and room_state and room_state.room_id {
            on_username_set(room_state.room_id, name);
        }
        username_set = True;
        setTimeout(lambda -> None { username_set = False; }, 2000);
    }

    def handle_end_session() -> None {
        confirm_end_session = False;
        on_end_session();
    }

    if not is_open {
        return None;
    }

    # Pre-compute static status content (if-elif chains can't live inside JSX expressions)
    static_status_content = None;
    if static_status == "idle" {
        static_status_content = <button
            onClick={lambda -> None { handle_generate_static_link(); }}
            className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 rounded-md transition"
        >
            {"Generate Link"}
        </button>;
    } elif static_status == "loading" {
        static_status_content = <button
            disabled={True}
            className="w-full bg-gray-300 text-gray-600 font-medium py-2 rounded-md cursor-not-allowed"
        >
            {"Generating..."}
        </button>;
    } elif static_status == "done" {
        static_status_content = <div className="space-y-2">
            <input
                type="text"
                value={static_link}
                readOnly={True}
                className="w-full px-3 py-2 border rounded-md bg-gray-50 font-mono text-sm"
            />
            <button
                onClick={lambda -> None { handle_copy_link(static_link); }}
                className={"w-full font-medium py-2 rounded-md transition " + (copied and "bg-green-500 hover:bg-green-600 text-white" or "bg-gray-200 hover:bg-gray-300 text-gray-800")}
            >
                {copied and "Copied!" or "Copy Link"}
            </button>
            <p className="text-xs text-gray-500 mt-2">
                {"This link expires in 7 days."}
            </p>
        </div>;
    } else {
        static_status_content = <div className="space-y-2">
            <div className="bg-red-50 border border-red-200 rounded-md p-3">
                <p className="text-sm text-red-700">
                    {error_message or "Failed to generate link. Please try again."}
                </p>
            </div>
            <button
                onClick={lambda -> None { handle_try_again(); }}
                className="w-full bg-gray-200 hover:bg-gray-300 text-gray-800 font-medium py-2 rounded-md transition"
            >
                {"Try Again"}
            </button>
        </div>;
    }

    # Pre-compute collab tab content
    collab_content = None;
    if room_state and room_state.room_id {
        collab_content = <div className="space-y-4">
            <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                <span className="text-sm font-medium text-green-700">{"Live - Collaborating"}</span>
            </div>
            <input
                type="text"
                value={collab_link}
                readOnly={True}
                className="w-full px-3 py-2 border rounded-md bg-gray-50 font-mono text-sm"
            />
            <button
                onClick={lambda -> None { handle_copy_link(collab_link); }}
                className={"w-full font-medium py-2 rounded-md transition " + (copied and "bg-green-500 hover:bg-green-600 text-white" or "bg-gray-200 hover:bg-gray-300 text-gray-800")}
            >
                {copied and "Copied!" or "Copy Link"}
            </button>
            <button
                onClick={lambda -> None { confirm_end_session = True; }}
                className="w-full bg-red-500 hover:bg-red-600 text-white font-medium py-2 rounded-md transition"
            >
                {"End Session"}
            </button>
        </div>;
    } else {
        collab_content = <div className="space-y-4">
            <p className="text-sm text-gray-600">
                {"Start a live session to collaborate with others in real time."}
            </p>
            <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                    {"Display Name"}
                </label>
                <input
                    type="text"
                    value={username_input}
                    onChange={lambda e: any -> None { handle_username_change(e.target.value); }}
                    className="w-full px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="Enter your name (optional)"
                />
            </div>
            <button
                onClick={lambda -> None { handle_start_collab_session(); }}
                className="w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 rounded-md transition"
            >
                {"Start Session"}
            </button>
        </div>;
    }

    # Pre-compute active tab panel
    tab_content = None;
    if active_tab == "static" {
        tab_content = <div>
            <p className="text-sm text-gray-600 mb-4">
                {"Generate a read-only link to your canvas. The link expires in 7 days."}
            </p>
            {static_status_content}
        </div>;
    } elif active_tab == "collab" {
        tab_content = collab_content;
    }

    return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
        <div className="bg-white rounded-lg shadow-lg max-w-md w-full mx-4">
            <div className="border-b px-6 py-4 flex justify-between items-center">
                <h2 className="text-lg font-semibold">{"Share Canvas"}</h2>
                <button
                    onClick={lambda -> None { on_close(); }}
                    className="text-gray-500 hover:text-gray-700 text-xl"
                >
                    {"×"}
                </button>
            </div>

            {not crypto_available and <div className="bg-yellow-100 border-l-4 border-yellow-500 p-3 mx-6 mt-4">
                <p className="text-sm text-yellow-700">
                    {"Web Crypto API not available. Try HTTPS or a different browser."}
                </p>
            </div> or None}

            <div className="flex border-b px-6 mt-4">
                <button
                    onClick={lambda -> None { active_tab = "static"; }}
                    className={"pb-3 px-4 border-b-2 transition " + (active_tab == "static" and "border-blue-500 text-blue-600 font-medium" or "border-transparent text-gray-600 hover:text-gray-900")}
                >
                    {"Read-only Share"}
                </button>
                <button
                    onClick={lambda -> None { active_tab = "collab"; }}
                    className={"pb-3 px-4 border-b-2 transition " + (active_tab == "collab" and "border-blue-500 text-blue-600 font-medium" or "border-transparent text-gray-600 hover:text-gray-900")}
                >
                    {"Live Collaboration"}
                </button>
            </div>

            <div className="p-6">
                {tab_content}
            </div>
        </div>

        {confirm_end_session and <ConfirmDialog
            title="End Collaboration Session?"
            message="This will disconnect all collaborators. Are you sure?"
            confirmText="End Session"
            onConfirm={lambda -> None { handle_end_session(); }}
            onCancel={lambda -> None { confirm_end_session = False; }}
        /> or None}
    </div>;
}
