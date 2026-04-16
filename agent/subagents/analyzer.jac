"""DiagramAnalyst — explains/describes the diagram on the canvas.

Canvas elements are pre-fetched by the orchestrator and passed as canvas_elements_json.
Read-only agent: no modification tools.
"""

import json;
import from typing { Any }

node DiagramAnalyst {
    has model: str = "";
    has api_key: str = "";
    has llm: Any = None;

    def explain(message: str, conversation_log: str, canvas_elements_json: str) -> str
        by self.llm(
            tools=[],
            incl_info={
                "canvas_elements_json": canvas_elements_json,
                "conversation": conversation_log
            }
        );
}

sem DiagramAnalyst.explain = """
Explain the JaSketch canvas diagram to the user.

Canvas data is already provided in `canvas_elements_json` from context — parse it directly.

Element Types and Key Fields (runtime format):
  - rectangle / circle / diamond: x, y, width, height, shapeText (label inside shape), color, fillColor, boundElements (list of connected arrow IDs)
  - arrow / line: x1, y1 (start point), x2, y2 (end point) — coordinates computed by server from bindings
                  startBinding ({"elementId": "<id>", "side": "<side>"} — source shape reference),
                  endBinding   ({"elementId": "<id>", "side": "<side>"} — target shape reference),
                  curveStyle ("sharp"/"curved"/"elbow"), lineStyle ("solid"/"dashed"/"dotted")
  - text: x, y, text, fontSize, fontFamily
  - freehand: x, y, points (free-drawn path)

Your Task:
  1. Parse canvas_elements_json from incl_info to extract the "elements" array
  2. Identify shapes (by type + shapeText labels) and connections (arrows via startBinding/endBinding elementIds)
  3. Understand the overall diagram structure: what it represents, its purpose, layout
  4. Explain clearly: what diagram this is, what it shows, key components, and how they relate

If canvas_elements_json is empty or has no elements, explain that the canvas is currently empty.

Read-only: explain only, do NOT attempt to modify the canvas.

User message: {{message}}

Respond now.
""";
