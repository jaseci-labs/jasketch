import from react { useRef }

def ToolIcon(
    toolId: str,
    color: str = "currentColor",
    size: float = 18
) -> JsxElement {

    if toolId == "select" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 3l7.07 16.97 2.51-7.39 7.39-2.51L3 3z" />
            <path d="M13 13l6 6" />
        </svg>;
    } elif toolId == "freehand" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
            <path d="m15 5 4 4" />
        </svg>;
    } elif toolId == "line" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round">
            <line x1="5" y1="19" x2="19" y2="5" />
        </svg>;
    } elif toolId == "arrow" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="5" y1="19" x2="19" y2="5" />
            <polyline points="10 5 19 5 19 14" />
        </svg>;
    } elif toolId == "rectangle" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" />
        </svg>;
    } elif toolId == "diamond" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2 L22 12 L12 22 L2 12 Z" />
        </svg>;
    } elif toolId == "circle" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2">
            <ellipse cx="12" cy="12" rx="10" ry="7" />
        </svg>;
    } elif toolId == "text" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="4 7 4 4 20 4 20 7" />
            <line x1="9.5" y1="20" x2="14.5" y2="20" />
            <line x1="12" y1="4" x2="12" y2="20" />
        </svg>;
    } elif toolId == "image" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
            <circle cx="8.5" cy="8.5" r="1.5" />
            <polyline points="21 15 16 10 5 21" />
        </svg>;
    }
    return <span>{toolId}</span>;
}

def:pub TopBar(
    onToolChange: Callable[[str], None],
    onImageLoad: Callable[[any], None],
    onSave: Callable[[], None],
    onLoad: Callable[[any], None],
    onShowShortcuts: Callable[[], None],
    onShare: Callable[[], None],
    onCollab: Callable[[], None],
    onParticipantListToggle: Callable[[], None],
    onToggleToolLock: Callable[[], None],
    currentTool: str = "select",
    roomState: dict = {},
    participants: dict = {},
    isHost: bool = False,
    participantListOpen: bool = False,
    toolLocked: bool = False
) -> JsxElement {
    fileInputRef = useRef(None);
    jasketchFileInputRef = useRef(None);

    has menuOpen: bool = False;
    has sessionIdCopied: bool = False;

    toolIds = ["select", "freehand", "line", "arrow", "rectangle", "diamond", "circle", "text", "image"];
    toolLabels = {
        "select": "Select",
        "freehand": "Pencil",
        "line": "Line",
        "arrow": "Arrow",
        "rectangle": "Rectangle",
        "diamond": "Diamond",
        "circle": "Ellipse",
        "text": "Text",
        "image": "Image"
    };
    toolShortcuts = {
        "select": "1",
        "freehand": "2",
        "line": "3",
        "arrow": "4",
        "rectangle": "5",
        "diamond": "6",
        "circle": "7",
        "text": "8",
        "image": "9"
    };

    def handleToolClick(toolId: str) -> None {
        if toolId == "image" {
            if fileInputRef.current {
                fileInputRef.current.click();
            }
        } else {
            onToolChange(toolId);
        }
    }

    def handleSave() -> None {
        if onSave { onSave(); }
    }

    def handleShare() -> None {
        if onShare { onShare(); }
    }

    def handleCollab() -> None {
        if onCollab { onCollab(); }
    }

    def handleCopySessionId() -> None {
        sid = sessionStorage.getItem("jasketch_session_id") or "";
        if sid {
            navigator.clipboard.writeText(sid).then(lambda {
                sessionIdCopied = True;
                setTimeout(lambda { sessionIdCopied = False; }, 2000);
            });
        }
    }

    def handleJaSketchFileChange(e: ChangeEvent) -> None {
        files = e.target.files;
        if len(files) > 0 {
            if onLoad { onLoad(files[0]); }
            e.target.value = "";
        }
    }

    def handleFileChange(e: ChangeEvent) -> None {
        files = e.target.files;
        if len(files) > 0 {
            file = files[0];
            reader = new(FileReader);
            reader.onload = lambda (event: any) {
                img = new(Image);
                img.onload = lambda {
                    onImageLoad({
                        "type": "image",
                        "x": 100,
                        "y": 100,
                        "width": img.width,
                        "height": img.height,
                        "src": event.target.result
                    });
                };
                img.src = event.target.result;
            };
            reader.readAsDataURL(file);
            e.target.value = "";
        }
    }

    is_session_active = roomState and roomState.room_id;
    participant_sids = [k for k in participants.keys() if k != "__hostSid"];
    participant_count = len(participant_sids);
    collab_btn_class = "w-8 h-8 rounded-md flex items-center justify-center transition-all duration-150 " + (is_session_active and "text-green-600 bg-green-50 shadow-[0_0_8px_2px_rgba(34,197,94,0.35)] hover:bg-green-100" or "text-orange-600 hover:bg-orange-50");

    return <header className="topbar bg-white/95 border-b border-gray-200/60 flex-shrink-0 relative overflow-visible">
        <div className="h-11 px-3 flex items-center justify-between overflow-visible">
            <div className="flex items-center gap-2 min-w-[120px]">
                <div className="w-9 h-9 rounded-lg shadow-sm overflow-hidden">
                    <svg width="100%" height="100%" viewBox="0 0 512 512">
                        <defs>
                            <linearGradient id="lbg" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stopColor="#f97316"/><stop offset="100%" stopColor="#ea580c"/></linearGradient>
                            <filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="4" dy="4" stdDeviation="12" floodColor="rgba(0,0,0,0.3)"/></filter>
                        </defs>
                        <rect width="512" height="512" rx="108" ry="108" fill="url(#lbg)"/>
                        <g transform="translate(256,256) rotate(-45) translate(-256,-256)" filter="url(#sh)">
                            <rect x="181" y="60" width="150" height="320" rx="8" fill="white" opacity="0.95"/>
                            <rect x="181" y="195" width="150" height="30" fill="#06b6d4" opacity="0.45"/>
                            <rect x="181" y="245" width="150" height="30" fill="#06b6d4" opacity="0.45"/>
                            <polygon points="181,380 331,380 256,460" fill="#fde68a"/>
                            <polygon points="228,420 284,420 256,458" fill="#374151"/>
                            <rect x="181" y="60" width="150" height="50" rx="8" fill="#f9a8d4" opacity="0.9"/>
                            <rect x="181" y="100" width="150" height="12" fill="#e5e7eb" opacity="0.5"/>
                        </g>
                        <path d="M350 385 Q375 350 400 368 Q425 385 445 358" stroke="white" strokeWidth="10" fill="none" strokeLinecap="round" opacity="0.6"/>
                    </svg>
                </div>
                <span className="text-sm font-bold text-gray-700 tracking-tight">JaSketch</span>
            </div>

            <div className="flex items-center gap-0.5 bg-gray-50 rounded-lg px-1 py-0.5">
                {[
                    <button
                        key={toolId}
                        onClick={lambda { handleToolClick(toolId); }}
                        title={toolLabels[toolId] + (toolShortcuts[toolId] and (" (" + toolShortcuts[toolId] + ")") or "")}
                        className={"relative w-9 h-9 rounded-md flex flex-col items-center justify-center gap-0 transition-all duration-150 " + (currentTool == toolId and toolId != "image" and "bg-white text-orange-600 shadow-sm" or "text-gray-400 hover:bg-white/60 hover:text-gray-600")}
                    >
                        <ToolIcon toolId={toolId} size={17} color={currentTool == toolId and toolId != "image" and "#ea580c" or "currentColor"} />
                        {toolShortcuts[toolId] and <span className={"text-[7px] leading-none font-medium mt-px " + (currentTool == toolId and toolId != "image" and "text-orange-400" or "text-gray-300")}>{toolShortcuts[toolId]}</span> or None}
                    </button>
                    for toolId in toolIds
                ]}
                <div className="w-px h-5 bg-gray-200 mx-0.5"></div>
                <button
                    onClick={lambda { onToggleToolLock(); }}
                    title={("Tool stays selected -- click to unlock (Q)" if toolLocked else "Keep the tool selected after drawing (Q)")}
                    aria-pressed={toolLocked}
                    className={"relative w-9 h-9 rounded-md flex flex-col items-center justify-center transition-all duration-150 " + ("bg-white text-orange-600 shadow-sm" if toolLocked else "text-gray-400 hover:bg-white/60 hover:text-gray-600")}
                >
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <rect x="4" y="11" width="16" height="10" rx="2" />
                        {(<path d="M8 11V7a4 4 0 0 1 8 0v4" /> if toolLocked else <path d="M8 11V7a4 4 0 0 1 7.5-2" />)}
                    </svg>
                    <span className={"text-[7px] leading-none font-medium mt-px " + ("text-orange-400" if toolLocked else "text-gray-300")}>{"q"}</span>
                </button>
            </div>

            <div className="min-w-[150px] flex items-center justify-end gap-1 relative">
                <span className="text-[10px] text-gray-400 hidden lg:block mr-2">{"Scroll to pan | Ctrl+scroll to zoom"}</span>

                <button onClick={lambda {handleShare();}} title="Shareable link"
                    className="w-8 h-8 rounded-md flex items-center justify-center text-orange-600 hover:bg-orange-50 transition-all duration-150">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
                    </svg>
                </button>

                <button onClick={lambda {handleCollab();}} title={is_session_active and "Live Collaboration (Active)" or "Live Collaboration"}
                    className={collab_btn_class}>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                        <circle cx="9" cy="7" r="4" />
                        <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
                    </svg>
                </button>

                {is_session_active and participant_count > 0 and <button
                    onClick={lambda { if onParticipantListToggle { onParticipantListToggle(); } }}
                    title="Participants"
                    className={"h-8 px-2 rounded-md flex items-center gap-1 text-xs font-medium transition-all duration-150 " + (participantListOpen and "bg-green-100 text-green-700" or "text-gray-600 hover:bg-gray-100")}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <circle cx="12" cy="8" r="4" /><path d="M20 21a8 8 0 1 0-16 0" />
                    </svg>
                    {str(participant_count)}
                </button> or None}

                <button onClick={lambda { menuOpen = not menuOpen; }} title="Menu" className="w-8 h-8 rounded-md flex items-center justify-center text-gray-400">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <line x1="3" y1="6" x2="21" y2="6" /><line x1="3" y1="12" x2="21" y2="12" /><line x1="3" y1="18" x2="21" y2="18" />
                    </svg>
                </button>
            </div>
        </div>

        {menuOpen and <div className="fixed top-11 right-3 bg-white border border-gray-200 rounded-lg shadow-lg z-50 w-64 py-1">
            <div className="px-4 py-2 border-b border-gray-100">
                <div className="text-xs text-gray-400 mb-1">{"Session ID"}</div>
                <div className="flex items-center gap-2">
                    <span className="text-xs font-mono text-gray-600 flex-1 truncate">{sessionStorage.getItem("jasketch_session_id") or "-"}</span>
                    <button onClick={lambda { handleCopySessionId(); }}
                        className={"text-xs px-2 py-0.5 rounded transition-colors " + (sessionIdCopied and "bg-green-100 text-green-700" or "bg-gray-100 text-gray-600 hover:bg-gray-200")}>
                        {sessionIdCopied and "Copied!" or "Copy"}
                    </button>
                </div>
            </div>
            <button onClick={lambda { if jasketchFileInputRef.current { jasketchFileInputRef.current.click(); } menuOpen = False; }}
                className="w-full px-4 py-2.5 text-left text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-3">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
                </svg>
                {"Open"}
                <span className="ml-auto text-xs text-gray-400">{"Ctrl+O"}</span>
            </button>
            <button onClick={lambda { handleSave(); menuOpen = False; }}
                className="w-full px-4 py-2.5 text-left text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-3">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" />
                </svg>
                {"Save to disk"}
                <span className="ml-auto text-xs text-gray-400">{"Ctrl+S"}</span>
            </button>
            <div className="border-t border-gray-100 my-1"></div>
            <button onClick={lambda { handleShare(); menuOpen = False; }}
                className="w-full px-4 py-2.5 text-left text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-3">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
                </svg>
                {"Shareable link"}
            </button>
            <button onClick={lambda { handleCollab(); menuOpen = False; }}
                className="w-full px-4 py-2.5 text-left text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-3">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" />
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" />
                </svg>
                {"Live collaboration"}
            </button>
            <div className="border-t border-gray-100 my-1"></div>
            <button onClick={lambda { if onShowShortcuts { onShowShortcuts(); } menuOpen = False; }}
                className="w-full px-4 py-2.5 text-left text-sm text-gray-700 hover:bg-gray-50 flex items-center gap-3">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="2" y="6" width="20" height="12" rx="2" /><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M8 14h8" />
                </svg>
                {"Keyboard shortcuts"}
                <span className="ml-auto text-xs text-gray-400">{"?"}</span>
            </button>
        </div> or None}

        <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            onChange={handleFileChange}
            className="hidden"
        />
        <input
            ref={jasketchFileInputRef}
            type="file"
            accept=".jasketch"
            onChange={handleJaSketchFileChange}
            className="hidden"
        />
    </header>;
}
