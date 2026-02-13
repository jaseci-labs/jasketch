import from "...constants.colors" { PRESET_COLORS }
import from "...constants.fonts" { FONTS, FONT_SIZES }
import from "...constants.tools" { LINE_STYLES }

def:pub Sidebar(props: dict) -> JsxElement {
    currentTool = props.currentTool or "freehand";
    currentColor = props.currentColor or "#1971c2";
    currentStrokeWidth = props.currentStrokeWidth or 2;
    currentOpacity = props.currentOpacity or 1.0;
    currentFontSize = props.currentFontSize or 24;
    currentFontFamily = props.currentFontFamily or "Virgil";
    currentLineStyle = props.currentLineStyle or "solid";
    currentFillColor = props.currentFillColor or "transparent";

    selectedElement = props.selectedElement;
    onColorChange = props.onColorChange;
    onStrokeWidthChange = props.onStrokeWidthChange;
    onOpacityChange = props.onOpacityChange;
    onFontSizeChange = props.onFontSizeChange;
    onFontFamilyChange = props.onFontFamilyChange;
    onLineStyleChange = props.onLineStyleChange;
    onFillColorChange = props.onFillColorChange;
    onUpdateElement = props.onUpdateElement;

    presetColors = PRESET_COLORS();
    fontSizes = FONT_SIZES();
    fonts = FONTS();
    lineStyles = LINE_STYLES();

    # Determine if we're editing an existing element or setting defaults for new ones
    hasSelection = selectedElement and selectedElement.element;
    sel = None;
    if hasSelection {
        sel = selectedElement.element;
    }

    # Determine what to show based on selection or tool
    showColor = False;
    showStroke = False;
    showOpacity = False;
    showFont = False;
    showFontSize = False;
    showLineStyle = False;
    showFillColor = False;

    activeColor = currentColor;
    activeStrokeWidth = currentStrokeWidth;
    activeOpacity = currentOpacity;
    activeFontSize = currentFontSize;
    activeFontFamily = currentFontFamily;
    activeLineStyle = currentLineStyle;
    activeFillColor = currentFillColor;

    if hasSelection {
        # Editing a selected element - show its properties
        elType = sel.type;
        if elType == "text" {
            showColor = True;
            showOpacity = True;
            showFont = True;
            showFontSize = True;
            activeColor = sel.color;
            activeOpacity = sel.opacity or 1.0;
            activeFontSize = sel.fontSize;
            activeFontFamily = sel.fontFamily;
        } elif elType == "freehand" or elType == "line" or elType == "arrow" or elType == "rectangle" or elType == "circle" or elType == "diamond" {
            showColor = True;
            showStroke = True;
            showOpacity = True;
            showLineStyle = True;
            activeColor = sel.color;
            activeStrokeWidth = sel.strokeWidth;
            activeOpacity = sel.opacity or 1.0;
            activeLineStyle = sel.lineStyle or "solid";
            if elType == "rectangle" or elType == "circle" or elType == "diamond" {
                showFillColor = True;
                activeFillColor = sel.fillColor or "transparent";
            }
        } elif elType == "image" {
            showOpacity = True;
            activeOpacity = sel.opacity or 1.0;
        }
    } else {
        # Setting defaults for new elements based on tool
        if currentTool == "text" {
            showColor = True;
            showOpacity = True;
            showFont = True;
            showFontSize = True;
        } elif currentTool != "select" {
            showColor = True;
            showStroke = True;
            showOpacity = True;
            if currentTool != "freehand" {
                showLineStyle = True;
            }
            if currentTool == "rectangle" or currentTool == "circle" or currentTool == "diamond" {
                showFillColor = True;
            }
        }
    }

    # Hide sidebar entirely when nothing to show
    hasContent = showColor or showStroke or showOpacity or showFont or showFontSize or showLineStyle or showFillColor or hasSelection;
    if not hasContent {
        return None;
    }

    # Handlers: update element if selected, or update tool defaults
    def handleColorChange(color: str) -> None {
        onColorChange(color);
        if hasSelection {
            onUpdateElement({"color": color});
        }
    }

    def handleStrokeWidthChange(width: int) -> None {
        onStrokeWidthChange(width);
        if hasSelection {
            onUpdateElement({"strokeWidth": width});
        }
    }

    def handleOpacityChange(opacity: float) -> None {
        onOpacityChange(opacity);
        if hasSelection {
            onUpdateElement({"opacity": opacity});
        }
    }

    def handleFontFamilyChange(font: str) -> None {
        onFontFamilyChange(font);
        if hasSelection {
            onUpdateElement({"fontFamily": font});
        }
    }

    def handleFontSizeChange(size: int) -> None {
        onFontSizeChange(size);
        if hasSelection {
            onUpdateElement({"fontSize": size});
        }
    }

    def handleLineStyleChange(style: str) -> None {
        onLineStyleChange(style);
        if hasSelection {
            onUpdateElement({"lineStyle": style});
        }
    }

    def handleFillColorChange(color: str) -> None {
        onFillColorChange(color);
        if hasSelection {
            onUpdateElement({"fillColor": color});
        }
    }

    return <div className="sidebar bg-white/90 backdrop-blur-xl rounded-2xl shadow-lg border border-gray-200/80 w-[210px] py-3 px-3 flex flex-col gap-3 animate-slide-in overflow-y-auto max-h-[calc(100vh-80px)]">

        # Header showing context
        {hasSelection and <div className="flex items-center gap-2 pb-1">
            <div className="w-2 h-2 rounded-full bg-violet-500"></div>
            <span className="text-[10px] font-semibold text-violet-600 uppercase tracking-wider">{sel.type + " selected"}</span>
        </div> or None}

        # Color Palette
        {showColor and <div>
            <span className="sidebar-label">Stroke</span>
            <div className="grid grid-cols-5 gap-1.5 mt-1.5">
                {presetColors.map(lambda color: any -> any {
                    isSelected = activeColor == color;
                    return <button
                        key={color}
                        onClick={lambda -> None { handleColorChange(color); }}
                        title={color}
                        className={"w-7 h-7 rounded-full transition-all duration-150 border border-gray-200/60 " + (isSelected and "ring-2 ring-violet-500 ring-offset-1 scale-110" or "hover:scale-110")}
                        style={{"backgroundColor": color}}
                    />;
                })}
            </div>
            <input
                type="color"
                value={activeColor}
                onChange={lambda e: any -> None { handleColorChange(e.target.value); }}
                title="Custom color"
                className="color-input w-full h-7 rounded-md cursor-pointer border border-gray-200 p-0 mt-1.5"
            />
        </div> or None}

        {showColor and <div className="h-px bg-gray-100"></div> or None}

        # Fill Color
        {showFillColor and <div>
            <span className="sidebar-label">Fill</span>
            <div className="flex items-center gap-1.5 mt-1.5">
                # Transparent (no fill) button
                <button
                    onClick={lambda -> None { handleFillColorChange("transparent"); }}
                    title="No fill"
                    className={"w-7 h-7 rounded-full border transition-all duration-150 flex items-center justify-center " + (activeFillColor == "transparent" and "ring-2 ring-violet-500 ring-offset-1 border-gray-300" or "border-gray-200 hover:scale-110")}
                    style={{"background": "repeating-conic-gradient(#e5e7eb 0% 25%, white 0% 50%) 50% / 8px 8px"}}
                >
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9ca3af" strokeWidth="2" strokeLinecap="round">
                        <line x1="4" y1="4" x2="20" y2="20" />
                    </svg>
                </button>
                # Use stroke color as fill
                <button
                    onClick={lambda -> None { handleFillColorChange(activeColor); }}
                    title="Fill with stroke color"
                    className={"w-7 h-7 rounded-full border transition-all duration-150 " + (activeFillColor != "transparent" and activeFillColor == activeColor and "ring-2 ring-violet-500 ring-offset-1 border-gray-300" or "border-gray-200 hover:scale-110")}
                    style={{"backgroundColor": activeColor, "opacity": 0.3}}
                />
                # Custom fill color picker
                <div className="relative">
                    <input
                        type="color"
                        value={activeFillColor != "transparent" and activeFillColor or "#ffffff"}
                        onChange={lambda e: any -> None { handleFillColorChange(e.target.value); }}
                        title="Custom fill color"
                        className="color-input w-7 h-7 rounded-full cursor-pointer border border-gray-200 p-0"
                    />
                </div>
            </div>
        </div> or None}

        {showFillColor and <div className="h-px bg-gray-100"></div> or None}

        # Stroke Width
        {showStroke and <div>
            <div className="flex items-center justify-between">
                <span className="sidebar-label">Stroke Width</span>
                <span className="text-[10px] text-gray-400 font-medium">{activeStrokeWidth + "px"}</span>
            </div>
            <input
                type="range"
                min="1"
                max="20"
                step="1"
                value={activeStrokeWidth}
                onChange={lambda e: any -> None { handleStrokeWidthChange(parseInt(e.target.value)); }}
                className="range-slider w-full mt-1.5"
            />
        </div> or None}

        # Line Style
        {showLineStyle and <div>
            <span className="sidebar-label">Line Style</span>
            <div className="flex items-center gap-1 mt-1.5">
                {lineStyles.map(lambda style: any -> any {
                    isActive = activeLineStyle == style.id;
                    return <button
                        key={style.id}
                        onClick={lambda -> None { handleLineStyleChange(style.id); }}
                        title={style.label}
                        className={"flex-1 h-8 rounded-lg flex items-center justify-center transition-all duration-150 " + (isActive and "bg-violet-50 ring-1 ring-violet-200" or "bg-gray-50 hover:bg-gray-100")}
                    >
                        <svg width="32" height="4" viewBox="0 0 32 4">
                            <line
                                x1="2" y1="2" x2="30" y2="2"
                                stroke={isActive and "#7c3aed" or "#9ca3af"}
                                strokeWidth="2"
                                strokeLinecap="round"
                                strokeDasharray={style.id == "dashed" and "6,4" or (style.id == "dotted" and "2,4" or "none")}
                            />
                        </svg>
                    </button>;
                })}
            </div>
        </div> or None}

        # Opacity
        {showOpacity and <div>
            <div className="flex items-center justify-between">
                <span className="sidebar-label">Opacity</span>
                <span className="text-[10px] text-gray-400 font-medium">{Math.round(activeOpacity * 100) + "%"}</span>
            </div>
            <input
                type="range"
                min="0"
                max="100"
                step="1"
                value={Math.round(activeOpacity * 100)}
                onChange={lambda e: any -> None { handleOpacityChange(parseInt(e.target.value) / 100); }}
                className="range-slider w-full mt-1.5"
            />
        </div> or None}

        # Font Options
        {showFont and <div>
            <div className="h-px bg-gray-100 mb-3"></div>
            <span className="sidebar-label">Font</span>
            <div className="flex flex-col gap-0.5 mt-1.5">
                {fonts.map(lambda font: any -> any {
                    isActive = activeFontFamily == font.id;
                    return <button
                        key={font.id}
                        onClick={lambda -> None { handleFontFamilyChange(font.id); }}
                        title={font.id}
                        className={"px-2 h-7 rounded-md flex items-center text-xs font-medium transition-all duration-150 whitespace-nowrap " + (isActive and "bg-violet-50 text-violet-700 ring-1 ring-violet-200" or "text-gray-500 hover:bg-gray-50")}
                        style={{"fontFamily": font.id}}
                    >
                        {font.label}
                    </button>;
                })}
            </div>
        </div> or None}

        {showFontSize and <div>
            <span className="sidebar-label mt-3">Size</span>
            <div className="grid grid-cols-3 gap-1 mt-1.5">
                {fontSizes.map(lambda size: any -> any {
                    isActive = activeFontSize == size;
                    return <button
                        key={size}
                        onClick={lambda -> None { handleFontSizeChange(size); }}
                        className={"h-7 rounded-md flex items-center justify-center text-xs font-medium transition-all duration-150 " + (isActive and "bg-violet-50 text-violet-700 ring-1 ring-violet-200" or "text-gray-500 hover:bg-gray-50")}
                    >
                        {size}
                    </button>;
                })}
            </div>
        </div> or None}
    </div>;
}
