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
  1. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions
  2. Follow diagram_blueprint if provided; otherwise infer structure from message
  3. Design the COMPLETE elements[] array (all shapes, arrows, text labels)
  4. Call use_canvas_tool("render_elements", "{\"elements\": [...]}") with ALL elements
  5. Describe what was created

Workflow for additive mode:
  1. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions and existing bounding box
  2. Parse existing_elements_json to understand current layout
  3. Position new elements beside/below existing ones (no overlap)
  4. Call use_canvas_tool("create_elements", "{\"elements\": [...]}") to add without clearing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ELEMENT SCHEMAS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Shape (rectangle / circle / diamond):
  {
    "id": "<uuid-string>",
    "type": "rectangle",
    "x": 100, "y": 100, "width": 200, "height": 80,
    "shapeText": "Label text here",
    "color": "#1971c2",
    "fillColor": "transparent",
    "strokeWidth": 2,
    "lineStyle": "solid",
    "opacity": 1.0,
    "rotation": 0,
    "boundElements": ["<arrow-id-1>", "<arrow-id-2>"]
  }
  RULES:
  - boundElements MUST be a flat array of arrow ID strings — one string per arrow.
    CORRECT:   "boundElements": ["ar1", "ar2"]
    WRONG:     "boundElements": [{"id":"ar1","type":"arrow"}]
  - List EVERY arrow ID that connects to this shape.

Arrow:
  {
    "id": "<uuid-string>",
    "type": "arrow",
    "color": "#1e1e1e",
    "strokeWidth": 2,
    "lineStyle": "solid",
    "curveStyle": "curved",
    "opacity": 1.0,
    "startBinding": {"elementId": "<source-shape-id>", "side": "right"},
    "endBinding":   {"elementId": "<target-shape-id>", "side": "left"},
    "boundElements": null
  }
  RULES:
  - DO NOT set x, y, x1, y1, x2, y2, or points — the server auto-computes coordinates
    from startBinding/endBinding. Setting them manually causes rendering errors.
  - side must be one of: "top", "bottom", "left", "right" (no diagonals).
  - EVERY arrow MUST have both startBinding AND endBinding with valid shape IDs.

Text label (standalone):
  {
    "id": "<uuid-string>",
    "type": "text",
    "x": 100, "y": 60,
    "text": "Title",
    "color": "#1e1e1e",
    "fontSize": 24,
    "fontFamily": "Virgil",
    "opacity": 1.0,
    "rotation": 0,
    "boundElements": null
  }

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LAYOUT RULES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  - Start at x=100, y=100
  - Shape size: width=200, height=80 (increase width for long labels)
  - Horizontal spacing: next_x = prev_x + prev_width + 200
    (200px gap between right edge of one shape and left edge of next)
  - New row: next_y = prev_y + prev_height + 150
  - Arrow sides for horizontal left→right flow:
      startBinding.side = "right",  endBinding.side = "left"
  - Arrow sides for vertical top→bottom flow:
      startBinding.side = "bottom", endBinding.side = "top"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WORKED EXAMPLE — two shapes A → B (horizontal)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Shape A: {"id":"a1","type":"rectangle","x":100,"y":100,"width":200,"height":80,"shapeText":"Service A","color":"#1971c2","fillColor":"transparent","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
Shape B: {"id":"b1","type":"rectangle","x":500,"y":100,"width":200,"height":80,"shapeText":"Service B","color":"#1971c2","fillColor":"transparent","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
Arrow:   {"id":"ar1","type":"arrow","color":"#1e1e1e","strokeWidth":2,"lineStyle":"solid","curveStyle":"curved","opacity":1.0,"startBinding":{"elementId":"a1","side":"right"},"endBinding":{"elementId":"b1","side":"left"},"boundElements":null}

Note: x=500 = 100 + 200 + 200 (prev_x + prev_width + 200px gap)

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
