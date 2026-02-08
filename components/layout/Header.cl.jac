def:pub Header() -> any {
    return <header className="backdrop-blur-md bg-white/90 border-b border-gray-200/60 flex-shrink-0">
        <div className="px-4 py-2 flex items-center justify-between">
            <div className="flex items-center gap-3">
                <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center shadow-sm">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z" fill="white"/>
                    </svg>
                </div>
                <h1 className="text-sm font-semibold text-gray-800">JaSketch</h1>
            </div>

            <div className="flex items-center gap-2">
                <span className="text-[10px] text-gray-400 hidden sm:block">Space+drag to pan | Scroll to zoom</span>
            </div>
        </div>
    </header>;
}
