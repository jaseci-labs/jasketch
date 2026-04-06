import from react { useRef }

def:pub useWebSocket(elementsHook: dict, viewportHook: dict, canvasRef: any, canvasHook: dict) -> dict {
    wsRef = useRef(None);
    connectedRef = useRef(False);
    elementsHookRef = useRef(elementsHook);
    viewportHookRef = useRef(viewportHook);
    canvasRefRef = useRef(canvasRef);
    canvasHookRef = useRef(canvasHook);
    reconnectTimerRef = useRef(None);

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
        msg = {"requestId": requestId, "success": success, "data": data};
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
            ami = 0;
            while ami < items.length {
                addedIds.push(items[ami].id or "");
                ami = ami + 1;
            }
            sendResponse(ws, requestId, True, {"ids": addedIds, "count": items.length, "action": "created"});
        } elif action == "getElements" {
            elems = hook.elements;
            result = [];
            i = 0;
            if data.type {
                while i < elems.length {
                    if elems[i] and elems[i].type == data.type {
                        result.push({"id": elems[i].id, "element": elems[i]});
                    }
                    i = i + 1;
                }
            } else {
                while i < elems.length {
                    result.push({"id": elems[i].id, "element": elems[i]});
                    i = i + 1;
                }
            }
            sendResponse(ws, requestId, True, {"elements": result, "total": elems.length});
        } elif action == "updateElement" {
            targetId = data.id;
            changes = data.changes or {};
            elems = hook.elements;
            foundEl = None;
            uei = 0;
            while uei < elems.length {
                if elems[uei] and elems[uei].id == targetId {
                    foundEl = elems[uei];
                }
                uei = uei + 1;
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
            canvas = canvasRefRef.current;
            if canvas and canvas.current {
                # Use JPEG at 0.6 quality for smaller payload and faster transfer
                dataUrl = canvas.current.toDataURL("image/jpeg", 0.6);
                sendResponse(ws, requestId, True, {"snapshot": dataUrl});
            } else {
                sendError(ws, requestId, "Canvas not available");
            }
        } elif action == "getBoundingBox" {
            elems = hook.elements;
            if elems.length == 0 {
                sendResponse(ws, requestId, True, {"boundingBox": None, "elementCount": 0});
            } else {
                bbMinX = 999999;
                bbMinY = 999999;
                bbMaxX = -999999;
                bbMaxY = -999999;
                bbi = 0;
                while bbi < elems.length {
                    bbEl = elems[bbi];
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
                        bbpi = 0;
                        while bbpi < bbEl.points.length {
                            if bbEl.points[bbpi].x < bbMinX { bbMinX = bbEl.points[bbpi].x; }
                            if bbEl.points[bbpi].y < bbMinY { bbMinY = bbEl.points[bbpi].y; }
                            if bbEl.points[bbpi].x > bbMaxX { bbMaxX = bbEl.points[bbpi].x; }
                            if bbEl.points[bbpi].y > bbMaxY { bbMaxY = bbEl.points[bbpi].y; }
                            bbpi = bbpi + 1;
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
                    bbi = bbi + 1;
                }
                sendResponse(ws, requestId, True, {
                    "boundingBox": {
                        "x": bbMinX,
                        "y": bbMinY,
                        "width": bbMaxX - bbMinX,
                        "height": bbMaxY - bbMinY
                    },
                    "elementCount": elems.length
                });
            }
        } elif action == "getElementById" {
            elems = hook.elements;
            targetId = data.id;
            foundEl = None;
            gei = 0;
            while gei < elems.length {
                if elems[gei] and elems[gei].id == targetId {
                    foundEl = elems[gei];
                }
                gei = gei + 1;
            }
            if foundEl {
                sendResponse(ws, requestId, True, {"id": targetId, "element": foundEl});
            } else {
                sendError(ws, requestId, "Element not found: " + targetId);
            }
        } else {
            sendError(ws, requestId, "Unknown action: " + action);
        }
    }

    def connect() -> None {
        url = getRelayUrl();
        ws = Reflect.construct(WebSocket, [url]);

        ws.onopen = lambda -> None {
            connectedRef.current = True;
            # Register as canvas with the relay
            ws.send(JSON.stringify({"role": "canvas"}));
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
