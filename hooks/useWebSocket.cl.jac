import from react { useEffect, useRef }

def:pub useWebSocket(elementsHook: dict) -> dict {
    wsRef = useRef(None);
    connectedRef = useRef(False);
    elementsHookRef = useRef(elementsHook);
    reconnectTimerRef = useRef(None);

    # Keep ref current to avoid stale closures
    elementsHookRef.current = elementsHook;

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
            newIndex = hook.elements.length;
            sendResponse(ws, requestId, True, {"index": newIndex, "action": "created"});
        } elif action == "addMultipleElements" {
            items = data.elements or [];
            hook.addMultipleElements(items);
            startIndex = hook.elements.length;
            sendResponse(ws, requestId, True, {"count": items.length, "startIndex": startIndex, "action": "created"});
        } elif action == "getElements" {
            elems = hook.elements;
            result = [];
            i = 0;
            if data.index != undefined and data.index != None {
                idx = data.index;
                if idx >= 0 and idx < elems.length {
                    result = [{"index": idx, "element": elems[idx]}];
                }
            } elif data.type {
                i = 0;
                while i < elems.length {
                    if elems[i] and elems[i].type == data.type {
                        result.push({"index": i, "element": elems[i]});
                    }
                    i = i + 1;
                }
            } else {
                i = 0;
                while i < elems.length {
                    result.push({"index": i, "element": elems[i]});
                    i = i + 1;
                }
            }
            sendResponse(ws, requestId, True, {"elements": result, "total": elems.length});
        } elif action == "updateElement" {
            idx = data.index;
            changes = data.changes or {};
            elems = hook.elements;
            if idx >= 0 and idx < elems.length {
                current = elems[idx];
                updated = Object.assign({}, current, changes);
                hook.updateElement(idx, updated);
                sendResponse(ws, requestId, True, {"index": idx, "action": "updated"});
            } else {
                sendError(ws, requestId, "Index out of range");
            }
        } elif action == "removeElement" {
            hook.removeElement(data.index);
            sendResponse(ws, requestId, True, {"index": data.index, "action": "deleted"});
        } elif action == "removeMultipleElements" {
            hook.removeMultipleElements(data.indices or []);
            sendResponse(ws, requestId, True, {"indices": data.indices, "action": "deleted"});
        } elif action == "clearElements" {
            hook.clearElements();
            sendResponse(ws, requestId, True, {"action": "cleared"});
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

    useEffect(lambda -> any {
        connect();

        return lambda -> None {
            if reconnectTimerRef.current {
                clearTimeout(reconnectTimerRef.current);
            }
            if wsRef.current {
                wsRef.current.close();
            }
        };
    }, []);

    return {"connected": connectedRef.current};
}
