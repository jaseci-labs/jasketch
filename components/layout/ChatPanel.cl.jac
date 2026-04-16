import from react { useRef }
import from "...hooks.useChatSocket" { useChatSocket }


# --- Icon helpers (keeps JSX readable) ---

def ChatIcon(props: dict) -> JsxElement {
    size = props.size or 16;
    return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={props.strokeWidth or "2"} strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>;
}

def GearIcon() -> JsxElement {
    return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="3" />
        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>;
}

def TrashIcon() -> JsxElement {
    return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="3 6 5 6 21 6" />
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    </svg>;
}

def CloseIcon() -> JsxElement {
    return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <line x1="18" y1="6" x2="6" y2="18" />
        <line x1="6" y1="6" x2="18" y2="18" />
    </svg>;
}

def SendIcon() -> JsxElement {
    return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <line x1="22" y1="2" x2="11" y2="13" />
        <polygon points="22 2 15 22 11 13 2 9 22 2" />
    </svg>;
}

def WarnIcon() -> JsxElement {
    return <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="10" />
        <line x1="12" y1="8" x2="12" y2="12" />
        <line x1="12" y1="16" x2="12.01" y2="16" />
    </svg>;
}


# --- Shared styles ---

def headerBtnClass(active: bool) -> str {
    base = "w-8 h-8 rounded-md flex items-center justify-center transition-all duration-150 ";
    if active {
        return base + "bg-orange-50 text-orange-600";
    }
    return base + "text-gray-400 hover:bg-gray-100 hover:text-gray-600";
}

def inputClass() -> str {
    return "w-full mt-1.5 px-3 py-2 text-xs rounded-lg border border-gray-200 bg-white focus:border-orange-300 focus:ring-1 focus:ring-orange-200 outline-none transition-all";
}


# --- Section components ---

def ChatHeader(props: dict) -> JsxElement {
    return <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
        <div className="flex items-center gap-2">
            <div className={"w-2 h-2 rounded-full " + (props.isConnected and "bg-green-500" or "bg-red-400")}></div>
            <span className="text-sm font-semibold text-gray-700">AI Chat</span>
        </div>
        <div className="flex items-center gap-1">
            <button onClick={props.onSettingsToggle} title="Settings" className={headerBtnClass(props.showSettings)}>
                <GearIcon />
            </button>
            <button onClick={props.onClear} title="Clear chat" className={headerBtnClass(False)}>
                <TrashIcon />
            </button>
            <button onClick={props.onClose} title="Close chat" className={headerBtnClass(False)}>
                <CloseIcon />
            </button>
        </div>
    </div>;
}

def ChatSettings(props: dict) -> JsxElement {
    stopProp = lambda e: any -> None { e.stopPropagation(); };

    return <div className="px-4 py-3 border-b border-gray-100 bg-gray-50/50 animate-fade-in">
        <div className="mb-3">
            <span className="sidebar-label">API Key</span>
            <input
                type="password"
                value={props.apiKey}
                onChange={lambda e: any -> None { props.onApiKeyChange(e.target.value); }}
                onKeyDown={stopProp}
                placeholder="sk-... or anthropic key..."
                className={inputClass()}
            />
        </div>
        <div>
            <span className="sidebar-label">Model</span>
            <select
                value={props.selectedModel}
                onChange={lambda e: any -> None { props.onModelChange(e.target.value); }}
                onKeyDown={stopProp}
                className={inputClass + " cursor-pointer"}
            >
                {[
                    <option key={opt.id} value={opt.id}>{opt.label}</option>
                    for opt in props.modelOptions
                ]}
            </select>
        </div>
    </div>;
}

def ChatEmptyState() -> JsxElement {
    return <div className="flex-1 flex items-center justify-center">
        <div className="text-center text-gray-300 py-12">
            <ChatIcon size={40} strokeWidth="1.5" />
            <p className="text-xs font-medium text-gray-400 mt-3">Ask AI to draw something</p>
            <p className="text-[10px] mt-1.5 text-gray-300">e.g. "Draw a flowchart for user login"</p>
        </div>
    </div>;
}

def ChatMessage(props: dict) -> JsxElement {
    msg = props.msg;

    if msg.role == "user" {
        return <div className="flex justify-end">
            <div className="chat-msg-user max-w-[85%] px-3 py-2 rounded-xl rounded-br-sm bg-orange-500 text-white text-xs leading-relaxed">
                {msg.content}
            </div>
        </div>;
    }
    if msg.role == "assistant" {
        return <div className="flex justify-start">
            <div className="chat-msg-assistant max-w-[85%] px-3 py-2 rounded-xl rounded-bl-sm bg-gray-100 text-gray-700 text-xs leading-relaxed whitespace-pre-wrap">
                {msg.content}
            </div>
        </div>;
    }
    if msg.role == "tool" {
        statusClass = msg.status == "running" and "bg-blue-50 text-blue-500" or "bg-green-50 text-green-600";
        return <div className="flex justify-center">
            <div className={"chat-msg-tool px-2.5 py-1 rounded-full text-[10px] font-medium " + statusClass}>
                {msg.status == "running" and "... " or ""}{msg.content}
            </div>
        </div>;
    }
    if msg.role == "error" {
        return <div className="flex justify-center">
            <div className="chat-msg-error px-2.5 py-1.5 rounded-lg bg-red-50 text-red-500 text-[10px] font-medium max-w-[90%] break-words">
                {msg.content}
            </div>
        </div>;
    }
    if msg.role == "agent" {
        agentStatusClass = msg.status == "running" and "bg-purple-50 text-purple-600" or "bg-purple-100 text-purple-700";
        return <div className="flex justify-center">
            <div className={"chat-msg-agent px-2.5 py-1 rounded-full text-[10px] font-medium " + agentStatusClass}>
                {msg.status == "running" and "⚙ " or "✓ "}{msg.content}
            </div>
        </div>;
    }
    return None;
}

def CanvasConfirmModal(props: dict) -> JsxElement {
    pending = props.pending;
    onApprove = props.onApprove;
    onDeny = props.onDeny;
    if not pending or not pending.confirmId {
        return <></>;
    }
    return <div className="flex-shrink-0 border-t border-amber-200/40 bg-amber-50 px-4 py-3">
        <div className="flex items-start gap-3">
            <div className="flex-1 min-w-0">
                <p className="text-xs font-semibold text-amber-600 mb-1">Canvas Confirmation</p>
                <p className="text-xs text-gray-700 mb-3">{pending.message}</p>
                <div className="flex gap-2">
                    <button onClick={onApprove}
                        className="bg-green-100/60 hover:bg-green-100 text-green-700 border border-green-200 text-xs font-medium px-3 py-1.5 rounded-lg transition-colors cursor-pointer">
                        Approve
                    </button>
                    <button onClick={onDeny}
                        className="bg-red-100/60 hover:bg-red-100 text-red-700 border border-red-200 text-xs font-medium px-3 py-1.5 rounded-lg transition-colors cursor-pointer">
                        Deny
                    </button>
                </div>
            </div>
        </div>
    </div>;
}

def ChatInput(props: dict) -> JsxElement {
    canSend = props.apiKey and props.inputText.trim() and not props.isLoading;
    isDisabled = not props.apiKey or props.isLoading;

    return <div className="px-4 py-3 border-t border-gray-100">
        {not props.apiKey and <p className="text-[10px] text-amber-500 mb-2 flex items-center gap-1">
            <WarnIcon />
            {"Set your API key in settings to start"}
        </p> or None}
        <div className="flex items-end gap-2">
            <textarea
                ref={props.inputRef}
                value={props.inputText}
                onChange={props.onChange}
                onKeyDown={props.onKeyDown}
                placeholder={props.apiKey and "Ask AI to draw..." or "Set API key first..."}
                disabled={isDisabled}
                rows="1"
                className="chat-input flex-1 px-3 py-2 text-xs rounded-xl border border-gray-200 bg-gray-50 resize-none outline-none focus:border-orange-300 focus:ring-1 focus:ring-orange-200 focus:bg-white disabled:opacity-50 disabled:cursor-not-allowed max-h-[100px] transition-all"
            />
            <button
                onClick={props.onSend}
                disabled={not canSend}
                className="w-9 h-9 rounded-xl flex items-center justify-center bg-orange-500 text-white hover:bg-orange-600 disabled:bg-gray-200 disabled:text-gray-400 disabled:cursor-not-allowed transition-all duration-150 flex-shrink-0"
                title="Send message"
            >
                <SendIcon />
            </button>
        </div>
    </div>;
}


# --- Main component ---

def:pub ChatPanel(props: dict) -> JsxElement {
    isOpen = props.isOpen;
    onToggle = props.onToggle;

    has apiKey: str = "";
    has selectedModel: str = "gpt-4o-mini";
    has inputText: str = "";
    has showSettings: bool = False;
    has initialized: bool = False;

    chat = useChatSocket();
    messagesEndRef = useRef(None);
    inputRef = useRef(None);

    modelOptions = [
        {"id": "gpt-4o", "label": "GPT-4o"},
        {"id": "gpt-4o-mini", "label": "GPT-4o Mini"},
        {"id": "gpt-5-mini", "label": "GPT-5 Mini"},
        {"id": "claude-sonnet-4-20250514", "label": "Claude Sonnet"},
        {"id": "claude-haiku-4-20250414", "label": "Claude Haiku"},
        {"id": "gemini/gemini-2.0-flash", "label": "Gemini Flash"},
        {"id": "ollama/llama3", "label": "Ollama Llama3"}
    ];

    # Load saved settings on mount
    can with entry {
        if not initialized {
            savedKey = localStorage.getItem("jasketch_chat_apikey");
            savedModel = localStorage.getItem("jasketch_chat_model");
            if savedKey { apiKey = savedKey; }
            if savedModel { selectedModel = savedModel; }
            initialized = True;
        }
    }

    # Auto-scroll to bottom when messages change
    can with [chat.messages] entry {
        if messagesEndRef.current {
            messagesEndRef.current.scrollIntoView({"behavior": "smooth"});
        }
    }

    # Focus input when panel opens
    can with [isOpen] entry {
        if isOpen and inputRef.current {
            setTimeout(lambda -> None {
                if inputRef.current { inputRef.current.focus(); }
            }, 150);
        }
    }

    def handleApiKeyChange(value: str) -> None {
        apiKey = value;
        localStorage.setItem("jasketch_chat_apikey", value);
    }

    def handleModelChange(value: str) -> None {
        selectedModel = value;
        localStorage.setItem("jasketch_chat_model", value);
    }

    def handleSend() -> None {
        text = inputText.trim();
        if not text or not apiKey or chat.isLoading { return; }
        chat.sendMessage(apiKey, selectedModel, text);
        inputText = "";
    }

    def handleKeyDown(e: any) -> None {
        e.stopPropagation();
        if e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            handleSend();
        }
    }

    # Closed state: floating toggle button
    if not isOpen {
        return <button
            onClick={onToggle}
            className="fixed bottom-6 right-6 z-50 w-12 h-12 rounded-full bg-orange-500 hover:bg-orange-600 text-white shadow-lg hover:shadow-xl transition-all duration-200 flex items-center justify-center"
            title="Open AI Chat"
        >
            <ChatIcon size={22} />
        </button>;
    }

    # Show typing indicator when loading and last message isn't already streaming
    showTyping = chat.isLoading and chat.messages.length > 0 and chat.messages[chat.messages.length - 1].role != "assistant";

    # Open state: full panel
    return <div className="chat-panel fixed right-0 top-[44px] bottom-0 w-[380px] z-40 bg-white/95 backdrop-blur-xl border-l border-gray-200/60 shadow-xl flex flex-col animate-slide-in-right">

        <ChatHeader
            isConnected={chat.isConnected}
            showSettings={showSettings}
            onSettingsToggle={lambda -> None { showSettings = not showSettings; }}
            onClear={lambda -> None { chat.clearMessages(); }}
            onClose={onToggle}
        />

        {showSettings and <ChatSettings
            apiKey={apiKey}
            selectedModel={selectedModel}
            modelOptions={modelOptions}
            onApiKeyChange={handleApiKeyChange}
            onModelChange={handleModelChange}
        /> or None}

        <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2.5">
            {chat.messages.length == 0 and <ChatEmptyState /> or None}

            {[
                <div key={String(msg.id)}>
                    <ChatMessage msg={msg} />
                </div>
                for msg in chat.messages
            ]}

            {showTyping and <div className="flex justify-start">
                <div className="px-3 py-2 rounded-xl rounded-bl-sm bg-gray-100 text-gray-400 text-xs">
                    <span className="chat-typing-dots">{"..."}</span>
                </div>
            </div> or None}

            <div ref={messagesEndRef}></div>
        </div>

        <CanvasConfirmModal
            pending={chat.pendingConfirm}
            onApprove={lambda -> None { chat.respondConfirm("ok"); }}
            onDeny={lambda -> None { chat.respondConfirm("deny"); }}
        />

        <ChatInput
            apiKey={apiKey}
            inputText={inputText}
            isLoading={chat.isLoading}
            inputRef={inputRef}
            onChange={lambda e: any -> None { inputText = e.target.value; }}
            onKeyDown={handleKeyDown}
            onSend={handleSend}
        />
    </div>;
}
