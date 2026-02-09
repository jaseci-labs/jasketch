"""Main entry point for JaSketch - Modern Whiteboard Application."""

cl {
    # Client-side imports
    import from react { useState, useRef }
    import from .components.layout.TopBar { TopBar }
    import from .components.layout.Sidebar { Sidebar }
    import from .components.Canvas { Canvas }
    import ".styles.css";

    def:pub app() -> any {
        # Drawing tool state
        [currentTool, setCurrentTool] = useState("freehand");
        [currentColor, setCurrentColor] = useState("#1971c2");
        [currentStrokeWidth, setCurrentStrokeWidth] = useState(2);
        [currentFontSize, setCurrentFontSize] = useState(24);
        [currentFontFamily, setCurrentFontFamily] = useState("Virgil");
        [currentOpacity, setCurrentOpacity] = useState(1.0);
        [currentLineStyle, setCurrentLineStyle] = useState("solid");
        [currentFillColor, setCurrentFillColor] = useState("transparent");

        # Selection state (updated by Canvas via callback)
        [selectedElement, setSelectedElement] = useState(None);

        # Refs for cross-component communication
        clearCanvasRef = useRef(None);
        addElementRef = useRef(None);
        updateElementRef = useRef(None);

        def handleUpdateElement(changes: dict) -> None {
            if selectedElement and updateElementRef.current {
                updateElementRef.current(selectedElement.index, changes);
            }
        }

        return <div className="h-screen flex flex-col overflow-hidden bg-white">
            # Top Bar
            <TopBar
                currentTool={currentTool}
                onToolChange={lambda tool: any -> None { setCurrentTool(tool); }}
                onImageLoad={lambda element: any -> None {
                    if addElementRef.current {
                        addElementRef.current(element);
                    }
                }}
            />

            # Main Content Area
            <div className="flex-1 overflow-hidden relative">
                # Floating Left Sidebar
                <div className="absolute left-3 top-3 z-10">
                    <Sidebar
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentOpacity={currentOpacity}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentLineStyle={currentLineStyle}
                        currentFillColor={currentFillColor}
                        selectedElement={selectedElement}
                        onColorChange={lambda color: any -> None { setCurrentColor(color); }}
                        onStrokeWidthChange={lambda width: any -> None { setCurrentStrokeWidth(width); }}
                        onOpacityChange={lambda opacity: any -> None { setCurrentOpacity(opacity); }}
                        onFontSizeChange={lambda size: any -> None { setCurrentFontSize(size); }}
                        onFontFamilyChange={lambda font: any -> None { setCurrentFontFamily(font); }}
                        onLineStyleChange={lambda style: any -> None { setCurrentLineStyle(style); }}
                        onFillColorChange={lambda color: any -> None { setCurrentFillColor(color); }}
                        onUpdateElement={handleUpdateElement}
                    />
                </div>

                # Canvas Container
                <div className="w-full h-full">
                    <Canvas
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentOpacity={currentOpacity}
                        currentLineStyle={currentLineStyle}
                        currentFillColor={currentFillColor}
                        clearCanvasRef={clearCanvasRef}
                        addElementRef={addElementRef}
                        updateElementRef={updateElementRef}
                        onSelectionChange={lambda sel: any -> None { setSelectedElement(sel); }}
                        onToolChange={lambda tool: any -> None { setCurrentTool(tool); }}
                    />
                </div>
            </div>
        </div>;
    }
}
