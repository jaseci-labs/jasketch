"""Chat transport: one WebSocket to the app's own `jasketch_chat` endpoint.

Two things changed when the agent stopped reaching back into the browser (see
agent/chat.jac):

  - The socket is `/ws/function/jasketch_chat` on this origin, not a second
    server on port 9602. Nothing to expose, nothing to proxy.
  - The canvas travels WITH the message and comes back in an `elements` frame,
    so the caller supplies a snapshot getter and an apply callback.
"""

import from react { useRef, useEffect }

sv import from ...agent.chat { jasketch_chat_confirm }


def:pub useChatSocket(
    getElements: Callable[[], list],
    onElements: Callable[[list], None]
) -> dict {
    has messages: list = [];
    has isLoading: bool = False;
    has isConnected: bool = False;
    has pendingConfirm: dict = {};
    has currentPhase: str = "";

    wsRef = useRef(None);
    connectedRef = useRef(False);
    reconnectTimerRef = useRef(None);
    messageIdRef = useRef(0);
    messagesRef = useRef([]);
    loadingRef = useRef(False);
    pendingConfirmRef = useRef({});
    getElementsRef = useRef(getElements);
    onElementsRef = useRef(onElements);

    messagesRef.current = messages;
    loadingRef.current = isLoading;
    pendingConfirmRef.current = pendingConfirm;
    getElementsRef.current = getElements;
    onElementsRef.current = onElements;

    def nextId() -> int {
        messageIdRef.current = messageIdRef.current + 1;
        return messageIdRef.current;
    }

    def getChatUrl() -> str {
        wsProtocol = "wss:" if window.location.protocol == "https:" else "ws:";
        return wsProtocol + "//" + window.location.host + "/ws/function/jasketch_chat";
    }

    def appendMessage(role: str, content: str) -> None {
        history: list = messagesRef.current or [];
        messagesRef.current = history + [{"id": nextId(), "role": role, "content": content}];
        messages = messagesRef.current;
    }

    def finishTurn() -> None {
        loadingRef.current = False;
        isLoading = False;
        currentPhase = "";
    }

    """Handle one agent frame. The endpoint wraps each yield as {type:"chunk", data}."""
    def handleFrame(frame: any) -> None {
        kind: str = frame.type or "";

        if kind == "confirm" {
            pendingConfirm = {"confirmId": frame.confirmId or "", "message": frame.message or ""};
            pendingConfirmRef.current = pendingConfirm;
        } elif kind == "message" {
            appendMessage("assistant", frame.content or "");
        } elif kind == "elements" {
            applyFn = onElementsRef.current;
            if applyFn {
                applyFn.call(None, frame.elements or []);
            }
        } elif kind == "agent_start" {
            currentPhase = frame.agent or "";
        } elif kind == "agent_done" {
            currentPhase = "";
        } elif kind == "error" {
            appendMessage("error", frame.message or "Unknown error");
            finishTurn();
        } elif kind == "done" {
            finishTurn();
        }
    }

    def handleWsMessage(event: any) -> None {
        envelope: any = JSON.parse(event.data);
        # Control frames (ping/pong/refreshed) carry no agent payload.
        if envelope.type == "ping" or envelope.type == "pong" or envelope.type == "refreshed" {
            return;
        }
        if envelope.ok == False {
            err: any = envelope.error or {};
            appendMessage("error", err.message or "The chat endpoint rejected the request.");
            finishTurn();
            return;
        }
        # A streaming target sends {ok, type:"chunk", data} per yield, then a
        # bare {ok, type:"done"} once the generator is exhausted.
        if envelope.type == "chunk" {
            handleFrame(envelope.data or {});
        } elif envelope.type == "done" {
            finishTurn();
        }
    }

    def connect() -> None {
        ws = new(WebSocket, getChatUrl());

        ws.onopen = lambda {
            connectedRef.current = True;
            isConnected = True;
        };
        ws.onmessage = lambda (event: any) {
            handleWsMessage(event);
        };
        ws.onclose = lambda {
            connectedRef.current = False;
            isConnected = False;
            wsRef.current = None;
            reconnectTimerRef.current = setTimeout(lambda { connect(); }, 3000);
        };
        ws.onerror = lambda { _ = 0; };

        wsRef.current = ws;
    }

    def getSessionId() -> any {
        # Same key as useWebSocket — both hooks read the same stable per-tab ID
        key = "jasketch_session_id";
        sid = sessionStorage.getItem(key);
        if not sid {
            sid = crypto.randomUUID();
            sessionStorage.setItem(key, sid);
        }
        return sid;
    }

    def sendMessage(apiKey: str, model: str, message: str) -> None {
        if not wsRef.current or not connectedRef.current {
            return;
        }
        snapshotFn = getElementsRef.current;
        snapshot = snapshotFn.call(None) if snapshotFn else [];

        appendMessage("user", message);
        loadingRef.current = True;
        isLoading = True;

        wsRef.current.send(JSON.stringify({
            "message": message,
            "api_key": apiKey,
            "model": model,
            "session_id": getSessionId(),
            "elements": snapshot or [],
            "viewport": {}
        }));
    }

    def clearMessages() -> None {
        messagesRef.current = [];
        messages = [];
        messageIdRef.current = 0;
    }

    async def respondConfirm(result: str) -> None {
        pending: any = pendingConfirmRef.current or {};
        cid: str = pending.confirmId or "";
        if cid {
            # A plain RPC, not a socket frame: the turn that asked is blocked on
            # a worker thread and this is a separate request that releases it.
            await jasketch_chat_confirm(cid, result);
        }
        pendingConfirm = {};
        pendingConfirmRef.current = {};
    }

    # Acquire-and-release in ONE effect: `can with entry`/`can with exit` compile
    # to separate useEffect closures, so the socket opened on mount is invisible
    # to the cleanup and would never be closed.
    useEffect(lambda () -> any {
        connect();
        return lambda {
            if reconnectTimerRef.current {
                clearTimeout(reconnectTimerRef.current);
            }
            if wsRef.current {
                wsRef.current.close();
            }
        };
    }, []);

    return {
        "messages": messages,
        "isLoading": isLoading,
        "isConnected": isConnected,
        "sendMessage": sendMessage,
        "clearMessages": clearMessages,
        "pendingConfirm": pendingConfirm,
        "respondConfirm": respondConfirm,
        "currentPhase": currentPhase
    };
}
