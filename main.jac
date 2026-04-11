"""Main entry point for JaSketch - Modern Whiteboard Application."""

import from typing { Any }
import from infrastructure.relay { start_relay_server }

glob _relay_started: Any = start_relay_server();

# Load and initialize agent
import from chat.agent { _boot }
glob _agent_booted: Any = _boot();

cl {
    # Client-side imports
    import from react { useRef }
    import from .components.layout.TopBar { TopBar }
    import from .components.layout.Sidebar { Sidebar }
    import from .components.layout.ChatPanel { ChatPanel }
    import from .components.Canvas { Canvas }
    import ".styles.css";

    def:pub app() -> JsxElement {
        # Drawing tool state
        has currentTool: str = "select";
        has currentColor: str = "#000000";
        has currentStrokeWidth: int = 2;
        has currentFontSize: int = 24;
        has currentFontFamily: str = "Virgil";
        has currentOpacity: float = 1.0;
        has currentLineStyle: str = "solid";
        has currentCurveStyle: str = "curved";
        has currentFillColor: str = "transparent";

        # Selection state (updated by Canvas via callback)
        has selectedElement: any = None;

        # Chat panel state
        has chatOpen: bool = False;

        # Refs for cross-component communication
        clearCanvasRef = useRef(None);
        addElementRef = useRef(None);
        updateElementRef = useRef(None);
        saveRef = useRef(None);
        loadElementsRef = useRef(None);

        def handleUpdateElement(changes: dict) -> None {
            if selectedElement and updateElementRef.current {
                updateElementRef.current(selectedElement.id, changes);
            }
        }

        return <div className="h-screen flex flex-col overflow-hidden bg-white">
            <TopBar
                currentTool={currentTool}
                onToolChange={lambda tool: any -> None { currentTool = tool; }}
                onImageLoad={lambda element: any -> None {
                    if addElementRef.current {
                        addElementRef.current(element);
                    }
                }}
                onSave={lambda -> None { if saveRef.current { saveRef.current(); } }}
                onLoad={lambda file: any -> None { if loadElementsRef.current { loadElementsRef.current(file); } }}
            />

            <div className="flex-1 overflow-hidden relative">
                <div className="absolute left-3 top-3 z-10">
                    <Sidebar
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentOpacity={currentOpacity}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentLineStyle={currentLineStyle}
                        currentCurveStyle={currentCurveStyle}
                        currentFillColor={currentFillColor}
                        selectedElement={selectedElement}
                        onColorChange={lambda color: any -> None { currentColor = color; }}
                        onStrokeWidthChange={lambda width: any -> None { currentStrokeWidth = width; }}
                        onOpacityChange={lambda opacity: any -> None { currentOpacity = opacity; }}
                        onFontSizeChange={lambda size: any -> None { currentFontSize = size; }}
                        onFontFamilyChange={lambda font: any -> None { currentFontFamily = font; }}
                        onLineStyleChange={lambda style: any -> None { currentLineStyle = style; }}
                        onCurveStyleChange={lambda style: any -> None { currentCurveStyle = style; }}
                        onFillColorChange={lambda color: any -> None { currentFillColor = color; }}
                        onUpdateElement={handleUpdateElement}
                    />
                </div>

                <div className="w-full h-full">
                    <Canvas
                        currentTool={currentTool}
                        currentColor={currentColor}
                        currentStrokeWidth={currentStrokeWidth}
                        currentFontSize={currentFontSize}
                        currentFontFamily={currentFontFamily}
                        currentOpacity={currentOpacity}
                        currentLineStyle={currentLineStyle}
                        currentCurveStyle={currentCurveStyle}
                        currentFillColor={currentFillColor}
                        clearCanvasRef={clearCanvasRef}
                        addElementRef={addElementRef}
                        updateElementRef={updateElementRef}
                        saveRef={saveRef}
                        loadElementsRef={loadElementsRef}
                        onSelectionChange={lambda sel: any -> None { selectedElement = sel; }}
                        onToolChange={lambda tool: any -> None { currentTool = tool; }}
                    />
                </div>

                <ChatPanel
                    isOpen={chatOpen}
                    onToggle={lambda -> None { chatOpen = not chatOpen; }}
                />

                <div className="absolute bottom-3 right-4 z-10 pointer-events-none">
                    <span className="text-[10px] tracking-wider text-gray-300 font-medium uppercase">
                        {"Powered by Jaseci"}
                    </span>
                </div>
            </div>
        </div>;
    }
}
