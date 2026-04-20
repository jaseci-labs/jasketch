"""ParticipantList — Zoom-style panel showing all room participants."""

import from react { useRef }

def:pub ParticipantList(props: dict) -> JsxElement {
    participants = props.participants or {};
    isHost = props.isHost or False;
    mySessionId = props.mySessionId or "";
    onClose = props.onClose;
    onRenameMe = props.onRenameMe;

    # __hostSid is a meta key injected by Canvas alongside participants
    hostSessionId = participants["__hostSid"] or "";

    my_data = participants[mySessionId] or {"username": localStorage.getItem("jasketch_username") or "Anonymous", "color": "#f97316"};

    has editingName: bool = False;
    has nameInput: str = my_data.username or "Anonymous";
    has nameSaved: bool = False;
    nameInputRef = useRef(None);

    def handleStartEdit() -> None {
        nameInput = (participants[mySessionId] and participants[mySessionId].username) or localStorage.getItem("jasketch_username") or "Anonymous";
        editingName = True;
        setTimeout(lambda -> None {
            if nameInputRef.current { nameInputRef.current.focus(); nameInputRef.current.select(); }
        }, 10);
    }

    def handleSaveName() -> None {
        if not editingName { return; }
        name = nameInput.strip() or "Anonymous";
        editingName = False;
        if onRenameMe { onRenameMe(name); }
        nameSaved = True;
        setTimeout(lambda -> None { nameSaved = False; }, 2000);
    }

    def handleNameKeyDown(e: dict) -> None {
        if e.key == "Enter" { handleSaveName(); }
        if e.key == "Escape" { editingName = False; }
    }

    all_sids = [sid for sid in Object.keys(participants) if sid != "__hostSid"];
    other_sids = [sid for sid in all_sids if sid != mySessionId];
    # Refresh my_data reactively
    current_my_data = participants[mySessionId] or {"username": localStorage.getItem("jasketch_username") or "Anonymous", "color": "#f97316"};

    return <div className="bg-white border border-gray-200 rounded-lg shadow-xl w-72">
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
            <span className="text-sm font-semibold text-gray-700">
                {"Participants (" + String(all_sids.length) + ")"}
            </span>
            <button
                onClick={lambda -> None { if onClose { onClose(); } }}
                className="text-gray-400 hover:text-gray-600 transition-colors"
            >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                </svg>
            </button>
        </div>
        <div className="py-1 max-h-64 overflow-y-auto">
            <div className="px-4 py-2.5 flex items-center gap-3">
                <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{"backgroundColor": current_my_data.color or "#f97316"}}></div>
                <div className="flex-1 min-w-0">
                    {editingName and <input
                        ref={nameInputRef}
                        type="text"
                        value={nameInput}
                        onChange={lambda e: any -> None { nameInput = e.target.value; }}
                        onKeyDown={handleNameKeyDown}
                        onBlur={lambda -> None { handleSaveName(); }}
                        className="w-full text-sm border border-orange-300 rounded px-2 py-0.5 focus:outline-none focus:ring-1 focus:ring-orange-400"
                    /> or <span className="text-sm text-gray-800 truncate block">{current_my_data.username or "Anonymous"}</span>}
                </div>
                <div className="flex items-center gap-1.5 flex-shrink-0">
                    <span className="text-xs text-gray-400">{"(me)"}</span>
                    {isHost and <span className="text-xs bg-orange-100 text-orange-700 px-1.5 py-0.5 rounded font-medium">{"Host"}</span> or None}
                    {not editingName and <button
                        onClick={lambda -> None { handleStartEdit(); }}
                        title="Rename"
                        className="text-gray-400 hover:text-orange-600 transition-colors"
                    >
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                            <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                            <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                        </svg>
                    </button> or <button
                        onClick={lambda -> None { handleSaveName(); }}
                        className="text-xs bg-orange-500 text-white px-2 py-0.5 rounded hover:bg-orange-600 transition-colors"
                    >{"Save"}</button>}
                </div>
            </div>
            {other_sids.length > 0 and <div className="border-t border-gray-50 my-0.5"></div> or None}
            {[<div key={osid} className="px-4 py-2.5 flex items-center gap-3">
                <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{"backgroundColor": participants[osid].color or "#999999"}}></div>
                <span className="text-sm text-gray-700 truncate flex-1">{participants[osid].username or "Anonymous"}</span>
                {osid == hostSessionId and <span className="text-xs bg-orange-100 text-orange-700 px-1.5 py-0.5 rounded font-medium flex-shrink-0">{"Host"}</span> or None}
            </div> for osid in other_sids]}
        </div>
    </div>;
}
