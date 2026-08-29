import from react { useRef, useEffect }

def:pub useChatSocket() -> dict {
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
    currentAssistantRef = useRef("");
    pendingConfirmRef = useRef({});

    messagesRef.current = messages;
    loadingRef.current = isLoading;
    pendingConfirmRef.current = pendingConfirm;

    def nextId() -> int {
        messageIdRef.current = messageIdRef.current + 1;
        return messageIdRef.current;
    }

    def getChatUrl() -> str {
        host = window.location.hostname;
        protocol = window.location.protocol;
        if host == "localhost" or host == "127.0.0.1" {
            return "ws://" + host + ":9602";
        }
        wsProtocol = "ws:";
        if protocol == "https:" {
            wsProtocol = "wss:";
        }
        return wsProtocol + "//" + host + "/chat-ws";
    }

    def handleWsMessage(event: any) -> None {
        data = JSON.parse(event.data);

        if data.type == "confirm" {
            pendingConfirm = {"confirmId": data.confirmId or "", "message": data.message or ""};
            pendingConfirmRef.current = pendingConfirm;
        } elif data.type == "message" {
            msgContent = data["content"] or "";
            messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "assistant", "content": msgContent}]);
            messages = messagesRef.current;
        } elif data.type == "done" {
            loadingRef.current = False;
            isLoading = False;
            currentAssistantRef.current = "";
            currentPhase = "";
        } elif data.type == "error" {
            messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "error", "content": data.message or "Unknown error"}]);
            messages = messagesRef.current;
            loadingRef.current = False;
            isLoading = False;
            currentAssistantRef.current = "";
            currentPhase = "";
        } elif data.type == "agent_start" {
            currentPhase = data.agent or "";
        } elif data.type == "agent_done" {
            currentPhase = "";
        }
    }

    def connect() -> None {
        url = getChatUrl();
        ws = Reflect.construct(WebSocket, [url]);

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
            reconnectTimerRef.current = setTimeout(lambda {
                connect();
            }, 3000);
        };

        ws.onerror = lambda {
            x = 0;
        };

        wsRef.current = ws;
    }

    def getSessionId() -> Any {
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

        history = [];
        for m in messagesRef.current {
            if m.role == "user" or m.role == "assistant" {
                history.push({"role": m.role, "content": m.content});
            }
        }

        messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "user", "content": message}]);
        messages = messagesRef.current;
        loadingRef.current = True;
        isLoading = True;
        currentAssistantRef.current = "";

        wsRef.current.send(JSON.stringify({
            "type": "chat",
            "apiKey": apiKey,
            "model": model,
            "message": message,
            "history": history,
            "sessionId": getSessionId()
        }));
    }

    def clearMessages() -> None {
        messagesRef.current = [];
        messages = [];
        currentAssistantRef.current = "";
        messageIdRef.current = 0;
    }

    def respondConfirm(result: str) -> None {
        cid = pendingConfirmRef.current.confirmId or "";
        if wsRef.current and connectedRef.current and cid {
            wsRef.current.send(JSON.stringify({
                "type": "confirm_response",
                "confirmId": cid,
                "result": result
            }));
        }
        pendingConfirm = {};
        pendingConfirmRef.current = {};
    }

    # Acquire-and-release in ONE effect: `can with entry`/`can with exit` compile
    # to separate useEffect closures, so a handle created in entry is invisible to
    # exit and the removeEventListener would silently no-op.
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
