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
            cur = messagesRef.current.slice();
            if cur.length > 0 and cur[cur.length - 1].role == "assistant" {
                cur[cur.length - 1] = {
                    "id": cur[cur.length - 1].id,
                    "role": "assistant",
                    "content": currentAssistantRef.current
                };
            } else {
                cur.push({"id": nextId(), "role": "assistant", "content": currentAssistantRef.current});
            }
            messagesRef.current = cur;
            messages = cur;
        } elif data.type == "tool_call" {
            cur = messagesRef.current.slice();
            cur.push({"id": nextId(), "role": "tool", "content": "Using " + data.name + "...", "status": "running"});
            messagesRef.current = cur;
            messages = cur;
        } elif data.type == "tool_result" {
            cur = messagesRef.current.slice();
            i = cur.length - 1;
            while i >= 0 {
                if cur[i].role == "tool" and cur[i].status == "running" {
                    cur[i] = {"id": cur[i].id, "role": "tool", "content": data.name + " done", "status": "done"};
                    break;
                }
                i = i - 1;
            }
            messagesRef.current = cur;
            messages = cur;
            currentAssistantRef.current = "";
        } elif data.type == "done" {
            loadingRef.current = False;
            isLoading = False;
            currentAssistantRef.current = "";
        } elif data.type == "error" {
            cur = messagesRef.current.slice();
            cur.push({"id": nextId(), "role": "error", "content": data.message or "Unknown error"});
            messagesRef.current = cur;
            messages = cur;
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

    def sendMessage(apiKey: str, model: str, message: str) -> None {
        if not wsRef.current or not connectedRef.current {
            return;
        }

        cur = messagesRef.current.slice();
        cur.push({"id": nextId(), "role": "user", "content": message});
        messagesRef.current = cur;
        messages = cur;
        loadingRef.current = True;
        isLoading = True;
        currentAssistantRef.current = "";

        history = [];
        for m in messagesRef.current {
            if m.role == "user" or m.role == "assistant" {
                history.push({"role": m.role, "content": m.content});
            }
        }

        wsRef.current.send(JSON.stringify({
            "type": "chat",
            "apiKey": apiKey,
            "model": model,
            "message": message,
            "history": history
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
