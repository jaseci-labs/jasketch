import from react { useRef }

def:pub useWebSocket(elementsHook: dict, viewportHook: dict, canvasRef: any, canvasHook: dict) -> dict {
    wsRef = useRef(None);
    connectedRef = useRef(False);
    elementsHookRef = useRef(elementsHook);
    viewportHookRef = useRef(viewportHook);
    canvasRefRef = useRef(canvasRef);
    canvasHookRef = useRef(canvasHook);
    reconnectTimerRef = useRef(None);
    pendingConfirmsRef = useRef({});

    # Keep refs current to avoid stale closures
    elementsHookRef.current = elementsHook;
    viewportHookRef.current = viewportHook;
    canvasRefRef.current = canvasRef;
    canvasHookRef.current = canvasHook;

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
            hook.clearElements();
            hook.addMultipleElements(newElements);

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
        } elif action == "showConfirm" {
            confirmId = data.confirmId;
            message = data.message or "Replace canvas content?";
            confirmResult = window.confirm(message);
            if confirmResult {
                pendingConfirmsRef.current[confirmId] = "ok";
            } else {
                pendingConfirmsRef.current[confirmId] = "cancel";
            }
            sendResponse(ws, requestId, True, {"received": True});
        } elif action == "getConfirmResult" {
            gcConfirmId = data.confirmId;
            gcResult = pendingConfirmsRef.current[gcConfirmId];
            if gcResult == undefined {
                gcResult = "pending";
            } else {
                pendingConfirmsRef.current[gcConfirmId] = None;
            }
            sendResponse(ws, requestId, True, {"result": gcResult});
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

    def connect() -> None {
        url = getRelayUrl();
        ws = Reflect.construct(WebSocket, [url]);

        ws.onopen = lambda -> None {
            connectedRef.current = True;
            # Register as canvas with a stable per-tab sessionId
            ws.send(JSON.stringify({"role": "canvas", "sessionId": getSessionId()}));
            console.log("[JaSketch MCP] Connected to relay at " + url);
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

    return {"connected": connectedRef.current};
}
