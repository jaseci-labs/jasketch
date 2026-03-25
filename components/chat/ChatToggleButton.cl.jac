def:pub ChatToggleButton(props: dict) -> JsxElement {
    isOpen = props.isOpen or False;
    onClick = props.onClick;

    return <button
        onClick={onClick}
        title={isOpen and "Close chat" or "Open AI chat"}
        className={"w-10 h-10 rounded-full flex items-center justify-center shadow-lg transition-all duration-200 " + (isOpen and "bg-gray-500 hover:bg-gray-600" or "bg-orange-500 hover:bg-orange-600") + " text-white hover:scale-105"}
    >
        {isOpen and
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
        or
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
            </svg>
        }
    </button>;
}
