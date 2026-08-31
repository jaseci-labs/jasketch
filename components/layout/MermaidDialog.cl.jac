"""Paste Mermaid, get shapes.

Deliberately a dialog rather than a live pane: importing is something you do
once at the start of a diagram and then edit by hand, not a source you keep in
sync. Treating it as a one-way import keeps the canvas the single source of
truth, so nothing you draw afterwards is at risk of being overwritten by a
re-render of the text.
"""

import from react { useRef, useEffect }
import from "...services.mermaid" { mermaid_to_elements }

glob MERMAID_SAMPLE: str = "graph TD\n    A[Christmas] -->|Get money| B(Go shopping)\n    B --> C{Let me think}\n    C -->|One| D[Laptop]\n    C -->|Two| E[iPhone]\n    C -->|Three| F[Car]";


def:pub MermaidDialog(
    is_open: bool,
    on_close: Callable[[], None],
    on_import: Callable[[list], None],
    color: str = "#000000",
    stroke_width: float = 2,
    font_family: str = "Virgil",
    font_size: float = 20
) -> JsxElement | None {

    has source: str = "";
    has error_message: str = "";

    textRef = useRef(None);

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

    def runImport() -> None {
        result = mermaid_to_elements(source, 200.0, 160.0, color, stroke_width, font_family, font_size);
        if not result["ok"] {
            error_message = result["error"];
            return;
        }
        error_message = "";
        on_import(result["elements"]);
        source = "";
        on_close();
    }

    if not is_open {
        return None;
    }

    return <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 backdrop-blur-sm p-4"
        onClick={lambda (ev: any) { if ev.target == ev.currentTarget { on_close(); } }}>
        <div className="bg-white rounded-2xl shadow-2xl ring-1 ring-slate-900/5 max-w-xl w-full overflow-hidden">

            <div className="px-6 pt-5 pb-1 flex justify-between items-start">
                <div>
                    <h2 className="text-base font-semibold text-slate-900">{"Import from Mermaid"}</h2>
                    <p className="text-xs text-slate-500 mt-0.5">{"Flowcharts become shapes you can edit."}</p>
                </div>
                <button onClick={lambda { on_close(); }} title="Close"
                    className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400 hover:text-slate-700 hover:bg-slate-100 transition-colors">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                </button>
            </div>

            <div className="px-6 py-4 space-y-3">
                <textarea
                    ref={textRef}
                    value={source}
                    onChange={lambda (e: any) { source = e.target.value; error_message = ""; }}
                    placeholder={MERMAID_SAMPLE}
                    spellCheck={False}
                    className="w-full h-56 px-3.5 py-3 rounded-xl border border-slate-200 font-mono text-xs leading-relaxed text-slate-700 placeholder:text-slate-300 focus:outline-none focus:border-orange-400 focus:ring-4 focus:ring-orange-500/10 transition resize-none"
                />

                {error_message != "" and <div className="bg-rose-50 border border-rose-100 rounded-xl px-3.5 py-2.5">
                    <p className="text-xs text-rose-700">{error_message}</p>
                </div> or None}

                <div className="flex items-center gap-2">
                    <button
                        onClick={lambda { source = MERMAID_SAMPLE; error_message = ""; }}
                        className="text-xs text-slate-500 hover:text-slate-800 transition-colors"
                    >{"Use an example"}</button>
                    <span className="ml-auto text-[11px] text-slate-400">{"Flowcharts only for now"}</span>
                </div>

                <button
                    onClick={lambda { runImport(); }}
                    disabled={source.trim() == ""}
                    className="w-full bg-orange-500 hover:bg-orange-600 active:bg-orange-700 disabled:bg-slate-100 disabled:text-slate-400 text-white font-medium py-2.5 rounded-xl shadow-sm transition-colors"
                >{"Add to canvas"}</button>
            </div>
        </div>
    </div>;
}
