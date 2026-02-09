import from react { useRef }

def ToolIcon(props: dict) -> any {
    toolId = props.toolId;
    color = props.color or "currentColor";
    size = props.size or 18;

    if toolId == "select" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 3l7.07 16.97 2.51-7.39 7.39-2.51L3 3z" />
            <path d="M13 13l6 6" />
        </svg>;
    } elif toolId == "freehand" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
            <path d="m15 5 4 4" />
        </svg>;
    } elif toolId == "line" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round">
            <line x1="5" y1="19" x2="19" y2="5" />
        </svg>;
    } elif toolId == "arrow" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="5" y1="19" x2="19" y2="5" />
            <polyline points="10 5 19 5 19 14" />
        </svg>;
    } elif toolId == "rectangle" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" />
        </svg>;
    } elif toolId == "diamond" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2 L22 12 L12 22 L2 12 Z" />
        </svg>;
    } elif toolId == "circle" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2">
            <ellipse cx="12" cy="12" rx="10" ry="7" />
        </svg>;
    } elif toolId == "text" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="4 7 4 4 20 4 20 7" />
            <line x1="9.5" y1="20" x2="14.5" y2="20" />
            <line x1="12" y1="4" x2="12" y2="20" />
        </svg>;
    } elif toolId == "image" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
            <circle cx="8.5" cy="8.5" r="1.5" />
            <polyline points="21 15 16 10 5 21" />
        </svg>;
    }
    return <span>{toolId}</span>;
}

def:pub TopBar(props: dict) -> any {
    currentTool = props.currentTool or "freehand";
    onToolChange = props.onToolChange;
    onImageLoad = props.onImageLoad;
    fileInputRef = useRef(None);

    toolIds = ["select", "freehand", "line", "arrow", "rectangle", "diamond", "circle", "text", "image"];
    toolLabels = {
        "select": "Select (V)",
        "freehand": "Pencil (P)",
        "line": "Line (L)",
        "arrow": "Arrow (A)",
        "rectangle": "Rectangle (R)",
        "diamond": "Diamond (D)",
        "circle": "Ellipse (O)",
        "text": "Text (T)",
        "image": "Image"
    };

    def handleToolClick(toolId: str) -> None {
        if toolId == "image" {
            if fileInputRef.current {
                fileInputRef.current.click();
            }
        } else {
            onToolChange(toolId);
        }
    }

    def handleFileChange(e: dict) -> None {
        files = e.target.files;
        if files.length > 0 {
            file = files[0];
            reader = Reflect.construct(FileReader, []);
            reader.onload = lambda event: any -> None {
                img = Reflect.construct(Image, []);
                img.onload = lambda -> None {
                    onImageLoad({
                        "type": "image",
                        "x": 100,
                        "y": 100,
                        "width": img.width,
                        "height": img.height,
                        "src": event.target.result
                    });
                };
                img.src = event.target.result;
            };
            reader.readAsDataURL(file);
            e.target.value = "";
        }
    }

    return <header className="topbar bg-white/90 border-b border-gray-200/60 flex-shrink-0">
        <div className="h-12 px-4 flex items-center justify-between">
            # Logo
            <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 flex items-center justify-center shadow-sm overflow-hidden">
                    <svg width="36" height="36" viewBox="0 0 512 512">
                        <g transform="translate(256,256) rotate(-45) translate(-256,-256)">
                            <rect x="196" y="100" width="120" height="260" rx="6" fill="white" opacity="0.95"/>
                            <rect x="196" y="180" width="120" height="24" fill="#c4b5fd" opacity="0.7"/>
                            <rect x="196" y="220" width="120" height="24" fill="#c4b5fd" opacity="0.7"/>
                            <polygon points="196,360 316,360 256,420" fill="#fbbf24"/>
                            <polygon points="240,400 272,400 256,420" fill="#374151"/>
                            <rect x="196" y="100" width="120" height="40" rx="6" fill="#f9a8d4" opacity="0.9"/>
                        </g>
                        <path d="M340 370 Q360 340 380 355 Q400 370 420 345" stroke="white" strokeWidth="8" fill="none" strokeLinecap="round" opacity="0.6"/>
                    </svg>
                </div>
                <span className="text-base font-bold text-gray-800 tracking-tight">JaSketch</span>
            </div>

            # Tool buttons
            <div className="flex items-center gap-0.5 bg-gray-50 rounded-xl px-1.5 py-1 border border-gray-200/60">
                {toolIds.map(lambda toolId: any -> any {
                    isActive = currentTool == toolId and toolId != "image";
                    return <button
                        key={toolId}
                        onClick={lambda -> None { handleToolClick(toolId); }}
                        title={toolLabels[toolId]}
                        className={"w-9 h-9 rounded-lg flex items-center justify-center transition-all duration-150 " + (isActive and "bg-white text-violet-700 shadow-sm ring-1 ring-violet-200" or "text-gray-400 hover:bg-white/80 hover:text-gray-600")}
                    >
                        <ToolIcon toolId={toolId} size={18} color={isActive and "#7c3aed" or "currentColor"} />
                    </button>;
                })}
            </div>

            # Help text
            <span className="text-[10px] text-gray-400 hidden sm:block">Space+drag to pan | Scroll to zoom</span>
        </div>

        # Hidden file input
        <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            onChange={handleFileChange}
            className="hidden"
        />
    </header>;
}
