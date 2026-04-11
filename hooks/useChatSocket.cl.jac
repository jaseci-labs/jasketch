import from react { useRef }

def:pub useChatSocket() -> dict {
    has messages: list = [];
    has isLoading: bool = False;
    has isConnected: bool = False;

    wsRef = useRef(None);
    connectedRef = useRef(False);
    reconnectTimerRef = useRef(None);
    messageIdRef = useRef(0);
    messagesRef = useRef([]);
    loadingRef = useRef(False);
    currentAssistantRef = useRef("");

    messagesRef.current = messages;
    loadingRef.current = isLoading;

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

        if data.type == "token" {
            currentAssistantRef.current = currentAssistantRef.current + data.content;
            if messagesRef.current.length > 0 and messagesRef.current[messagesRef.current.length - 1].role == "assistant" {
                messagesRef.current = messagesRef.current.slice(0, messagesRef.current.length - 1).concat([{
                    "id": messagesRef.current[messagesRef.current.length - 1].id,
                    "role": "assistant",
                    "content": currentAssistantRef.current
                }]);
            } else {
                messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "assistant", "content": currentAssistantRef.current}]);
            }
            messages = messagesRef.current;
        } elif data.type == "tool_call" {
            messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "tool", "content": "Using " + data.name + "...", "status": "running"}]);
            messages = messagesRef.current;
        } elif data.type == "tool_result" {
            if messagesRef.current.length > 0 and messagesRef.current[messagesRef.current.length - 1].role == "tool" and messagesRef.current[messagesRef.current.length - 1].status == "running" {
                messagesRef.current = messagesRef.current.slice(0, messagesRef.current.length - 1).concat([{"id": messagesRef.current[messagesRef.current.length - 1].id, "role": "tool", "content": data.name + " done", "status": "done"}]);
            }
            messages = messagesRef.current;
            currentAssistantRef.current = "";
        } elif data.type == "done" {
            loadingRef.current = False;
            isLoading = False;
            currentAssistantRef.current = "";
        } elif data.type == "error" {
            messagesRef.current = messagesRef.current.concat([{"id": nextId(), "role": "error", "content": data.message or "Unknown error"}]);
            messages = messagesRef.current;
            loadingRef.current = False;
            isLoading = False;
            currentAssistantRef.current = "";
        }
    }

    def connect() -> None {
        url = getChatUrl();
        ws = Reflect.construct(WebSocket, [url]);

        ws.onopen = lambda -> None {
            connectedRef.current = True;
            isConnected = True;
        };

        ws.onmessage = lambda event: any -> None {
            handleWsMessage(event);
        };

        ws.onclose = lambda -> None {
            connectedRef.current = False;
            isConnected = False;
            wsRef.current = None;
            reconnectTimerRef.current = setTimeout(lambda -> None {
                connect();
            }, 3000);
        };

        ws.onerror = lambda -> None {
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

    return {
        "messages": messages,
        "isLoading": isLoading,
        "isConnected": isConnected,
        "sendMessage": sendMessage,
        "clearMessages": clearMessages
    };
}
