"""DiagramEditor — modifies existing canvas diagrams.

Strategies:
  - Small changes (recolor, relabel, move 1-3 elements): use update_element()
  - Structural changes (add layers, restructure, major additions): use render_elements with full updated array
  - Preserve element IDs when doing full re-render for visual continuity
  - All arrows in re-rendered output must use startBinding/endBinding; shapes must list arrow IDs in boundElements
"""

import from typing { Any }
import json;

node DiagramEditor {
    has model: str = "";
    has api_key: str = "";
    has llm: Any = None;

    def revise(message: str, conversation_log: str) -> str
        by self.llm(
            tools=[use_canvas_tool],
            max_react_iterations=10,
            incl_info={
                "available_canvas_tools": [t for t in _editor_provider.list_tools() if t["name"] in EDITOR_TOOLS],
                "conversation": conversation_log
            }
        );
}

sem DiagramEditor.revise = """
Modify the existing canvas diagram based on user request.

Workflow:
  1. Call use_canvas_tool("get_drawing_guide", "{}") to load element schemas and styling palette
  2. Call use_canvas_tool("get_canvas_elements", "{}") to fetch the current diagram
  3. Analyze the current elements
  4. Choose a strategy:
     - Small changes (recolor, relabel, move 1-3 elements):
         use use_canvas_tool("update_element", "{\"index\": N, \"changes\": {field: value}}")
     - Structural changes (add layers, restructure, major additions):
         use use_canvas_tool("render_elements", "{\"elements\": [...]}")
  5. Preserve element IDs when re-rendering for visual continuity
  6. Describe what changed

Arrow Binding Rules for full re-render (CRITICAL — follow exactly):
  - EVERY arrow MUST have both startBinding AND endBinding referencing valid shape IDs
  - Each shape's boundElements MUST list ALL arrow IDs connected to it
  - Arrow format: {"id":"<id>","type":"arrow","curveStyle":"elbow",
                   "startBinding":{"elementId":"<src-id>","side":"<side>"},
                   "endBinding":{"elementId":"<dst-id>","side":"<side>"},"boundElements":null}
  - DO NOT set x, y, x1, y1, x2, y2, or points on arrows — server computes from bindings
  - Valid side values: "top", "bottom", "left", "right" (no diagonals)
  - Use semantic fillColor and curveStyle from the drawing guide to maintain visual quality

User message: {{message}}

Respond now.
""";

# ── Tool binding (populated by orchestrator before each call) ──────────────────

glob EDITOR_TOOLS: list[str] = ["get_drawing_guide", "get_canvas_elements", "update_element", "render_elements"];

glob _editor_provider: Any = None;

def use_canvas_tool(name: str, arguments: str) -> str {
    args: dict = {};
    try {
        if isinstance(arguments, dict) { args = arguments; }
        elif arguments { args = json.loads(arguments); }
    } except Exception { args = {}; }
    return _editor_provider.call_tool(name, args);
}
sem use_canvas_tool = "Call a canvas tool by name. Only use tools listed in available_canvas_tools from context.";
sem use_canvas_tool.name = "Tool name — must exactly match one of the names in available_canvas_tools.";
sem use_canvas_tool.arguments = "JSON object string matching the inputSchema of the named tool. Build from the schema in available_canvas_tools.";

# ── Provider injection (called by orchestrator) ────────────────────────────────

def _set_editor_provider(provider: Any) -> None {
    _editor_provider = provider;
}
