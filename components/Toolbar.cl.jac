import from "..constants.colors" { PRESET_COLORS }
import from "..constants.fonts" { FONTS, FONT_SIZES }

def:pub ToolIcon(props: dict) -> any {
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
    } elif toolId == "circle" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2">
            <circle cx="12" cy="12" r="10" />
        </svg>;
    } elif toolId == "text" {
        return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="4 7 4 4 20 4 20 7" />
            <line x1="9.5" y1="20" x2="14.5" y2="20" />
            <line x1="12" y1="4" x2="12" y2="20" />
        </svg>;
    }
    return <span>{toolId}</span>;
}

def:pub Toolbar(props: dict) -> any {
    currentTool = props.currentTool or "freehand";
    currentColor = props.currentColor or "#1e1e1e";
    currentStrokeWidth = props.currentStrokeWidth or 2;
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Inter";

    onToolChange = props.onToolChange;
    onColorChange = props.onColorChange;
    onStrokeWidthChange = props.onStrokeWidthChange;
    onFontSizeChange = props.onFontSizeChange;
    onFontFamilyChange = props.onFontFamilyChange;

    presetColors = PRESET_COLORS();
    fontSizes = FONT_SIZES();
    fonts = FONTS();

    toolIds = ["select", "freehand", "line", "arrow", "rectangle", "circle", "text"];
    toolLabels = {
        "select": "Select",
        "freehand": "Pencil",
        "line": "Line",
        "arrow": "Arrow",
        "rectangle": "Rectangle",
        "circle": "Circle",
        "text": "Text"
    };

    return <div className="flex flex-row items-start gap-2">
        # Main Toolbar
        <div className="flex flex-col items-center py-2 px-1.5 gap-2 bg-white/90 backdrop-blur-xl rounded-xl shadow-lg border border-gray-200/80">
            # Tools Section
            <div className="flex flex-col gap-1">
                {toolIds.map(lambda toolId: any -> any {
                    isActive = currentTool == toolId;
                    return <button
                        key={toolId}
                        onClick={lambda -> None { onToolChange(toolId); }}
                        title={toolLabels[toolId]}
                        className={"w-9 h-9 rounded-lg flex items-center justify-center transition-all duration-150 " + (isActive and "bg-violet-100 text-violet-700 shadow-sm" or "text-gray-500 hover:bg-gray-100 hover:text-gray-700")}
                    >
                        <ToolIcon toolId={toolId} size={18} color={isActive and "#7c3aed" or "currentColor"} />
                    </button>;
                })}
            </div>

            # Divider
            <div className="w-6 h-px bg-gray-200"></div>

            # Color Section
            <div className="flex flex-col items-center gap-1.5">
                <div className="grid grid-cols-2 gap-1">
                    {presetColors.map(lambda color: any -> any {
                        isSelected = currentColor == color;
                        return <button
                            key={color}
                            onClick={lambda -> None { onColorChange(color); }}
                            title={color}
                            className={"w-4 h-4 rounded-full transition-all duration-150 " + (isSelected and "ring-2 ring-violet-500 ring-offset-1 scale-110" or "hover:scale-110")}
                            style={{"backgroundColor": color}}
                        />;
                    })}
                </div>
                <input
                    type="color"
                    value={currentColor}
                    onChange={lambda e: any -> None { onColorChange(e.target.value); }}
                    title="Custom color"
                    className="w-8 h-5 rounded cursor-pointer border border-gray-200 p-0"
                />
            </div>

            # Divider
            <div className="w-6 h-px bg-gray-200"></div>

            # Stroke Width Section
            <div className="flex flex-col items-center gap-1.5">
                <span className="text-[9px] font-semibold uppercase tracking-wider text-gray-400">{currentStrokeWidth + "px"}</span>
                <div className="flex flex-col items-center" style={{"height": "80px"}}>
                    <input
                        type="range"
                        min="1"
                        max="20"
                        step="1"
                        value={currentStrokeWidth}
                        onChange={lambda e: any -> None { onStrokeWidthChange(parseInt(e.target.value)); }}
                        title={"Stroke: " + String(currentStrokeWidth) + "px"}
                        className="stroke-slider"
                        style={{"writingMode": "vertical-lr", "direction": "rtl", "width": "20px", "height": "72px", "accentColor": "#7c3aed"}}
                    />
                </div>
            </div>
        </div>

        # Side Panel for Text Options (pops out to the right)
        {currentTool == "text" and <div className="flex flex-col items-center py-2 px-1.5 gap-2 bg-white/90 backdrop-blur-xl rounded-xl shadow-lg border border-gray-200/80">
            # Font Family
            <span className="text-[9px] font-semibold uppercase tracking-wider text-gray-400">Font</span>
            <div className="flex flex-col gap-0.5">
                {fonts.map(lambda font: any -> any {
                    isActive = currentFontFamily == font.id;
                    return <button
                        key={font.id}
                        onClick={lambda -> None { onFontFamilyChange(font.id); }}
                        title={font.id}
                        className={"px-2 h-7 rounded-md flex items-center justify-center text-[10px] font-medium transition-all duration-150 whitespace-nowrap " + (isActive and "bg-violet-100 text-violet-700" or "text-gray-500 hover:bg-gray-100")}
                        style={{"fontFamily": font.id}}
                    >
                        {font.label}
                    </button>;
                })}
            </div>

            <div className="w-6 h-px bg-gray-200"></div>

            # Font Size
            <span className="text-[9px] font-semibold uppercase tracking-wider text-gray-400">Size</span>
            <div className="flex flex-col gap-0.5">
                {fontSizes.map(lambda size: any -> any {
                    isActive = currentFontSize == size;
                    return <button
                        key={size}
                        onClick={lambda -> None { onFontSizeChange(size); }}
                        className={"w-9 h-6 rounded-md flex items-center justify-center text-[10px] font-medium transition-all duration-150 " + (isActive and "bg-violet-100 text-violet-700" or "text-gray-500 hover:bg-gray-100")}
                    >
                        {size}
                    </button>;
                })}
            </div>
        </div> or None}
    </div>;
}
