import from react { useRef }

def:pub ChatMessages(props: dict) -> JsxElement {
    chatMessages = props.messages or [];
    isLoading = props.isLoading or False;
    scrollRef = useRef(None);

    # Auto-scroll to bottom when messages change
    can with [chatMessages, isLoading] entry {
        if scrollRef.current {
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
        }
    }

    def renderToolCall(tc: dict) -> JsxElement {
        has expanded: bool = False;

        statusIcon = "";
        statusColor = "";
        if tc.status == "running" {
            statusIcon = "...";
            statusColor = "text-orange-500";
        } else {
            statusIcon = "done";
            statusColor = "text-green-500";
        }

        return <div key={tc.name} className="mt-1.5 rounded-md border border-gray-200 bg-white text-xs overflow-hidden">
            <button
                onClick={lambda -> None { expanded = not expanded; }}
                className="w-full flex items-center gap-1.5 px-2 py-1.5 hover:bg-gray-50 transition-colors text-left"
            >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#9ca3af" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z" />
                </svg>
                <span className="font-medium text-gray-600 flex-1">{tc.name}</span>
                <span className={statusColor + " text-[10px]"}>{statusIcon}</span>
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#9ca3af" strokeWidth="2" strokeLinecap="round" className={"transition-transform " + (expanded and "rotate-180" or "")}>
                    <polyline points="6 9 12 15 18 9" />
                </svg>
            </button>
            {expanded and <div className="px-2 py-1.5 border-t border-gray-100 bg-gray-50">
                <div className="mb-1">
                    <span className="text-[10px] font-semibold text-gray-400 uppercase">Args</span>
                    <pre className="text-[10px] text-gray-500 whitespace-pre-wrap break-all mt-0.5">{JSON.stringify(tc.arguments, None, 2)}</pre>
                </div>
                {tc.result and <div>
                    <span className="text-[10px] font-semibold text-gray-400 uppercase">Result</span>
                    <pre className="text-[10px] text-gray-500 whitespace-pre-wrap break-all mt-0.5">{JSON.stringify(tc.result, None, 2).slice(0, 500)}</pre>
                </div> or None}
            </div> or None}
        </div>;
    }

    def renderMessage(msg: dict) -> JsxElement {
        if msg.role == "user" {
            return <div key={msg.content} className="flex justify-end mb-3">
                <div className="max-w-[85%] rounded-xl rounded-br-sm bg-orange-50 border border-orange-100 px-3 py-2">
                    <p className="text-sm text-gray-700 whitespace-pre-wrap">{msg.content}</p>
                </div>
            </div>;
        } elif msg.role == "assistant" {
            return <div key={msg.content} className="flex justify-start mb-3">
                <div className="max-w-[85%]">
                    <div className="rounded-xl rounded-bl-sm bg-gray-50 border border-gray-100 px-3 py-2">
                        {msg.content and <p className="text-sm text-gray-700 whitespace-pre-wrap">{msg.content}</p> or None}
                    </div>
                    {msg.toolCalls and msg.toolCalls.length > 0 and <div className="mt-1">
                        {[renderToolCall(tc) for tc in msg.toolCalls]}
                    </div> or None}
                </div>
            </div>;
        } elif msg.role == "error" {
            return <div key={msg.content} className="flex justify-center mb-3">
                <div className="max-w-[90%] rounded-lg bg-red-50 border border-red-100 px-3 py-2">
                    <p className="text-xs text-red-600">{msg.content}</p>
                </div>
            </div>;
        }
        return None;
    }

    return <div ref={scrollRef} className="flex-1 overflow-y-auto px-3 py-3 chat-scrollbar">
        {chatMessages.length == 0 and
            <div className="flex flex-col items-center justify-center h-full text-center px-6">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#d1d5db" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="mb-3">
                    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                <p className="text-sm text-gray-400 font-medium">AI Whiteboard Assistant</p>
                <p className="text-xs text-gray-300 mt-1">Ask me to draw diagrams, flowcharts, or anything on the canvas.</p>
            </div>
        or
            <div>
                {[renderMessage(msg) for msg in chatMessages]}
                {isLoading and <div className="flex justify-start mb-3">
                    <div className="rounded-xl rounded-bl-sm bg-gray-50 border border-gray-100 px-4 py-3">
                        <div className="flex gap-1 items-center">
                            <div className="w-1.5 h-1.5 rounded-full bg-gray-400 chat-loading-dot" style={{"animationDelay": "0ms"}}></div>
                            <div className="w-1.5 h-1.5 rounded-full bg-gray-400 chat-loading-dot" style={{"animationDelay": "150ms"}}></div>
                            <div className="w-1.5 h-1.5 rounded-full bg-gray-400 chat-loading-dot" style={{"animationDelay": "300ms"}}></div>
                        </div>
                    </div>
                </div> or None}
            </div>
        }
    </div>;
}
