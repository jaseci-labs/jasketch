import from react { useRef }

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
        # Auto-detect: use wss:// for deployed, ws:// for localhost
        protocol = window.location.protocol;
        host = window.location.hostname;
        port = window.location.port;

        if host == "localhost" or host == "127.0.0.1" {
            # Local dev: relay runs on port 9601
            return "ws://" + host + ":9601";
        }
        # Deployed: relay exposed on /ws path via same host
        wsProtocol = "ws:";
        if protocol == "https:" {
            wsProtocol = "wss:";
        }
        return wsProtocol + "//" + host + "/ws";
    }

    def sendResponse(ws: any, requestId: str, success: bool, data: any) -> None {
        msg = {"role": "canvas", "requestId": requestId, "success": success, "data": data};
        ws.send(JSON.stringify(msg));
    }

    def sendError(ws: any, requestId: str, error: str) -> None {
        msg = {"requestId": requestId, "success": False, "error": error};
        ws.send(JSON.stringify(msg));
    }

    def handleMessage(ws: any, event: any) -> None {
        msg = JSON.parse(event.data);

        # Skip relay control messages
        if msg.type == "registered" or msg.type == "canvasConnected" or msg.type == "canvasDisconnected" {
            return;
        }

        # Handle room collaboration messages
        msg_type = msg.type or "";
        if msg_type == "room_joined" {
            # Joined a collaboration room successfully
            roomStateRef.current = {
                "room_id": msg.roomId,
                "room_key": msg.roomKey or ""
            };
            console.log("[JaSketch] Joined room: " + msg.roomId);
            # Initialize self in participants
            rj_sid = getSessionId();
            rj_name = localStorage.getItem("jasketch_username") or "Anonymous";
            rj_color = msg.cursorColor or "#999999";
            rj_parts = Object.assign({}, participantsRef.current);
            rj_parts[rj_sid] = {"username": rj_name, "color": rj_color};
            # Add all existing room members sent by the server
            if msg.members {
                rj_member_sids = Object.keys(msg.members);
                for rj_msid in rj_member_sids {
                    rj_parts[rj_msid] = {
                        "username": msg.members[rj_msid].username or "Anonymous",
                        "color": msg.members[rj_msid].color or "#999999"
                    };
                }
            }
            participantsRef.current = rj_parts;
            participants = Object.assign({}, rj_parts);
            # Store host session ID from server
            if msg.hostSessionId {
                hostSessionIdRef.current = msg.hostSessionId;
                hostSessionId = msg.hostSessionId;
            }
            return;
        }

        if msg_type == "room_sync" {
            # Late joiner: receive current scene from room host
            # TODO: Decrypt scene and apply it
            return;
        }

        if msg_type == "room_update" {
            upd_payload = msg.payload or "";
            if upd_payload {
                upd_hook = elementsHookRef.current;
                upd_elements = JSON.parse(upd_payload);
                isApplyingRemoteRef.current = True;
                upd_hook.setElementsReplaceAll(upd_elements);
            }
            return;
        }

        if msg_type == "cursor_update" {
            # Another member's cursor position
            cu_sid = msg.sessionId or "";
            # Ignore own cursor echoes (relay broadcasts to all during update_username)
            if cu_sid == getSessionId() { return; }
            cu_updated = Object.assign({}, cursorStatesRef.current);
            cu_updated[cu_sid] = {
                "username": msg.username or "Anonymous",
                "color": msg.cursorColor or "#999999",
                "x": msg.x or 0.0,
                "y": msg.y or 0.0
            };
            cursorStatesRef.current = cu_updated;
            cursorStates = Object.assign({}, cu_updated);
            # Always upsert participant info (handles users not yet seen via room_joined)
            if cu_sid {
                cu_parts = Object.assign({}, participantsRef.current);
                cu_existing = cu_parts[cu_sid] or {};
                cu_parts[cu_sid] = Object.assign({}, cu_existing, {
                    "username": msg.username or "Anonymous",
                    "color": msg.cursorColor or "#999999"
                });
                participantsRef.current = cu_parts;
                participants = Object.assign({}, cu_parts);
            }
            return;
        }

        if msg_type == "room_member_joined" {
            console.log("[JaSketch] Member joined: " + msg.username);
            # Add new member to participants
            rmj_sid = msg.sessionId or "";
            if rmj_sid {
                rmj_parts = Object.assign({}, participantsRef.current);
                rmj_parts[rmj_sid] = {"username": msg.username or "Anonymous", "color": msg.cursorColor or "#999999"};
                participantsRef.current = rmj_parts;
                participants = Object.assign({}, rmj_parts);
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
            left_sid = msg.sessionId or "";
            if left_sid {
                cl_updated = Object.assign({}, cursorStatesRef.current);
                cl_filtered = Object.fromEntries(Object.entries(cl_updated).filter(lambda kv: any -> bool { return kv[0] != left_sid; }));
                cursorStatesRef.current = cl_filtered;
                cursorStates = Object.assign({}, cl_filtered);
                # Remove from participants
                rml_parts = Object.assign({}, participantsRef.current);
                rml_filtered = Object.fromEntries(Object.entries(rml_parts).filter(lambda kv: any -> bool { return kv[0] != left_sid; }));
                participantsRef.current = rml_filtered;
                participants = Object.assign({}, rml_filtered);
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

        requestId = msg.requestId;
        action = msg.action;
        data = msg.data or {};
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
                addedIds.push(it.id or "");
            }
            sendResponse(ws, requestId, True, {"ids": addedIds, "count": items.length, "action": "created"});
        } elif action == "getElements" {
            # Use elementsRef for synchronous read (avoids stale React state snapshot)
            elems = (hook.elementsRef and hook.elementsRef.current) or hook.elements;
            result = [];
            for el in elems {
                if el and (not data.type or el.type == data.type) {
                    result.push({"id": el.id, "element": el});
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
                updated = Object.assign({}, foundEl, changes);
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

    def sendRoomBroadcast(bcast_elements: list) -> None {
        bcast_room_state = roomStateRef.current;
        if not (bcast_room_state and bcast_room_state.room_id) {
            return;
        }
        bcast_ws = wsRef.current;
        if not (bcast_ws and connectedRef.current) {
            return;
        }
        # Filter out draft elements (id="__draft__") received from remote previews
        bcast_filtered = [];
        bcast_fi = 0;
        while bcast_fi < bcast_elements.length {
            if bcast_elements[bcast_fi] and bcast_elements[bcast_fi].id != "__draft__" {
                bcast_filtered.push(bcast_elements[bcast_fi]);
            }
            bcast_fi = bcast_fi + 1;
        }
        bcast_msg = {
            "type": "room_broadcast",
            "roomId": bcast_room_state.room_id,
            "sessionId": getSessionId(),
            "payload": JSON.stringify(bcast_filtered)
        };
        bcast_ws.send(JSON.stringify(bcast_msg));
    }
    sendRoomBroadcastRef.current = sendRoomBroadcast;

    def sendRoomPreview(prev_elements: list) -> None {
        # Like sendRoomBroadcast but includes draft elements (for live drawing preview)
        prev_room_state = roomStateRef.current;
        if not (prev_room_state and prev_room_state.room_id) {
            return;
        }
        prev_ws = wsRef.current;
        if not (prev_ws and connectedRef.current) {
            return;
        }
        prev_msg = {
            "type": "room_broadcast",
            "roomId": prev_room_state.room_id,
            "sessionId": getSessionId(),
            "payload": JSON.stringify(prev_elements)
        };
        prev_ws.send(JSON.stringify(prev_msg));
    }
    sendRoomPreviewRef.current = sendRoomPreview;

    def sendCursorBroadcast(cur_x: float, cur_y: float, cur_username: str) -> None {
        cur_room_state = roomStateRef.current;
        if not (cur_room_state and cur_room_state.room_id) {
            return;
        }
        cur_ws = wsRef.current;
        if not (cur_ws and connectedRef.current) {
            return;
        }
        cur_msg = {
            "type": "cursor_move",
            "roomId": cur_room_state.room_id,
            "sessionId": getSessionId(),
            "x": cur_x,
            "y": cur_y,
            "username": cur_username
        };
        cur_ws.send(JSON.stringify(cur_msg));
    }
    sendCursorBroadcastRef.current = sendCursorBroadcast;

    def joinRoom(jr_room_id: str, jr_username: str) -> None {
        jr_ws = wsRef.current;
        if not (jr_ws and connectedRef.current) {
            return;
        }
        jr_msg = {
            "type": "join_room",
            "roomId": jr_room_id,
            "sessionId": getSessionId(),
            "username": jr_username
        };
        jr_ws.send(JSON.stringify(jr_msg));
    }
    joinRoomRef.current = joinRoom;

    def sendEndSession(es_room_id: str) -> None {
        es_ws = wsRef.current;
        if not (es_ws and connectedRef.current) { return; }
        es_ws.send(JSON.stringify({
            "type": "end_session",
            "roomId": es_room_id,
            "sessionId": getSessionId()
        }));
    }
    sendEndSessionRef.current = sendEndSession;

    def sendUpdateUsername(uu_room_id: str, uu_username: str) -> None {
        uu_ws = wsRef.current;
        if not (uu_ws and connectedRef.current) { return; }
        uu_ws.send(JSON.stringify({
            "type": "update_username",
            "roomId": uu_room_id,
            "sessionId": getSessionId(),
            "username": uu_username
        }));
        # Optimistic self-update
        uu_sid = getSessionId();
        if participantsRef.current[uu_sid] {
            uu_parts = Object.assign({}, participantsRef.current);
            uu_parts[uu_sid] = Object.assign({}, uu_parts[uu_sid], {"username": uu_username});
            participantsRef.current = uu_parts;
            participants = Object.assign({}, uu_parts);
        }
    }
    sendUpdateUsernameRef.current = sendUpdateUsername;

    def connect() -> None {
        url = getRelayUrl();
        ws = Reflect.construct(WebSocket, [url]);

        ws.onopen = lambda -> None {
            connectedRef.current = True;
            reg_msg: any = {
                "role": "canvas",
                "sessionId": getSessionId()
            };

            ws.send(JSON.stringify(reg_msg));
            console.log("[JaSketch MCP] Connected to relay at " + url);

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
                setTimeout(lambda -> None {
                    if joinRoomRef.current {
                        joinRoomRef.current(lr_rid, lr_name);
                    }
                }, 100);
            }
        };

        ws.onmessage = lambda event: any -> None {
            handleMessage(ws, event);
        };

        ws.onclose = lambda -> None {
            connectedRef.current = False;
            wsRef.current = None;
            # Reconnect after 3 seconds
            reconnectTimerRef.current = setTimeout(lambda -> None {
                connect();
            }, 3000);
        };

        ws.onerror = lambda -> None {
            # Suppress errors, onclose will handle reconnect
            x = 0;
        };

        wsRef.current = ws;
    }

    can with entry {
        connect();

        return lambda -> None {
            if reconnectTimerRef.current {
                clearTimeout(reconnectTimerRef.current);
            }
            if wsRef.current {
                wsRef.current.close();
            }
        };
    }

    can with [roomState.room_id] entry {
        # When room_id becomes set after initial connect (host starts session), send join_room
        if roomState and roomState.room_id and wsRef.current and connectedRef.current {
            jr_stored_name = localStorage.getItem("jasketch_username") or "Anonymous";
            joinRoomRef.current(roomState.room_id, jr_stored_name);
        }
        return lambda -> None { };
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
