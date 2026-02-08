"""Main entry point for JaSketch - Modern Whiteboard Application."""

cl {
    # Client-side imports
    import from react { useState }
    import from .components.layout.Header { Header }
    import from .components.Toolbar { Toolbar }
    import from .components.Canvas { Canvas }
    import ".styles.css";

    def:pub app() -> any {
        # Drawing tool state
        [currentTool, setCurrentTool] = useState("freehand");
        [currentColor, setCurrentColor] = useState("#1e1e1e");
        [currentStrokeWidth, setCurrentStrokeWidth] = useState(2);
        [currentFontSize, setCurrentFontSize] = useState(24);
        [currentFontFamily, setCurrentFontFamily] = useState("Inter");

        return <div className="h-screen flex flex-col overflow-hidden bg-white">
            # Modern Header
            <Header />

            # Main Content with Floating Toolbar
            <div className="flex flex-1 overflow-hidden relative">
                # Floating Left Toolbar
                <div className="absolute left-3 top-3 z-10">
                    <Toolbar
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        onToolChange={lambda tool: any -> None { setCurrentTool(tool); }}
                        onColorChange={lambda color: any -> None { setCurrentColor(color); }}
                        onStrokeWidthChange={lambda width: any -> None { setCurrentStrokeWidth(width); }}
                        onFontSizeChange={lambda size: any -> None { setCurrentFontSize(size); }}
                        onFontFamilyChange={lambda font: any -> None { setCurrentFontFamily(font); }}
                    />
                </div>

                # Canvas Container - Full Screen
                <div className="flex-1 flex items-center justify-center">
                    <Canvas
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                    />
                </div>
            </div>
        </div>;
    }
}
