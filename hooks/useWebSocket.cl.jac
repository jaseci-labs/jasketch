import from react { useRef, useEffect }
import from "..services.scene_sharing" { encrypt_scene, decrypt_scene }
import from "..services.ws_endpoint" { ws_url, ws_should_retry_under_prefix }

def:pub useWebSocket(elementsHook: dict, viewportHook: dict, canvasRef: any, canvasHook: dict, roomState: dict = None, onSessionEnded: any = None) -> dict {
    wsRef = useRef(None);
    connectedRef = useRef(False);
    elementsHookRef = useRef(elementsHook);
    viewportHookRef = useRef(viewportHook);
    canvasRefRef = useRef(canvasRef);
    canvasHookRef = useRef(canvasHook);
    roomStateRef = useRef(roomState or {});
    onSessionEndedRef = useRef(None);
    cursorStatesRef = useRef({});
    participantsRef = useRef({});
    hostSessionIdRef = useRef("");
    isApplyingRemoteRef = useRef(False);
    sendRoomBroadcastRef = useRef(None);
    sendRoomPreviewRef = useRef(None);
    sendCursorBroadcastRef = useRef(None);
    sendEndSessionRef = useRef(None);
    sendUpdateUsernameRef = useRef(None);
    joinRoomRef = useRef(None);
    reconnectTimerRef = useRef(None);
    has cursorStates: dict = {};
    has participants: dict = {};
    has hostSessionId: str = "";

    # Keep refs current to avoid stale closures
    elementsHookRef.current = elementsHook;
    viewportHookRef.current = viewportHook;
    canvasRefRef.current = canvasRef;
    canvasHookRef.current = canvasHook;
    roomStateRef.current = roomState or {};
    onSessionEndedRef.current = onSessionEnded;

    def getRelayUrl() -> str {
        # The relay is an endpoint of this app now, not a server on its own port.
        return str(ws_url("function/jasketch_relay"));
    }

    """Send one relay frame. `kind` names the exchange; see infrastructure/relay.jac."""
    def relaySend(frame: dict) -> None {
        ws = wsRef.current;
        if not ws { return; }
        if not connectedRef.current { return; }
        ws.send(JSON.stringify(frame));
    }

    def currentRoomId() -> str {
        state: any = roomStateRef.current or {};
        return state.room_id or "";
    }

    def currentRoomKey() -> str {
        state: any = roomStateRef.current or {};
        return state.room_key or "";
    }

    def sendResponse(ws: any, requestId: str, success: bool, data: any) -> None {
        ws.send(JSON.stringify({
            "kind": "response",
            "session_id": getSessionId(),
            "request_id": requestId,
            "success": success,
            "data": data
        }));
    }

    def sendError(ws: any, requestId: str, error: str) -> None {
        ws.send(JSON.stringify({
            "kind": "response",
            "session_id": getSessionId(),
            "request_id": requestId,
            "success": False,
            "error": error
        }));
    }

    """Route one broadcast frame.

    Every connected tab receives every envelope this endpoint yields, so the
    first job is deciding whether this one is ours: room traffic is matched on
    room_id, controller traffic on session_id. Scene payloads are ciphertext and
    are only decryptable by tabs holding the room key anyway."""
    async def handleMessage(ws: any, event: any) -> None {
        envelope: any = JSON.parse(event.data);

        # Transport control frames and the stream terminator carry no relay payload.
        if envelope.type == "ping" or envelope.type == "pong" or envelope.type == "refreshed" {
            return;
        }
        if envelope.ok == False or envelope.type != "chunk" {
            return;
        }
        msg: any = envelope.data or {};
        msg_type = msg.kind or "";

        my_room = currentRoomId();
        my_sid = getSessionId();

        # Room traffic addressed to a room we are not in.
        if msg.room_id and msg.room_id != my_room {
            return;
        }
        # room_joined and command are addressed TO one session; everything else
        # describes what somebody ELSE did, so our own echoes are dropped.
        addressed_to_me = msg_type == "room_joined" or msg_type == "command";
        if msg.session_id and (msg.session_id == my_sid) != addressed_to_me {
            return;
        }

        if msg_type == "room_joined" {
            # Joined a collaboration room successfully. The key is ours alone --
            # it lives in the URL fragment and never reaches the server.
            roomStateRef.current = {"room_id": msg.room_id, "room_key": currentRoomKey()};
            console.log("[JaSketch] Joined room: " + msg.room_id);
            # Initialize self in participants
            rj_sid = getSessionId();
            rj_name = localStorage.getItem("jasketch_username") or "Anonymous";
            rj_color = msg.cursor_color or "#999999";
            rj_parts = {**participantsRef.current};
            rj_parts[rj_sid] = {"username": rj_name, "color": rj_color};
            # Add all existing room members sent by the server
            if msg.members {
                rj_member_sids = msg.members.keys();
                for rj_msid in rj_member_sids {
                    rj_parts[rj_msid] = {
                        "username": msg.members[rj_msid].username or "Anonymous",
                        "color": msg.members[rj_msid].color or "#999999"
                    };
                }
            }
            participantsRef.current = rj_parts;
            participants = {**rj_parts};
            # Store host session ID from server
            if msg.host_session_id {
                hostSessionIdRef.current = msg.host_session_id;
                hostSessionId = msg.host_session_id;
            }
            return;
        }

        if msg_type == "room_update" {
            upd_payload = msg.payload or "";
            upd_key = currentRoomKey();
            if upd_payload and upd_key {
                upd_elements = await decrypt_scene(upd_payload, upd_key);
                if upd_elements {
                    upd_hook = elementsHookRef.current;
                    isApplyingRemoteRef.current = True;
                    upd_hook.setElementsReplaceAll(upd_elements);
                }
            }
            return;
        }

        if msg_type == "cursor_update" {
            # Another member's cursor position
            cu_sid = msg.session_id or "";
            # Ignore own cursor echoes (relay broadcasts to all during update_username)
            if cu_sid == getSessionId() { return; }
            cu_updated = {**cursorStatesRef.current};
            cu_updated[cu_sid] = {
                "username": msg.username or "Anonymous",
                "color": msg.cursor_color or "#999999",
                "x": msg.x or 0.0,
                "y": msg.y or 0.0
            };
            cursorStatesRef.current = cu_updated;
            cursorStates = {**cu_updated};
            # Always upsert participant info (handles users not yet seen via room_joined)
            if cu_sid {
                cu_parts = {**participantsRef.current};
                cu_existing = cu_parts[cu_sid] or {};
                cu_parts[cu_sid] = {**cu_existing, **{
                    "username": msg.username or "Anonymous",
                    "color": msg.cursor_color or "#999999"
                }};
                participantsRef.current = cu_parts;
                participants = {**cu_parts};
            }
            return;
        }

        if msg_type == "room_member_joined" {
            console.log("[JaSketch] Member joined: " + msg.username);
            # Add new member to participants
            rmj_sid = msg.session_id or "";
            if rmj_sid {
                rmj_parts = {**participantsRef.current};
                rmj_parts[rmj_sid] = {"username": msg.username or "Anonymous", "color": msg.cursor_color or "#999999"};
                participantsRef.current = rmj_parts;
                participants = {**rmj_parts};
            }
            sync_hook = elementsHookRef.current;
            sync_elems = (sync_hook.elementsRef and sync_hook.elementsRef.current) or sync_hook.elements;
            # Only broadcast if we have elements (avoid wiping a joiner's canvas with empty array)
            if sync_elems and sync_elems.length > 0 and sendRoomBroadcastRef.current {
                sendRoomBroadcastRef.current(sync_elems);
            }
            return;
        }

        if msg_type == "room_member_left" {
            left_sid = msg.session_id or "";
            if left_sid {
                cl_updated = {**cursorStatesRef.current};
                cl_filtered = {cl_k: cl_v for (cl_k, cl_v) in cl_updated.items() if cl_k != left_sid};
                cursorStatesRef.current = cl_filtered;
                cursorStates = {**cl_filtered};
                # Remove from participants
                rml_parts = {**participantsRef.current};
                rml_filtered = {rml_k: rml_v for (rml_k, rml_v) in rml_parts.items() if rml_k != left_sid};
                participantsRef.current = rml_filtered;
                participants = {**rml_filtered};
            }
            console.log("[JaSketch] Member left");
            return;
        }

        if msg_type == "session_ended" {
            console.log("[JaSketch] Collaboration session ended");
            roomStateRef.current = {"room_id": None, "room_key": None};
            cursorStatesRef.current = {};
            cursorStates = {};
            participantsRef.current = {};
            participants = {};
            if onSessionEndedRef.current { onSessionEndedRef.current(); }
            return;
        }

        # Everything below is a controller command addressed to this canvas
        # (the MCP bridge): read or mutate the canvas, then answer by request_id.
        if msg_type != "command" {
            return;
        }
        requestId = msg.request_id;
        action = msg.action;
        data: any = msg.data or {};
        hook = elementsHookRef.current;

        if action == "addElement" {
            hook.addElement(data);
            addedId = data.id or "";
            sendResponse(ws, requestId, True, {"id": addedId, "action": "created"});
        } elif action == "addMultipleElements" {
            items = data.elements or [];
            hook.addMultipleElements(items);
            addedIds = [];
            for it in items {
                addedIds.append(it.id or "");
            }
            sendResponse(ws, requestId, True, {"ids": addedIds, "count": len(items), "action": "created"});
        } elif action == "getElements" {
            # Use elementsRef for synchronous read (avoids stale React state snapshot)
            elems = (hook.elementsRef and hook.elementsRef.current) or hook.elements;
            result = [];
            for el in elems {
                if el and (not data.type or el.type == data.type) {
                    result.append({"id": el.id, "element": el});
                }
            }
            sendResponse(ws, requestId, True, {"elements": result, "total": elems.length});
        } elif action == "updateElement" {
            targetId = data.id;
            changes = data.changes or {};
            updateElems = hook.elements;
            foundEl = None;
            for el in updateElems {
                if el and el.id == targetId {
                    foundEl = el;
                }
            }
            if foundEl {
                updated = {**foundEl, **changes};
                hook.updateElement(targetId, updated);
                sendResponse(ws, requestId, True, {"id": targetId, "action": "updated"});
            } else {
                sendError(ws, requestId, "Element not found: " + targetId);
            }
        } elif action == "removeElement" {
            hook.removeElement(data.id);
            sendResponse(ws, requestId, True, {"id": data.id, "action": "deleted"});
        } elif action == "removeMultipleElements" {
            hook.removeMultipleElements(data.ids or []);
            sendResponse(ws, requestId, True, {"ids": data.ids, "action": "deleted"});
        } elif action == "clearElements" {
            hook.clearElements();
            sendResponse(ws, requestId, True, {"action": "cleared"});
        } elif action == "getViewport" {
            vp = viewportHookRef.current;
            canvas = canvasRefRef.current;
            canvasWidth = 0;
            canvasHeight = 0;
            if canvas and canvas.current {
                rect = canvas.current.getBoundingClientRect();
                canvasWidth = rect.width;
                canvasHeight = rect.height;
            }
            # Calculate visible area in world coordinates
            visibleX = (0 - vp.panOffset.x) / vp.zoom;
            visibleY = (0 - vp.panOffset.y) / vp.zoom;
            visibleWidth = canvasWidth / vp.zoom;
            visibleHeight = canvasHeight / vp.zoom;
            sendResponse(ws, requestId, True, {
                "zoom": vp.zoom,
                "panOffset": vp.panOffset,
                "canvasWidth": canvasWidth,
                "canvasHeight": canvasHeight,
                "visibleArea": {
                    "x": visibleX,
                    "y": visibleY,
                    "width": visibleWidth,
                    "height": visibleHeight
                }
            });
        } elif action == "getCanvasSnapshot" {
            snapshotCvs = canvasRefRef.current;
            if snapshotCvs and snapshotCvs.current {
                # Use JPEG at 0.6 quality for smaller payload and faster transfer
                dataUrl = snapshotCvs.current.toDataURL("image/jpeg", 0.6);
                sendResponse(ws, requestId, True, {"snapshot": dataUrl});
            } else {
                sendError(ws, requestId, "Canvas not available");
            }
        } elif action == "getBoundingBox" {
            bbElems = hook.elements;
            if bbElems.length == 0 {
                sendResponse(ws, requestId, True, {"boundingBox": None, "elementCount": 0});
            } else {
                bbMinX = 999999;
                bbMinY = 999999;
                bbMaxX = -999999;
                bbMaxY = -999999;
                for bbEl in bbElems {
                    if bbEl.type == "line" or bbEl.type == "arrow" {
                        if bbEl.x1 < bbMinX { bbMinX = bbEl.x1; }
                        if bbEl.y1 < bbMinY { bbMinY = bbEl.y1; }
                        if bbEl.x2 > bbMaxX { bbMaxX = bbEl.x2; }
                        if bbEl.y2 > bbMaxY { bbMaxY = bbEl.y2; }
                        if bbEl.x1 > bbMaxX { bbMaxX = bbEl.x1; }
                        if bbEl.y1 > bbMaxY { bbMaxY = bbEl.y1; }
                        if bbEl.x2 < bbMinX { bbMinX = bbEl.x2; }
                        if bbEl.y2 < bbMinY { bbMinY = bbEl.y2; }
                    } elif bbEl.type == "freehand" and bbEl.points and bbEl.points.length > 0 {
                        for bbPt in bbEl.points {
                            if bbPt.x < bbMinX { bbMinX = bbPt.x; }
                            if bbPt.y < bbMinY { bbMinY = bbPt.y; }
                            if bbPt.x > bbMaxX { bbMaxX = bbPt.x; }
                            if bbPt.y > bbMaxY { bbMaxY = bbPt.y; }
                        }
                    } elif bbEl.type == "text" {
                        textW = (bbEl.fontSize or 16) * (bbEl.text or "").length * 0.6;
                        textH = (bbEl.fontSize or 16) * 1.2;
                        if bbEl.x < bbMinX { bbMinX = bbEl.x; }
                        if bbEl.y < bbMinY { bbMinY = bbEl.y; }
                        if bbEl.x + textW > bbMaxX { bbMaxX = bbEl.x + textW; }
                        if bbEl.y + textH > bbMaxY { bbMaxY = bbEl.y + textH; }
                    } else {
                        # rectangle, circle, diamond, image
                        if bbEl.x != undefined {
                            if bbEl.x < bbMinX { bbMinX = bbEl.x; }
                            if bbEl.y < bbMinY { bbMinY = bbEl.y; }
                            if bbEl.x + (bbEl.width or 0) > bbMaxX { bbMaxX = bbEl.x + (bbEl.width or 0); }
                            if bbEl.y + (bbEl.height or 0) > bbMaxY { bbMaxY = bbEl.y + (bbEl.height or 0); }
                        }
                    }
                }
                sendResponse(ws, requestId, True, {
                    "boundingBox": {
                        "x": bbMinX,
                        "y": bbMinY,
                        "width": bbMaxX - bbMinX,
                        "height": bbMaxY - bbMinY
                    },
                    "elementCount": bbElems.length
                });
            }
        } elif action == "getElementById" {
            findElems = hook.elements;
            findTargetId = data.id;
            findEl = None;
            for el in findElems {
                if el and el.id == findTargetId {
                    findEl = el;
                }
            }
            if findEl {
                sendResponse(ws, requestId, True, {"id": findTargetId, "element": findEl});
            } else {
                sendError(ws, requestId, "Element not found: " + findTargetId);
            }
        } elif action == "setElements" {
            newElements = data.elements or [];
            # Directly replace elements to avoid React state sync race condition
            # (clearElements + addMultipleElements would read stale state)
            hook.setElementsReplaceAll(newElements);

            # Auto-fit viewport: compute bounding box of all elements, then zoom to fit with 60px padding
            setVp = viewportHookRef.current;
            setCvs = canvasRefRef.current;
            setCvWidth = 0;
            setCvHeight = 0;
            if setCvs and setCvs.current {
                rect = setCvs.current.getBoundingClientRect();
                setCvWidth = rect.width;
                setCvHeight = rect.height;
            }

            # Calculate bounding box of all newly set elements
            if newElements.length > 0 {
                bbMinX = 999999;
                bbMinY = 999999;
                bbMaxX = -999999;
                bbMaxY = -999999;
                for el in newElements {
                    if el.type == "line" or el.type == "arrow" {
                        if el.x1 < bbMinX { bbMinX = el.x1; }
                        if el.y1 < bbMinY { bbMinY = el.y1; }
                        if el.x2 > bbMaxX { bbMaxX = el.x2; }
                        if el.y2 > bbMaxY { bbMaxY = el.y2; }
                        if el.x1 > bbMaxX { bbMaxX = el.x1; }
                        if el.y1 > bbMaxY { bbMaxY = el.y1; }
                        if el.x2 < bbMinX { bbMinX = el.x2; }
                        if el.y2 < bbMinY { bbMinY = el.y2; }
                    } elif el.type == "freehand" and el.points and el.points.length > 0 {
                        for pt in el.points {
                            if pt.x < bbMinX { bbMinX = pt.x; }
                            if pt.y < bbMinY { bbMinY = pt.y; }
                            if pt.x > bbMaxX { bbMaxX = pt.x; }
                            if pt.y > bbMaxY { bbMaxY = pt.y; }
                        }
                    } elif el.type == "text" {
                        textW = (el.fontSize or 16) * (el.text or "").length * 0.6;
                        textH = (el.fontSize or 16) * 1.2;
                        if el.x < bbMinX { bbMinX = el.x; }
                        if el.y < bbMinY { bbMinY = el.y; }
                        if el.x + textW > bbMaxX { bbMaxX = el.x + textW; }
                        if el.y + textH > bbMaxY { bbMaxY = el.y + textH; }
                    } else {
                        # rectangle, circle, diamond, image
                        if el.x != undefined {
                            if el.x < bbMinX { bbMinX = el.x; }
                            if el.y < bbMinY { bbMinY = el.y; }
                            if el.x + (el.width or 0) > bbMaxX { bbMaxX = el.x + (el.width or 0); }
                            if el.y + (el.height or 0) > bbMaxY { bbMaxY = el.y + (el.height or 0); }
                        }
                    }
                }

                # Compute zoom to fit with 60px padding on all sides, capped at 2x
                padding = 60;
                bbWidth = bbMaxX - bbMinX;
                bbHeight = bbMaxY - bbMinY;
                zoomX = (setCvWidth - 2 * padding) / bbWidth;
                zoomY = (setCvHeight - 2 * padding) / bbHeight;
                newZoom = Math.min(zoomX, zoomY, 2.0);
                newZoom = Math.max(newZoom, 0.1);

                # Center diagram with new zoom
                centerX = (bbMinX + bbMaxX) / 2;
                centerY = (bbMinY + bbMaxY) / 2;
                newPanX = setCvWidth / 2 - centerX * newZoom;
                newPanY = setCvHeight / 2 - centerY * newZoom;

                # Update viewport via viewportHook
                if setVp {
                    setVp.setZoom(newZoom);
                    setVp.setPanOffset({"x": newPanX, "y": newPanY});
                }
            }

            sendResponse(ws, requestId, True, {"count": newElements.length, "action": "set"});
        } else {
            sendError(ws, requestId, "Unknown action: " + action);
        }
    }

    def getSessionId() -> Any {
        # Stable per browser tab — survives page refresh, cleared when tab closes
        key = "jasketch_session_id";
        sid = sessionStorage.getItem(key);
        if not sid {
            sid = crypto.randomUUID();
            sessionStorage.setItem(key, sid);
        }
        return sid;
    }

    """Publish the scene to the room, encrypted under the room key."""
    async def sendRoomBroadcast(bcast_elements: list) -> None {
        bcast_room = currentRoomId();
        bcast_key = currentRoomKey();
        if not (bcast_room and bcast_key) {
            return;
        }
        # Filter out draft elements (id="__draft__") received from remote previews
        bcast_filtered = [];
        bcast_fi = 0;
        while bcast_fi < len(bcast_elements) {
            if bcast_elements[bcast_fi] and bcast_elements[bcast_fi].id != "__draft__" {
                bcast_filtered.append(bcast_elements[bcast_fi]);
            }
            bcast_fi = bcast_fi + 1;
        }
        bcast_cipher = await encrypt_scene(bcast_filtered, bcast_key);
        if not bcast_cipher { return; }
        relaySend({
            "kind": "room_broadcast",
            "room_id": bcast_room,
            "session_id": getSessionId(),
            "payload": bcast_cipher
        });
    }
    sendRoomBroadcastRef.current = sendRoomBroadcast;

    """Like sendRoomBroadcast but keeps draft elements, for live drawing preview."""
    async def sendRoomPreview(prev_elements: list) -> None {
        prev_room = currentRoomId();
        prev_key = currentRoomKey();
        if not (prev_room and prev_key) {
            return;
        }
        prev_cipher = await encrypt_scene(prev_elements, prev_key);
        if not prev_cipher { return; }
        relaySend({
            "kind": "room_broadcast",
            "room_id": prev_room,
            "session_id": getSessionId(),
            "payload": prev_cipher
        });
    }
    sendRoomPreviewRef.current = sendRoomPreview;

    def sendCursorBroadcast(cur_x: float, cur_y: float, cur_username: str) -> None {
        cur_room = currentRoomId();
        if not cur_room { return; }
        relaySend({
            "kind": "cursor_move",
            "room_id": cur_room,
            "session_id": getSessionId(),
            "x": cur_x,
            "y": cur_y,
            "username": cur_username
        });
    }
    sendCursorBroadcastRef.current = sendCursorBroadcast;

    def joinRoom(jr_room_id: str, jr_username: str) -> None {
        relaySend({
            "kind": "join_room",
            "room_id": jr_room_id,
            "session_id": getSessionId(),
            "username": jr_username
        });
    }
    joinRoomRef.current = joinRoom;

    def sendEndSession(es_room_id: str) -> None {
        relaySend({
            "kind": "end_session",
            "room_id": es_room_id,
            "session_id": getSessionId()
        });
    }
    sendEndSessionRef.current = sendEndSession;

    def sendUpdateUsername(uu_room_id: str, uu_username: str) -> None {
        relaySend({
            "kind": "update_username",
            "room_id": uu_room_id,
            "session_id": getSessionId(),
            "username": uu_username
        });
        # Optimistic self-update
        uu_sid = getSessionId();
        if participantsRef.current[uu_sid] {
            uu_parts = {**participantsRef.current};
            uu_parts[uu_sid] = {**uu_parts[uu_sid], **{"username": uu_username}};
            participantsRef.current = uu_parts;
            participants = {**uu_parts};
        }
    }
    sendUpdateUsernameRef.current = sendUpdateUsername;

    def connect() -> None {
        url = getRelayUrl();
        ws = new(WebSocket, url);

        ws.onopen = lambda {
            connectedRef.current = True;
            # Mint the tab's session id NOW, not on first send. It is how the MCP
            # bridge addresses this canvas (JASKETCH_SESSION_ID), and the docs
            # tell people to read it out of sessionStorage -- which returned null
            # on any tab that had not yet drawn or joined a room.
            console.log("[JaSketch] Relay connected at " + url + " (session " + getSessionId() + ")");
            # Announce this canvas so callers can be told "that tab is gone"
            # immediately, instead of waiting out a request timeout.
            relaySend({"kind": "hello", "session_id": getSessionId()});

            # Auto-rejoin: check roomStateRef first (normal reconnect), then sessionStorage
            # (handles host refresh where React state reset before onopen fires)
            lr_room_state = roomStateRef.current;
            lr_rid = "";
            if lr_room_state and lr_room_state.room_id {
                lr_rid = lr_room_state.room_id;
            } else {
                lr_rid = sessionStorage.getItem("jasketch_room_id") or "";
            }
            if lr_rid {
                lr_name = localStorage.getItem("jasketch_username") or "Anonymous";
                setTimeout(lambda {
                    if joinRoomRef.current {
                        joinRoomRef.current(lr_rid, lr_name);
                    }
                }, 100);
            }
        };

        ws.onmessage = lambda (event: any) {
            handleMessage(ws, event);
        };

        ws.onclose = lambda (ev: any) {
            connectedRef.current = False;
            wsRef.current = None;
            # 1008 means the gateway does not route /ws at the root; retry at
            # once under the service prefix rather than waiting out the backoff.
            retry_now = ws_should_retry_under_prefix(ev.code or 0);
            reconnectTimerRef.current = setTimeout(lambda {
                connect();
            }, 50 if retry_now else 3000);
        };

        ws.onerror = lambda {
            # Suppress errors, onclose will handle reconnect
            x = 0;
        };

        wsRef.current = ws;
    }

    # Acquire-and-release in ONE effect: `can with entry`/`can with exit` compile
    # to separate useEffect closures, so a handle created in entry is invisible to
    # exit and the removeEventListener would silently no-op.
    useEffect(lambda () -> any {
        connect();
        # Presence keepalive: the relay reaps members it has not heard from,
        # because a broadcast endpoint never learns that a socket closed.
        heartbeat = setInterval(lambda {
            hb_room = currentRoomId();
            if hb_room {
                relaySend({
                    "kind": "heartbeat",
                    "room_id": hb_room,
                    "session_id": getSessionId()
                });
            }
        }, 15000);
        return lambda {
            clearInterval(heartbeat);
            if reconnectTimerRef.current {
                clearTimeout(reconnectTimerRef.current);
            }
            if wsRef.current {
                hb_leave_room = currentRoomId();
                if hb_leave_room {
                    relaySend({
                        "kind": "leave_room",
                        "room_id": hb_leave_room,
                        "session_id": getSessionId()
                    });
                }
                wsRef.current.close();
            }
        };
    }, []);


    can with [roomState["room_id"]] entry {
        # Split rather than one `a and b and c and d` chain: folding the raw
        # WebSocket handle into an and-chain made the whole guard read false and
        # the join was silently never sent. Keep JS handles out of boolean chains.
        jr_room_id = roomState["room_id"] if roomState else "";
        if jr_room_id {
            if connectedRef.current {
                jr_stored_name = localStorage.getItem("jasketch_username") or "Anonymous";
                joinRoomRef.current(jr_room_id, jr_stored_name);
            }
        }
        return lambda { };
    }

    return {
        "connected": connectedRef.current,
        "isApplyingRemoteRef": isApplyingRemoteRef,
        "sendRoomBroadcastRef": sendRoomBroadcastRef,
        "sendRoomPreviewRef": sendRoomPreviewRef,
        "sendCursorBroadcastRef": sendCursorBroadcastRef,
        "sendEndSessionRef": sendEndSessionRef,
        "sendUpdateUsernameRef": sendUpdateUsernameRef,
        "cursorStates": cursorStates,
        "participants": participants,
        "hostSessionId": hostSessionId
    };
}
