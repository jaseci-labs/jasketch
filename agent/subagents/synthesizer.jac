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
    has llm: Any = None;

    def compose(message: str, conversation_log: str, diagram_blueprint: str,
                canvas_mode: str, existing_elements_json: str, existing_bounding_box: str) -> str
        by self.llm(
            tools=[use_canvas_tool],
            max_react_iterations=8,
            incl_info={
                "available_canvas_tools": [t for t in _composer_provider.list_tools() if t["name"] in COMPOSER_TOOLS],
                "conversation": conversation_log,
                "diagram_blueprint": diagram_blueprint,
                "canvas_mode": canvas_mode,
                "existing_elements_json": existing_elements_json,
                "existing_bounding_box": existing_bounding_box
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

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  CRITICAL: canvas_mode DETERMINES YOUR TOOL CHOICE ⚠️
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IF canvas_mode == "replace":
  → MUST use render_elements (this clears and replaces)
  → DO NOT use create_elements

IF canvas_mode == "additive":
  → MUST use create_elements (this adds without clearing)
  → DO NOT use render_elements
  → Place new diagram beside existing using existing_bounding_box

If you use the wrong tool, the diagram will not be placed correctly.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workflow for replace mode:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Call use_canvas_tool("get_drawing_guide", "{}") to load element schemas and styling palette
  2. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions
  3. Follow diagram_blueprint if provided; otherwise infer structure from message
  4. Design the COMPLETE elements[] array (all shapes, arrows, text labels) using the styling guide
  5. Run the PRE-RENDER CHECKLIST below — fix any issues before rendering
  6. Call use_canvas_tool("render_elements", "{\"elements\": [...]}")
     MUST include ALL elements (clears canvas first, then renders)
  7. Describe what was created

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Workflow for additive mode:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. Call use_canvas_tool("get_drawing_guide", "{}") to load element schemas and styling palette
  2. Call use_canvas_tool("get_viewport", "{}") to get canvas dimensions
  3. Parse existing_elements_json to understand what's already on the canvas
  4. Read existing_bounding_box from incl_info — format: {x, y, width, height}
     - If bounding_box has x, y, width, height:
       Place new diagram starting at: x + width + 120 (120px gap to the right)
     - If bounding_box is empty/null, start at x=100, y=100
  5. Design NEW elements only (DON'T include existing elements)
  6. Run the PRE-RENDER CHECKLIST below
  7. Call use_canvas_tool("create_elements", "{\"elements\": [...]}")
     MUST use create_elements, NOT render_elements
     Only pass your NEW elements
  8. Describe what was added

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
    "fillColor": "#e7f5ff",
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
  - Always set a semantic fillColor — see STYLING GUIDE below.

Arrow:
  {
    "id": "<uuid-string>",
    "type": "arrow",
    "color": "#1e1e1e",
    "strokeWidth": 2,
    "lineStyle": "solid",
    "curveStyle": "elbow",
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
STYLING GUIDE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

curveStyle — choose based on diagram type:
  "elbow"  → right-angle L/Z routing — USE FOR: architecture, flowchart, ER, sequence diagrams (DEFAULT)
  "curved" → smooth arcs — USE FOR: mindmaps, organic/relational diagrams
  "sharp"  → straight V-angle bends — USE FOR: simple linear flows, state machines

lineStyle — choose based on connection semantics:
  "solid"  → direct dependency, mandatory data flow (DEFAULT)
  "dashed" → optional, async, or event-driven connection
  "dotted" → annotation, inheritance hint, or conceptual/weak link

fillColor semantic palette — assign by node ROLE, not randomly:
  User-facing (client, browser, mobile):     color="#1971c2"  fillColor="#e7f5ff"
  Processing (service, handler, microservice): color="#2b8a3e"  fillColor="#ebfbee"
  Storage (database, cache, queue):           color="#0c8599"  fillColor="#e3fafc"
  Gateway/Router (API gw, load balancer):     color="#e8590c"  fillColor="#fff4e6"
  Async/Queue (message bus, event topic):     color="#9c36b5"  fillColor="#f8f0fc"
  External (third-party, external system):    color="#868e96"  fillColor="#f1f3f5"
  Decision (condition, branch — diamond):     color="#f08c00"  fillColor="#fff9db"
  Error/Warning (error handler, dead-letter): color="#e03131"  fillColor="#fff5f5"

Shape type semantics:
  "rectangle" → standard component, service, process, module
  "diamond"   → decision point, condition, branch
  "circle"    → start/end terminal, actor, external entity

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
PRE-RENDER CHECKLIST — verify ALL before calling render_elements
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✓ Every arrow has startBinding.elementId pointing to a valid shape ID in the array
  ✓ Every arrow has endBinding.elementId pointing to a valid shape ID in the array
  ✓ Every shape lists ALL connected arrow IDs in boundElements: ["ar1", ...]
  ✓ NO arrow has x, y, x1, y1, x2, y2, or points fields set
  ✓ All element IDs are unique strings across the entire elements array
  ✓ Every shape has a semantic fillColor (not all transparent)
  ✓ curveStyle matches the diagram type (elbow for architecture/flowchart, curved for mindmaps)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WORKED EXAMPLE — two shapes A → B (horizontal, architecture style)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Shape A: {"id":"a1","type":"rectangle","x":100,"y":100,"width":200,"height":80,"shapeText":"Client","color":"#1971c2","fillColor":"#e7f5ff","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
Shape B: {"id":"b1","type":"rectangle","x":500,"y":100,"width":200,"height":80,"shapeText":"API Service","color":"#2b8a3e","fillColor":"#ebfbee","strokeWidth":2,"lineStyle":"solid","opacity":1.0,"rotation":0,"boundElements":["ar1"]}
Arrow:   {"id":"ar1","type":"arrow","color":"#1e1e1e","strokeWidth":2,"lineStyle":"solid","curveStyle":"elbow","opacity":1.0,"startBinding":{"elementId":"a1","side":"right"},"endBinding":{"elementId":"b1","side":"left"},"boundElements":null}

Note: x=500 = 100 + 200 + 200 (prev_x + prev_width + 200px gap)
      Client uses user-facing palette (blue), API Service uses processing palette (green)

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
sem use_canvas_tool = "Call a canvas tool by name with JSON arguments. Always pass both 'name' and 'arguments' parameters.";
sem use_canvas_tool.name = "(required) Tool name — must exactly match one of: get_drawing_guide, get_viewport, render_elements, create_elements";
sem use_canvas_tool.arguments = "(required) JSON object string (not Python dict) matching the inputSchema of the named tool. Example: '{\"elements\": [...]}'  or '{}'  for tools with no inputs.";

# ── Provider injection (called by orchestrator) ────────────────────────────────

def _set_composer_provider(provider: Any) -> None {
    _composer_provider = provider;
}
