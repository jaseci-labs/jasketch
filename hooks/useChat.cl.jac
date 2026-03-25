import from react { useRef }

def:pub useChat() -> dict {
    has messages: list = [];
    has isLoading: bool = False;
    has isOpen: bool = False;
    has showSettings: bool = False;
    has settings: dict = {
        "apiKey": "",
        "model": "gpt-4o",
        "provider": "openai"
    };

    abortControllerRef = useRef(None);
    settingsLoadedRef = useRef(False);

    SETTINGS_KEY = "jasketch_chat_settings";

    def getChatServerUrl() -> str {
        host = window.location.hostname;
        protocol = window.location.protocol;

        if host == "localhost" or host == "127.0.0.1" {
            return "http://" + host + ":8001";
        }
        return protocol + "//" + host + "/chat";
    }

    # Load settings from localStorage on mount
    can with entry {
        stored = localStorage.getItem(SETTINGS_KEY);
        if stored {
            parsed = JSON.parse(stored);
            if parsed {
                settings = parsed;
            }
        }
        settingsLoadedRef.current = True;
    }

    def saveSettings(newSettings: dict) -> None {
        settings = newSettings;
        localStorage.setItem(SETTINGS_KEY, JSON.stringify(newSettings));
    }

    def toggleOpen() -> None {
        isOpen = not isOpen;
    }

    def toggleSettings() -> None {
        showSettings = not showSettings;
    }

    def clearMessages() -> None {
        messages = [];
    }

    def stopGeneration() -> None {
        if abortControllerRef.current {
            abortControllerRef.current.abort();
            abortControllerRef.current = None;
        }
        isLoading = False;
    }

    def parseSSEStream(reader: any, decoder: any) -> None {
        buffer = "";
        assistantContent = "";
        toolCalls = [];

        def processChunk() -> None {
            reader.read().then(lambda result: any -> None {
                if result.done {
                    isLoading = False;
                    return;
                }

                buffer = buffer + decoder.decode(result.value, {"stream": True});
                lines = buffer.split("\n");
                # Keep the last potentially incomplete line in buffer
                buffer = lines.pop();

                idx = 0;
                while idx < lines.length {
                    line = lines[idx];
                    idx = idx + 1;

                    if line.startsWith("event: ") {
                        eventType = line.slice(7).trim();
                        # Next line should be data:
                        if idx < lines.length and lines[idx].startsWith("data: ") {
                            dataStr = lines[idx].slice(6);
                            idx = idx + 1;
                            handleSSEEvent(eventType, dataStr);
                        }
                    } elif line.startsWith("data: ") {
                        # Event without explicit event type
                        dataStr = line.slice(6);
                        handleSSEEvent("message", dataStr);
                    }
                }

                processChunk();
            }).catch(lambda err: any -> None {
                if err.name != "AbortError" {
                    console.error("[JaSketch Chat] Stream error:", err);
                    messages = messages.concat([{
                        "role": "error",
                        "content": "Connection error: " + err.message
                    }]);
                }
                isLoading = False;
            });
        }

        def handleSSEEvent(eventType: str, dataStr: str) -> None {
            data = {};
            if dataStr and dataStr != "{}" {
                data = JSON.parse(dataStr);
            }

            if eventType == "content_delta" {
                assistantContent = assistantContent + (data.content or "");
                # Update or add assistant message
                lastMsg = messages.length > 0 and messages[messages.length - 1] or None;
                if lastMsg and lastMsg.role == "assistant" {
                    updated = messages.slice(0, messages.length - 1);
                    updated.push({
                        "role": "assistant",
                        "content": assistantContent,
                        "toolCalls": toolCalls.slice()
                    });
                    messages = updated;
                } else {
                    messages = messages.concat([{
                        "role": "assistant",
                        "content": assistantContent,
                        "toolCalls": toolCalls.slice()
                    }]);
                }
            } elif eventType == "tool_call" {
                toolCalls.push({
                    "name": data.name,
                    "arguments": data.arguments,
                    "result": None,
                    "status": "running"
                });
                # Update assistant message with tool call info
                lastMsg = messages.length > 0 and messages[messages.length - 1] or None;
                if lastMsg and lastMsg.role == "assistant" {
                    updated = messages.slice(0, messages.length - 1);
                    updated.push({
                        "role": "assistant",
                        "content": assistantContent,
                        "toolCalls": toolCalls.slice()
                    });
                    messages = updated;
                }
            } elif eventType == "tool_result" {
                # Update the last tool call with its result
                if toolCalls.length > 0 {
                    lastTc = toolCalls[toolCalls.length - 1];
                    lastTc.result = data.result;
                    lastTc.status = "done";
                    # Refresh assistant message
                    lastMsg = messages.length > 0 and messages[messages.length - 1] or None;
                    if lastMsg and lastMsg.role == "assistant" {
                        updated = messages.slice(0, messages.length - 1);
                        updated.push({
                            "role": "assistant",
                            "content": assistantContent,
                            "toolCalls": toolCalls.slice()
                        });
                        messages = updated;
                    }
                }
            } elif eventType == "done" {
                isLoading = False;
            } elif eventType == "error" {
                messages = messages.concat([{
                    "role": "error",
                    "content": data.message or "Unknown error"
                }]);
                isLoading = False;
            }
        }

        processChunk();
    }

    def sendMessage(content: str) -> None {
        if not content.trim() or not settings.apiKey {
            if not settings.apiKey {
                messages = messages.concat([{
                    "role": "error",
                    "content": "Please set your API key in settings first."
                }]);
                showSettings = True;
            }
            return;
        }

        # Add user message
        userMsg = {"role": "user", "content": content};
        newMessages = messages.concat([userMsg]);
        messages = newMessages;
        isLoading = True;

        # Build messages for API (only role + content, skip toolCalls/error)
        apiMessages = [];
        mi = 0;
        while mi < newMessages.length {
            msg = newMessages[mi];
            if msg.role == "user" or msg.role == "assistant" {
                apiMessages.push({"role": msg.role, "content": msg.content or ""});
            }
            mi = mi + 1;
        }

        controller = Reflect.construct(AbortController, []);
        abortControllerRef.current = controller;

        url = getChatServerUrl() + "/chat/completions";
        body = JSON.stringify({
            "messages": apiMessages,
            "api_key": settings.apiKey,
            "model": settings.model
        });

        fetch(url, {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": body,
            "signal": controller.signal
        }).then(lambda response: any -> None {
            if not response.ok {
                response.text().then(lambda errText: any -> None {
                    messages = messages.concat([{
                        "role": "error",
                        "content": "Server error: " + errText
                    }]);
                    isLoading = False;
                });
                return;
            }
            reader = response.body.getReader();
            decoder = Reflect.construct(TextDecoder, []);
            parseSSEStream(reader, decoder);
        }).catch(lambda err: any -> None {
            if err.name != "AbortError" {
                messages = messages.concat([{
                    "role": "error",
                    "content": "Failed to connect: " + err.message
                }]);
            }
            isLoading = False;
        });
    }

    return {
        "messages": messages,
        "isLoading": isLoading,
        "isOpen": isOpen,
        "showSettings": showSettings,
        "settings": settings,
        "sendMessage": sendMessage,
        "stopGeneration": stopGeneration,
        "clearMessages": clearMessages,
        "toggleOpen": toggleOpen,
        "toggleSettings": toggleSettings,
        "saveSettings": saveSettings
    };
}
