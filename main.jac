"""Main entry point for JaSketch - Modern Whiteboard Application."""

import from typing { Any }
import os;
import from infrastructure.relay { start_relay_server }
import from infrastructure.share_server { initialize_share_server }

# Start relay by default unless explicitly disabled via JASKETCH_START_RELAY (helps avoid port conflicts when turned off in multi-process/reload scenarios)
glob _relay_started: Any = start_relay_server() if os.environ.get("JASKETCH_START_RELAY", "true").lower() == "true" else None;

# Initialize share server for encrypted scene storage
glob _share_server_ready: Any = initialize_share_server();

# Load and initialize agent
import from agent.server { _boot }
glob _agent_booted: Any = _boot();

cl {
    # Client-side imports
    import from react { useRef, useEffect }
    import from .components.layout.TopBar { TopBar }
    import from .components.layout.Sidebar { Sidebar }
    import from .components.layout.ChatPanel { ChatPanel }
    import from .components.layout.share_dialog { ShareDialog }
    import from .components.layout.participant_list { ParticipantList }
    import from .components.Canvas { Canvas }
    import from .components.canvas.join_name_overlay { JoinNameOverlay }
    import from .services.scene_sharing { import_from_share_backend }
    import ".styles.css";

    def:pub app() -> JsxElement {
        # Drawing tool state
        has currentTool: str = "select";
        has currentColor: str = "#000000";
        has currentStrokeWidth: int = 2;
        has currentFontSize: int = 24;
        has currentFontFamily: str = "Virgil";
        has currentOpacity: float = 1.0;
        has currentLineStyle: str = "solid";
        has currentCurveStyle: str = "curved";
        has currentFillColor: str = "transparent";

        # Selection state (updated by Canvas via callback)
        has selectedElement: any = None;

        # Chat panel state
        has chatOpen: bool = False;

        # Keyboard shortcuts help state
        has showShortcuts: bool = False;

        # Share dialog state
        has shareDialogOpen: bool = False;

        # Participant tracking and host state
        has participants: dict = {};
        has isHost: bool = False;
        has participantListOpen: bool = False;
        has shareDialogTab: str = "static";

        # Collaboration room state (room_id and room_key from URL hash)
        has roomState: dict = {"room_id": None, "room_key": None};

        # Joiner overlay: pending room from URL, show name prompt before activating
        has pendingRoom: dict = {"room_id": None, "room_key": None};
        has joinOverlayVisible: bool = False;

        # Share load error (set when a #json= URL fails to load)
        has shareLoadError: str = "";

        # Refs for cross-component communication
        clearCanvasRef = useRef(None);
        endSessionRef = useRef(None);
        updateUsernameRef = useRef(None);
        addElementRef = useRef(None);
        updateElementRef = useRef(None);
        saveRef = useRef(None);
        loadElementsRef = useRef(None);
        elementsForShareRef = useRef([]);
        setElementsRef = useRef(None);

        def handleDismissShareError() -> None {
            shareLoadError = "";
        }

        def handleUpdateElement(changes: dict) -> None {
            if selectedElement and updateElementRef.current {
                updateElementRef.current(selectedElement.id, changes);
            }
        }

        def load_share_from_url() -> None {
            hash = window.location.hash or "";
            if not hash {
                # Host case: URL has no hash, but might have been in a room before refresh
                stored_rid = sessionStorage.getItem("jasketch_room_id") or "";
                stored_rkey = sessionStorage.getItem("jasketch_room_key") or "";
                if stored_rid and stored_rkey {
                    roomState = {"room_id": stored_rid, "room_key": stored_rkey};
                    if sessionStorage.getItem("jasketch_is_host") == "true" {
                        isHost = True;
                    }
                }
                return;
            }
            if hash.startsWith("#json=") {
                # Static share: #json=<share_id>,<encryption_key>
                hash_part = hash[6:];
                parts = hash_part.split(",");
                share_id = str(parts[0] or "");
                share_key = str(parts[1] or "");
                if share_id and share_key and setElementsRef.current {
                    async def load_shared_scene() {
                        result = await import_from_share_backend(share_id, share_key);
                        if result["ok"] {
                            if setElementsRef.current {
                                setElementsRef.current(result["elements"]);
                            }
                        } else {
                            shareLoadError = str(result["error"] or "Failed to load shared canvas.");
                        }
                    }
                    load_shared_scene();
                } elif not (share_id and share_key) {
                    shareLoadError = "Share link is malformed — missing ID or key.";
                }
            } elif hash.startsWith("#room=") {
                # Collaboration room: #room=<room_id>,<room_key>
                room_hash_part = hash[6:];
                room_parts = room_hash_part.split(",");
                room_id = room_parts[0] or "";
                room_key = room_parts[1] or "";
                if room_id and room_key {
                    # If this tab already has a session ID in sessionStorage, it's a reload —
                    # auto-rejoin silently using the stored username instead of showing the overlay.
                    existing_sid = sessionStorage.getItem("jasketch_session_id");
                    if existing_sid {
                        roomState = {"room_id": room_id, "room_key": room_key};
                    } else {
                        pendingRoom = {"room_id": room_id, "room_key": room_key};
                        joinOverlayVisible = True;
                    }
                }
            }
        }

        # Parse URL hash on mount for share links
        useEffect(
            lambda () -> any {
                load_share_from_url();
                return None;
            },
            []
        );

        # Pre-compute share load error banner
        share_error_banner = None;
        if shareLoadError {
            share_error_banner = <div className="fixed top-4 left-1/2 -translate-x-1/2 bg-red-600 text-white px-6 py-3 rounded-lg shadow-lg text-sm z-50 flex items-center gap-3">
                <span>{shareLoadError}</span>
                <button onClick={lambda { handleDismissShareError(); }} className="text-white/80 hover:text-white font-bold text-lg leading-none">{"×"}</button>
            </div>;
        }

        return <div className="h-screen flex flex-col overflow-hidden bg-white">
            <TopBar
                currentTool={currentTool}
                onToolChange={lambda (tool: any) { currentTool = tool; }}
                onImageLoad={lambda (element: any) {
                    if addElementRef.current {
                        addElementRef.current(element);
                    }
                }}
                onSave={lambda { if saveRef.current { saveRef.current(); } }}
                onLoad={lambda (file: any) { if loadElementsRef.current { loadElementsRef.current(file); } }}
                onShowShortcuts={lambda { showShortcuts = not showShortcuts; }}
                onShare={lambda { shareDialogTab = "static"; shareDialogOpen = True; }}
                onCollab={lambda { shareDialogTab = "collab"; shareDialogOpen = True; }}
                roomState={roomState}
                participants={participants}
                isHost={isHost}
                participantListOpen={participantListOpen}
                onParticipantListToggle={lambda { participantListOpen = not participantListOpen; }}
            />

            <div className="flex-1 overflow-hidden relative">
                <div className="absolute left-3 top-3 z-10">
                    <Sidebar
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentOpacity={currentOpacity}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentLineStyle={currentLineStyle}
                        currentCurveStyle={currentCurveStyle}
                        currentFillColor={currentFillColor}
                        selectedElement={selectedElement}
                        onColorChange={lambda (color: any) { currentColor = color; }}
                        onStrokeWidthChange={lambda (width: any) { currentStrokeWidth = width; }}
                        onOpacityChange={lambda (opacity: any) { currentOpacity = opacity; }}
                        onFontSizeChange={lambda (size: any) { currentFontSize = size; }}
                        onFontFamilyChange={lambda (font: any) { currentFontFamily = font; }}
                        onLineStyleChange={lambda (style: any) { currentLineStyle = style; }}
                        onCurveStyleChange={lambda (style: any) { currentCurveStyle = style; }}
                        onFillColorChange={lambda (color: any) { currentFillColor = color; }}
                        onUpdateElement={handleUpdateElement}
                    />
                </div>

                <div className="w-full h-full">
                    <Canvas
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentOpacity={currentOpacity}
                        currentLineStyle={currentLineStyle}
                        currentCurveStyle={currentCurveStyle}
                        currentFillColor={currentFillColor}
                        roomState={roomState}
                        clearCanvasRef={clearCanvasRef}
                        addElementRef={addElementRef}
                        updateElementRef={updateElementRef}
                        saveRef={saveRef}
                        loadElementsRef={loadElementsRef}
                        elementsForShareRef={elementsForShareRef}
                        setElementsRef={setElementsRef}
                        endSessionRef={endSessionRef}
                        updateUsernameRef={updateUsernameRef}
                        onParticipantsChange={lambda (p: any) { participants = p; }}
                        onSessionEnded={lambda {
                            sessionStorage.removeItem("jasketch_room_id");
                            sessionStorage.removeItem("jasketch_room_key");
                            sessionStorage.removeItem("jasketch_is_host");
                            roomState = {"room_id": None, "room_key": None};
                            isHost = False;
                            shareDialogOpen = False;
                            participantListOpen = False;
                        }}
                        onSelectionChange={lambda (sel: any) { selectedElement = sel; }}
                        onToolChange={lambda (tool: any) { currentTool = tool; }}
                        showShortcuts={showShortcuts}
                        onToggleShortcuts={lambda { showShortcuts = not showShortcuts; }}
                    />
                </div>

                <ChatPanel
                    isOpen={chatOpen}
                    onToggle={lambda { chatOpen = not chatOpen; }}
                />

                <ShareDialog
                    is_open={shareDialogOpen}
                    on_close={lambda { shareDialogOpen = False; }}
                    elements_ref={elementsForShareRef}
                    room_state={roomState}
                    default_tab={shareDialogTab}
                    on_join_room={lambda (room_id: str, room_key: str) {
                        sessionStorage.setItem("jasketch_room_id", room_id);
                        sessionStorage.setItem("jasketch_room_key", room_key);
                        sessionStorage.setItem("jasketch_is_host", "true");
                        roomState = {"room_id": room_id, "room_key": room_key};
                        isHost = True;
                    }}
                    on_end_session={lambda {
                        es_rid = roomState["room_id"] or "";
                        if endSessionRef.current and es_rid { endSessionRef.current(es_rid); }
                    }}
                    on_username_set={lambda (room_id: str, name: str) {
                        if updateUsernameRef.current { updateUsernameRef.current(room_id, name); }
                    }}
                />

                <div className="absolute bottom-3 right-4 z-10 pointer-events-none">
                    <span className="text-[10px] tracking-wider text-gray-300 font-medium uppercase">
                        {"Powered by Jaseci"}
                    </span>
                </div>

                {participantListOpen and roomState and roomState["room_id"] and <div className="absolute top-11 right-1 z-50">
                    <ParticipantList
                        participants={participants}
                        isHost={isHost}
                        mySessionId={sessionStorage.getItem("jasketch_session_id") or ""}
                        onClose={lambda { participantListOpen = False; }}
                        onRenameMe={lambda (name: any) {
                            localStorage.setItem("jasketch_username", name);
                            if updateUsernameRef.current and roomState["room_id"] {
                                updateUsernameRef.current(roomState["room_id"], name);
                            }
                        }}
                    />
                </div> or None}
            </div>

            {shareLoadError and <div className="fixed top-4 left-1/2 -translate-x-1/2 bg-red-600 text-white px-6 py-3 rounded-lg shadow-lg text-sm z-50 flex items-center gap-3">
                <span>{shareLoadError}</span>
                <button onClick={lambda { handleDismissShareError(); }} className="text-white/80 hover:text-white font-bold text-lg leading-none">{"×"}</button>
            </div> or None}

            {joinOverlayVisible and <JoinNameOverlay
                on_join={lambda (name: any) {
                    localStorage.setItem("jasketch_username", name);
                    sessionStorage.setItem("jasketch_room_id", pendingRoom["room_id"]);
                    sessionStorage.setItem("jasketch_room_key", pendingRoom["room_key"]);
                    roomState = pendingRoom;
                    joinOverlayVisible = False;
                }}
            /> or None}
        </div>;
    }
}
