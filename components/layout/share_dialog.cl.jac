"""ShareDialog — Two-tab dialog for static and live collaboration sharing."""

import from react { useState, useRef, useEffect }
import from ..layout.ConfirmDialog { ConfirmDialog }
import from ...services.scene_sharing { check_crypto_available, export_to_share_backend, generate_room_credentials }

def:pub ShareDialog(
    is_open: bool,
    on_close: Callable[[], None],
    elements_ref: any,
    room_state: dict,
    on_join_room: Callable[[str, str], None],
    on_end_session: Callable[[], None],
    on_username_set: Callable[[str, str], None] | None = None,
    default_tab: str = "static"
) -> JsxElement | None {
    has active_tab: str = default_tab;
    has static_status: str = "idle";     # idle, loading, done, error
    has static_link: str = "";
    has error_message: str = "";
    has collab_status: str = "idle";      # idle, live
    has collab_link: str = "";
    has copied: bool = False;
    has crypto_available: bool = True;
    has username_input: str = "";
    has username_set: bool = False;
    has confirm_end_session: bool = False;
    has _generating: bool = False;

    def closeOnEscape(ev: any) -> None {
        if ev.key == "Escape" {
            on_close();
        }
    }

    useEffect(lambda () -> any {
        if is_open {
            window.addEventListener("keydown", closeOnEscape);
        }
        return lambda {
            window.removeEventListener("keydown", closeOnEscape);
        };
    }, [is_open]);

    useEffect(
        lambda () -> any {
            crypto_available = check_crypto_available();
            return lambda { };
        },
        []
    );

    useEffect(
        lambda () -> any {
            if is_open {
                active_tab = default_tab;
                static_status = "idle";
                static_link = "";
                error_message = "";
                copied = False;
                _generating = False;
            }
            return lambda { };
        },
        [is_open]
    );

    can with [room_state["room_id"], is_open] entry {
        if is_open and room_state and room_state["room_id"] and not collab_link {
            origin = window.location.origin;
            pathname = window.location.pathname;
            collab_link = f"{origin}{pathname}#room={room_state["room_id"]},{room_state["room_key"]}";
        }
        return lambda { };
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

    async def handle_start_collab_session() -> None {
        creds = await generate_room_credentials();
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
                lambda {
                    copied = True;
                    setTimeout(lambda {
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
        if on_username_set and room_state and room_state["room_id"] {
            on_username_set(room_state["room_id"], name);
        }
        username_set = True;
        setTimeout(lambda { username_set = False; }, 2000);
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
            onClick={lambda { handle_generate_static_link(); }}
            className="w-full bg-orange-500 hover:bg-orange-600 active:bg-orange-700 text-white font-medium py-2.5 rounded-xl shadow-sm transition-colors"
        >
            {"Generate Link"}
        </button>;
    } elif static_status == "loading" {
        static_status_content = <button
            disabled={True}
            className="w-full bg-slate-100 text-slate-400 font-medium py-2.5 rounded-xl cursor-not-allowed"
        >
            {"Generating..."}
        </button>;
    } elif static_status == "done" {
        static_status_content = <div className="space-y-2">
            <input
                type="text"
                value={static_link}
                readOnly={True}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 font-mono text-sm text-slate-700"
            />
            <button
                onClick={lambda { handle_copy_link(static_link); }}
                className={"w-full font-medium py-2 rounded-md transition " + ("bg-emerald-600 text-white" if copied else "bg-slate-100 hover:bg-slate-200 text-slate-700")}
            >
                {copied and "Copied!" or "Copy Link"}
            </button>
            <p className="text-xs text-gray-500 mt-2">
                {"This link expires in 7 days."}
            </p>
        </div>;
    } else {
        static_status_content = <div className="space-y-2">
            <div className="bg-rose-50 border border-rose-100 rounded-xl p-3.5">
                <p className="text-sm text-red-700">
                    {error_message or "Failed to generate link. Please try again."}
                </p>
            </div>
            <button
                onClick={lambda { handle_try_again(); }}
                className="w-full bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium py-2.5 rounded-xl transition-colors"
            >
                {"Try Again"}
            </button>
        </div>;
    }

    # Pre-compute collab tab content
    collab_content = None;
    if room_state and room_state["room_id"] {
        collab_content = <div className="space-y-4">
            <div className="flex items-center gap-2">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                <span className="text-sm font-medium text-green-700">{"Live - Collaborating"}</span>
            </div>
            <input
                type="text"
                value={collab_link}
                readOnly={True}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 font-mono text-sm text-slate-700"
            />
            <button
                onClick={lambda { handle_copy_link(collab_link); }}
                className={"w-full font-medium py-2 rounded-md transition " + ("bg-emerald-600 text-white" if copied else "bg-slate-100 hover:bg-slate-200 text-slate-700")}
            >
                {copied and "Copied!" or "Copy Link"}
            </button>
            <button
                onClick={lambda { confirm_end_session = True; }}
                className="w-full bg-rose-600 hover:bg-rose-700 text-white font-medium py-2.5 rounded-xl shadow-sm transition-colors"
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
                    onChange={lambda (e: any) { handle_username_change(e.target.value); }}
                    className="w-full px-3.5 py-2.5 rounded-xl border border-slate-200 text-sm placeholder:text-slate-400 focus:outline-none focus:border-orange-400 focus:ring-4 focus:ring-orange-500/10 transition"
                    placeholder="Enter your name"
                />
            </div>
            <button
                onClick={lambda { handle_start_collab_session(); }}
                className="w-full bg-orange-500 hover:bg-orange-600 active:bg-orange-700 text-white font-medium py-2.5 rounded-xl shadow-sm transition-colors"
            >
                {"Start Session"}
            </button>
        </div>;
    }

    # ── AI assistant panel ────────────────────────────────────────────────────
    # The session id used to be reachable only from the devtools console, which
    # is not a step anyone should have to take to connect an assistant.
    mcp_session = sessionStorage.getItem("jasketch_session_id") or "";
    mcp_url = window.location.origin + "/mcp";
    mcp_command = "claude mcp add --transport http jasketch " + mcp_url;

    assistant_content = <div className="space-y-4">
        <p className="text-sm text-gray-600">
            {"Let Claude (or any MCP client) draw on this canvas. Nothing to install."}
        </p>

        <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">{"1. Add the server"}</label>
            <input
                type="text"
                value={mcp_command}
                readOnly={True}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 font-mono text-xs text-slate-700"
            />
            <button
                onClick={lambda { handle_copy_link(mcp_command); }}
                className={"mt-2 w-full font-medium py-2 rounded-md transition " + ("bg-emerald-600 text-white" if copied else "bg-slate-100 hover:bg-slate-200 text-slate-700")}
            >
                {copied and "Copied!" or "Copy command"}
            </button>
        </div>

        <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
                {"2. Tell it which canvas -- this tab's id"}
            </label>
            <input
                type="text"
                value={mcp_session}
                readOnly={True}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 font-mono text-xs text-slate-700"
            />
            <button
                onClick={lambda { handle_copy_link(mcp_session); }}
                className="mt-2 w-full bg-slate-100 hover:bg-slate-200 text-slate-700 font-medium py-2.5 rounded-xl transition-colors"
            >
                {"Copy session id"}
            </button>
            <p className="text-xs text-gray-500 mt-2">
                {"Paste it when the assistant asks which canvas to draw on. It is per tab, and resets if you close this one."}
            </p>
        </div>
    </div>;

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
    } elif active_tab == "assistant" {
        tab_content = assistant_content;
    }

    return <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 backdrop-blur-sm p-4"
        onClick={lambda (ev: any) { if ev.target == ev.currentTarget { on_close(); } }}>
        <div className="bg-white rounded-2xl shadow-2xl ring-1 ring-slate-900/5 max-w-md w-full overflow-hidden">
            <div className="px-6 pt-5 pb-1 flex justify-between items-start">
                <h2 className="text-lg font-semibold">{"Share Canvas"}</h2>
                <button
                    onClick={lambda { on_close(); }}
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

            <div className="mx-6 mt-4 mb-1 flex gap-1 bg-slate-100 rounded-xl p-1">
                <button
                    onClick={lambda { active_tab = "static"; }}
                    className={"flex-1 px-3 py-2 rounded-lg text-sm whitespace-nowrap transition-all duration-150 " + ("bg-white text-slate-900 font-medium shadow-sm ring-1 ring-slate-900/5" if active_tab == "static" else "text-slate-500 hover:text-slate-800")}
                >
                    {"Read-only"}
                </button>
                <button
                    onClick={lambda { active_tab = "collab"; }}
                    className={"flex-1 px-3 py-2 rounded-lg text-sm whitespace-nowrap transition-all duration-150 " + ("bg-white text-slate-900 font-medium shadow-sm ring-1 ring-slate-900/5" if active_tab == "collab" else "text-slate-500 hover:text-slate-800")}
                >
                    {"Live"}
                </button>
                <button
                    onClick={lambda { active_tab = "assistant"; }}
                    className={"flex-1 px-3 py-2 rounded-lg text-sm whitespace-nowrap transition-all duration-150 " + ("bg-white text-slate-900 font-medium shadow-sm ring-1 ring-slate-900/5" if active_tab == "assistant" else "text-slate-500 hover:text-slate-800")}
                >
                    {"AI"}
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
            onConfirm={lambda { handle_end_session(); }}
            onCancel={lambda { confirm_end_session = False; }}
        /> or None}
    </div>;
}
