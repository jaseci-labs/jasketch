import from react { useRef }

def ToolIcon(props: dict) -> JsxElement {
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

def:pub TopBar(props: dict) -> JsxElement {
    currentTool = props.currentTool or "select";
    onToolChange = props.onToolChange;
    onImageLoad = props.onImageLoad;
    fileInputRef = useRef(None);

    toolIds = ["select", "freehand", "line", "arrow", "rectangle", "diamond", "circle", "text", "image"];
    toolLabels = {
        "select": "Select",
        "freehand": "Pencil",
        "line": "Line",
        "arrow": "Arrow",
        "rectangle": "Rectangle",
        "diamond": "Diamond",
        "circle": "Ellipse",
        "text": "Text",
        "image": "Image"
    };
    toolShortcuts = {
        "select": "1",
        "freehand": "2",
        "line": "3",
        "arrow": "4",
        "rectangle": "5",
        "diamond": "6",
        "circle": "7",
        "text": "8",
        "image": "9"
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

    return <header className="topbar bg-white/95 border-b border-gray-200/60 flex-shrink-0">
        <div className="h-11 px-3 flex items-center justify-between">
            <div className="flex items-center gap-2 min-w-[120px]">
                <div className="w-9 h-9 rounded-lg shadow-sm overflow-hidden">
                    <svg width="100%" height="100%" viewBox="0 0 512 512">
                        <defs>
                            <linearGradient id="lbg" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stopColor="#f97316"/><stop offset="100%" stopColor="#ea580c"/></linearGradient>
                            <filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="4" dy="4" stdDeviation="12" floodColor="rgba(0,0,0,0.3)"/></filter>
                        </defs>
                        <rect width="512" height="512" rx="108" ry="108" fill="url(#lbg)"/>
                        <g transform="translate(256,256) rotate(-45) translate(-256,-256)" filter="url(#sh)">
                            <rect x="181" y="60" width="150" height="320" rx="8" fill="white" opacity="0.95"/>
                            <rect x="181" y="195" width="150" height="30" fill="#06b6d4" opacity="0.45"/>
                            <rect x="181" y="245" width="150" height="30" fill="#06b6d4" opacity="0.45"/>
                            <polygon points="181,380 331,380 256,460" fill="#fde68a"/>
                            <polygon points="228,420 284,420 256,458" fill="#374151"/>
                            <rect x="181" y="60" width="150" height="50" rx="8" fill="#f9a8d4" opacity="0.9"/>
                            <rect x="181" y="100" width="150" height="12" fill="#e5e7eb" opacity="0.5"/>
                        </g>
                        <path d="M350 385 Q375 350 400 368 Q425 385 445 358" stroke="white" strokeWidth="10" fill="none" strokeLinecap="round" opacity="0.6"/>
                    </svg>
                </div>
                <span className="text-sm font-bold text-gray-700 tracking-tight">JaSketch</span>
            </div>

            <div className="flex items-center gap-0.5 bg-gray-50 rounded-lg px-1 py-0.5">
                {toolIds.map(lambda toolId: any -> any {
                    isActive = currentTool == toolId and toolId != "image";
                    shortcut = toolShortcuts[toolId];
                    return <button
                        key={toolId}
                        onClick={lambda -> None { handleToolClick(toolId); }}
                        title={toolLabels[toolId] + (shortcut and (" (" + shortcut + ")") or "")}
                        className={"relative w-9 h-9 rounded-md flex flex-col items-center justify-center gap-0 transition-all duration-150 " + (isActive and "bg-white text-orange-600 shadow-sm" or "text-gray-400 hover:bg-white/60 hover:text-gray-600")}
                    >
                        <ToolIcon toolId={toolId} size={17} color={isActive and "#ea580c" or "currentColor"} />
                        {shortcut and <span className={"text-[7px] leading-none font-medium mt-px " + (isActive and "text-orange-400" or "text-gray-300")}>{shortcut}</span> or None}
                    </button>;
                })}
            </div>

            <div className="min-w-[120px] flex justify-end">
                <span className="text-[10px] text-gray-400 hidden sm:block">Scroll to pan | Ctrl+scroll to zoom</span>
            </div>
        </div>

        <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            onChange={handleFileChange}
            className="hidden"
        />
    </header>;
}
