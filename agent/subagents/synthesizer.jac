"""DiagramComposer — generates new diagrams from scratch or in additive mode.

Strategies:
  - replace mode (canvas empty or user approved): use render_elements with complete elements[]
  - additive mode: use get_viewport + existing elements, then create_elements to add beside existing
  - Always use startBinding/endBinding on arrows and boundElements on shapes for proper connectivity
"""

import from typing { Any }
import json;

node DiagramComposer {
    has model: str = "";
    has api_key: str = "";

    def compose(message: str, conversation_log: str, diagram_blueprint: str,
                canvas_mode: str, existing_elements_json: str) -> str
        by llm(
            tools=[use_canvas_tool],
            max_react_iterations=8,
            incl_info={
                "available_canvas_tools": [t for t in _composer_provider.list_tools() if t["name"] in COMPOSER_TOOLS],
                "conversation": conversation_log,
                "diagram_blueprint": diagram_blueprint,
                "canvas_mode": canvas_mode,
                "existing_elements_json": existing_elements_json
            }
        );
}

sem DiagramComposer.compose = """
Generate a complete diagram and render it to the canvas.

Inputs (from incl_info):
  - canvas_mode: "replace" (canvas empty or cleared) or "additive" (add beside existing)
  - existing_elements_json: current canvas elements JSON (non-empty only in additive mode)
  - diagram_blueprint: JSON-serialized BlueprintSpec from DiagramPlanner (may be empty string)
  - conversation: rolling transcript of recent turns

Workflow for replace mode:
  1. Call use_canvas_tool("get_drawing_guide", "{}") to confirm element schema
  2. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions
  3. Follow diagram_blueprint if provided; otherwise infer structure from message
  4. Design the COMPLETE elements[] array (all shapes, arrows, text)
  5. Call use_canvas_tool("render_elements", "{\"elements\": [...]}") with ALL elements
  6. Describe what was created

Workflow for additive mode:
  1. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions and existing bounding box
  2. Parse existing_elements_json to understand current layout
  3. Design new elements that fit beside/below existing ones
  4. Call use_canvas_tool("create_elements", "{\"elements\": [...]}") to add without clearing

Element Schemas:

Shape (rectangle / circle / diamond):
  {
    "id": "<uuid>",
    "type": "rectangle",
    "x": 100, "y": 100, "width": 200, "height": 80,
    "shapeText": "Label",
    "color": "#1971c2",
    "fillColor": "transparent",
    "strokeWidth": 2,
    "lineStyle": "solid",
    "opacity": 1.0,
    "rotation": 0,
    "boundElements": ["<arrow-id>"]
  }
  NOTE: boundElements MUST list ALL arrow IDs connected to this shape.

Arrow / Line:
  {
    "id": "<uuid>",
    "type": "arrow",
    "x": 300, "y": 140,
    "points": [[0, 0], [200, 0]],
    "color": "#000000",
    "strokeWidth": 2,
    "lineStyle": "solid",
    "curveStyle": "curved",
    "opacity": 1.0,
    "startBinding": {"elementId": "<shape-a-id>", "side": "right"},
    "endBinding":   {"elementId": "<shape-b-id>", "side": "left"},
    "boundElements": null
  }
  NOTE: points[0] is ALWAYS [0,0] (relative start). Last point is [dx, dy] offset to end.
  arrow.x,y = physical position of the start point (source shape's connecting edge).

Text:
  {
    "id": "<uuid>",
    "type": "text",
    "x": 100, "y": 60,
    "text": "Title",
    "color": "#000000",
    "fontSize": 24,
    "fontFamily": "Virgil",
    "opacity": 1.0,
    "rotation": 0,
    "boundElements": null
  }

Arrow Binding Rules (CRITICAL — follow exactly):
  1. EVERY arrow MUST have both startBinding AND endBinding referencing valid shape IDs
  2. Each shape's boundElements MUST list ALL arrow IDs connected to it
  3. Valid side values: "top", "bottom", "left", "right", "top-right", "top-left", "bottom-right", "bottom-left"
  4. For horizontal A→B flow:
       arrow.x = A.x + A.width
       arrow.y = A.y + A.height / 2
       points = [[0, 0], [B.x - (A.x + A.width), 0]]
       startBinding.side = "right"
       endBinding.side = "left"
  5. For vertical A→B flow:
       arrow.x = A.x + A.width / 2
       arrow.y = A.y + A.height
       points = [[0, 0], [0, B.y - (A.y + A.height)]]
       startBinding.side = "bottom"
       endBinding.side = "top"

Worked Example (two shapes A→B, horizontal):
  Shape A: {"id":"a1","type":"rectangle","x":100,"y":100,"width":200,"height":80,"shapeText":"Service A","color":"#1971c2","fillColor":"transparent","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
  Shape B: {"id":"b1","type":"rectangle","x":500,"y":100,"width":200,"height":80,"shapeText":"Service B","color":"#1971c2","fillColor":"transparent","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
  Arrow:   {"id":"ar1","type":"arrow","x":300,"y":140,"points":[[0,0],[200,0]],"color":"#000000","strokeWidth":2,"lineStyle":"solid","curveStyle":"curved","opacity":1.0,"startBinding":{"elementId":"a1","side":"right"},"endBinding":{"elementId":"b1","side":"left"},"boundElements":null}

Layout Guidelines:
  - Start at x=100, y=100
  - Horizontal gap between shapes: 200px
  - Vertical gap between rows: 150px
  - Minimum shape size: 140×60
  - Use shapeText for labels inside shapes

User message: {{message}}

Respond now.
""";

# ── Tool binding (populated by orchestrator before each call) ──────────────────

glob COMPOSER_TOOLS: list[str] = ["get_drawing_guide", "get_viewport", "render_elements", "create_elements"];

glob _composer_provider: Any = None;

def use_canvas_tool(name: str, arguments: str) -> str {
    args: dict = {};
    try {
        if isinstance(arguments, dict) { args = arguments; }
        elif arguments { args = json.loads(arguments); }
    } except Exception { args = {}; }
    return _composer_provider.call_tool(name, args);
}
sem use_canvas_tool = "Call a canvas tool by name. Only use tools listed in available_canvas_tools from context.";
sem use_canvas_tool.name = "Tool name — must exactly match one of the names in available_canvas_tools.";
sem use_canvas_tool.arguments = "JSON object string matching the inputSchema of the named tool. Build from the schema in available_canvas_tools.";

# ── Provider injection (called by orchestrator) ────────────────────────────────

def _set_composer_provider(provider: Any) -> None {
    global _composer_provider;
    _composer_provider = provider;
}
