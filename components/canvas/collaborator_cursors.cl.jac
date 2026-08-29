"""CollaboratorCursors — Render other collaborators' cursors and usernames on the canvas."""

def:pub CollaboratorCursors(cursor_states: dict, zoom: float, pan_x: float, pan_y: float) -> JsxElement | None {
    if not cursor_states {
        return None;
    }

    cursor_sids: list = cursor_states.keys();
    if not cursor_sids or len(cursor_sids) == 0 {
        return None;
    }

    return <div className="absolute inset-0 pointer-events-none overflow-hidden z-30">
        {[<div
            key={csid}
            className="absolute flex flex-col items-start"
            style={{
                "left": (cursor_states[csid].x * zoom + pan_x) + "px",
                "top": (cursor_states[csid].y * zoom + pan_y) + "px",
                "transform": "translate(-4px, -4px)"
            }}
        >
            <svg width="14" height="14" viewBox="0 0 14 14">
                <path
                    d="M0 0 L0 14 L4 10 L7 13 L9 12 L6 9 L10 9 Z"
                    fill={cursor_states[csid].color or "#666"}
                    stroke="white"
                    strokeWidth="0.8"
                />
            </svg>
            <div
                className="text-xs font-medium px-1.5 py-0.5 rounded-sm whitespace-nowrap mt-0.5"
                style={{"backgroundColor": cursor_states[csid].color or "#666", "color": "white", "fontSize": "11px"}}
            >
                {cursor_states[csid].username or "Anonymous"}
            </div>
        </div> for csid in cursor_states.keys()]}
    </div>;
}
