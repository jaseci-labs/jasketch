import from .ChatMessages { ChatMessages }
import from .ChatInput { ChatInput }
import from .ChatSettings { ChatSettings }

def:pub ChatPanel(props: dict) -> JsxElement {
    chatHook = props.chatHook;

    return <div className="absolute right-0 top-0 z-20 h-full w-[380px] flex flex-col bg-white/95 backdrop-blur-xl border-l border-gray-200/60 shadow-md animate-slide-in-right">
        <div className="flex items-center justify-between px-3 py-2.5 border-b border-gray-200/60">
            <div className="flex items-center gap-2">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#f97316" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                <span className="text-sm font-semibold text-gray-700">AI Chat</span>
            </div>
            <div className="flex items-center gap-1">
                {chatHook.messages.length > 0 and <button
                    onClick={chatHook.clearMessages}
                    title="Clear messages"
                    className="w-7 h-7 rounded-md flex items-center justify-center text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="3 6 5 6 21 6" />
                        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                    </svg>
                </button> or None}

                <button
                    onClick={chatHook.toggleSettings}
                    title="Settings"
                    className={"w-7 h-7 rounded-md flex items-center justify-center transition-colors " + (chatHook.showSettings and "text-orange-500 bg-orange-50" or "text-gray-400 hover:text-gray-600 hover:bg-gray-100")}
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <circle cx="12" cy="12" r="3" />
                        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
                    </svg>
                </button>

                <button
                    onClick={chatHook.toggleOpen}
                    title="Close chat"
                    className="w-7 h-7 rounded-md flex items-center justify-center text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors"
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <line x1="18" y1="6" x2="6" y2="18" />
                        <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                </button>
            </div>
        </div>

        {chatHook.showSettings and <ChatSettings
            settings={chatHook.settings}
            onSave={chatHook.saveSettings}
            onClose={chatHook.toggleSettings}
        /> or None}

        <ChatMessages
            messages={chatHook.messages}
            isLoading={chatHook.isLoading}
        />

        <ChatInput
            onSend={chatHook.sendMessage}
            onStop={chatHook.stopGeneration}
            isLoading={chatHook.isLoading}
        />
    </div>;
}
