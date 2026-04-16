"""DiagramAnalyst — explains/describes the diagram on the canvas.

Fetches canvas elements via get_canvas_elements tool and provides analysis.
Read-only agent: no modification tools.
"""

import json;
import from typing { Any }

node DiagramAnalyst {
    has model: str = "";
    has api_key: str = "";
    has llm: Any = None;

    def explain(message: str, conversation_log: str) -> str
        by self.llm(
            tools=[use_canvas_tool],
            max_react_iterations=2,
            incl_info={
                "available_canvas_tools": [t for t in _analyst_provider.list_tools() if t["name"] in ANALYST_TOOLS],
                "conversation": conversation_log
            }
        );
}

sem DiagramAnalyst.explain = """
Explain the JaSketch canvas diagram to the user.

Workflow:
  1. Call use_canvas_tool("get_canvas_elements", "{}") to fetch the current diagram
  2. Analyze the elements to understand the diagram structure
  3. Explain to the user what the diagram shows, its purpose, key components, and relationships

Element Types and Key Fields (runtime format):
  - rectangle / circle / diamond: x, y, width, height, shapeText (label inside shape), color, fillColor, boundElements (list of connected arrow IDs)
  - arrow / line: x1, y1 (start point), x2, y2 (end point) — coordinates computed by server from bindings
                  startBinding ({"elementId": "<id>", "side": "<side>"} — source shape reference),
                  endBinding   ({"elementId": "<id>", "side": "<side>"} — target shape reference),
                  curveStyle ("sharp"/"curved"/"elbow"), lineStyle ("solid"/"dashed"/"dotted")
  - text: x, y, text, fontSize, fontFamily
  - freehand: x, y, points (free-drawn path)

Your Task:
  1. Fetch canvas elements via use_canvas_tool("get_canvas_elements", "{}")
  2. Identify shapes (by type + shapeText labels) and connections (arrows via startBinding/endBinding elementIds)
  3. Understand the overall diagram structure: what it represents, its purpose, layout
  4. Explain clearly: what diagram this is, what it shows, key components, and how they relate

Read-only: explain only, do NOT attempt to modify the canvas.

User message: {{message}}

Respond now.
""";

# ── Tool binding (populated by orchestrator before each call) ──────────────────

glob ANALYST_TOOLS: list[str] = ["get_canvas_elements"];

glob _analyst_provider: Any = None;

def use_canvas_tool(name: str, arguments: str) -> str {
    args: dict = {};
    try {
        if isinstance(arguments, dict) { args = arguments; }
        elif arguments { args = json.loads(arguments); }
    } except Exception { args = {}; }
    return _analyst_provider.call_tool(name, args);
}
sem use_canvas_tool = "Call a canvas tool by name. Only use tools listed in available_canvas_tools from context.";
sem use_canvas_tool.name = "Tool name — must exactly match one of the names in available_canvas_tools.";
sem use_canvas_tool.arguments = "JSON object string matching the inputSchema of the named tool. Build from the schema in available_canvas_tools.";

# ── Provider injection (called by orchestrator) ────────────────────────────────

def _set_analyst_provider(provider: Any) -> None {
    global _analyst_provider;
    _analyst_provider = provider;
}
