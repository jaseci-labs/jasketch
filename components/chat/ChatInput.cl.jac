import from react { useRef }

def:pub ChatInput(props: dict) -> JsxElement {
    onSend = props.onSend;
    onStop = props.onStop;
    isLoading = props.isLoading or False;
    has inputValue: str = "";
    textareaRef = useRef(None);

    def handleKeyDown(e: any) -> None {
        # Prevent canvas shortcuts from firing
        e.stopPropagation();

        if e.key == "Enter" and not e.shiftKey {
            e.preventDefault();
            if inputValue.trim() and not isLoading {
                onSend(inputValue.trim());
                inputValue = "";
                if textareaRef.current {
                    textareaRef.current.style.height = "auto";
                }
            }
        }
    }

    def handleInput(e: any) -> None {
        inputValue = e.target.value;
        # Auto-grow textarea
        if textareaRef.current {
            textareaRef.current.style.height = "auto";
            textareaRef.current.style.height = Math.min(textareaRef.current.scrollHeight, 120) + "px";
        }
    }

    def handleSendClick() -> None {
        if inputValue.trim() and not isLoading {
            onSend(inputValue.trim());
            inputValue = "";
            if textareaRef.current {
                textareaRef.current.style.height = "auto";
            }
        }
    }

    return <div className="border-t border-gray-200/60 p-3">
        <div className="flex items-end gap-2">
            <textarea
                ref={textareaRef}
                value={inputValue}
                onInput={handleInput}
                onKeyDown={handleKeyDown}
                placeholder="Ask AI to draw something..."
                rows="1"
                className="flex-1 resize-none rounded-lg border border-gray-200 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-orange-500/50 focus:border-orange-300 bg-white placeholder-gray-400"
                style={{"maxHeight": "120px"}}
            />
            {isLoading and
                <button
                    onClick={onStop}
                    title="Stop generation"
                    className="w-8 h-8 rounded-lg bg-red-500 hover:bg-red-600 text-white flex items-center justify-center flex-shrink-0 transition-colors"
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                        <rect x="6" y="6" width="12" height="12" rx="1" />
                    </svg>
                </button>
            or
                <button
                    onClick={handleSendClick}
                    disabled={not inputValue.trim()}
                    title="Send message"
                    className={"w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-colors " + (inputValue.trim() and "bg-orange-500 hover:bg-orange-600 text-white" or "bg-gray-100 text-gray-300 cursor-not-allowed")}
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <line x1="22" y1="2" x2="11" y2="13" />
                        <polygon points="22 2 15 22 11 13 2 9 22 2" />
                    </svg>
                </button>
            }
        </div>
    </div>;
}
