"""IntentRouter — pure text router, no tools, no drawing.

Classifies user intent and returns a typed RouteDecision.
Clear-canvas commands are handled upstream in the orchestrator before this agent is called.
"""

import from typing { Any }
import from .schemas { RouteTag, RouteDecision }

node IntentRouter {
    has model: str = "";
    has api_key: str = "";

    def handle(message: str, conversation_log: str,
               has_diagram_blueprint: bool, canvas_summary: str) -> RouteDecision
        by llm(
            incl_info={
                "conversation": conversation_log,
                "has_blueprint": has_diagram_blueprint,
                "canvas_state": canvas_summary
            }
        );
}
sem IntentRouter.handle = """
You are the JaSketch intent router. Classify the user's intent and return a RouteDecision.
You have NO tools. You cannot clear, draw, or modify the canvas.

Inputs available in context:
  - message: the user's current message to classify
  - conversation (from incl_info): rolling transcript of recent turns
  - has_blueprint (from incl_info): true if a diagram blueprint is ready to render
  - canvas_state (from incl_info): current canvas state hint — 'empty', 'non-empty', or 'unknown'

Classification Rules:
  - Greetings, small talk, off-topic questions → NO_ROUTE; write your conversational reply in the reply field
  - Questions about JaSketch capabilities → NO_ROUTE; answer directly in the reply field
  - Any diagram creation/planning request ("draw", "create", "make", "build", "design", "sketch") → ROUTE_PLAN
    DiagramPlanner will decide whether to immediately render based on the message
  - has_blueprint=true AND user says "draw it"/"render"/"make it"/"now" → ROUTE_SYNTHESIZE
  - User asks to explain/describe/analyze what's on the canvas → ROUTE_ANALYZE
  - User wants to modify/update/edit existing canvas diagram → ROUTE_REFINE
  - canvas_state empty/unknown + modification request → ROUTE_PLAN instead of ROUTE_REFINE

Return a RouteDecision with:
  - route: the RouteTag enum value matching the user's intent
  - reply: a conversational response when route=NO_ROUTE; empty string for all other routes

User message: {{message}}

Respond now.
""";
