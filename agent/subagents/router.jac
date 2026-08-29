"""IntentRouter — pure text router, no tools, no drawing.

Classifies user intent and returns a typed RouteDecision.
Clear-canvas commands are handled upstream in the orchestrator before this agent is called.
"""

import from typing { Any }
import from .schemas { RouteTag, RouteDecision, decode_json_object }

node IntentRouter {
    has model: str = "";
    has api_key: str = "";
    has llm: Any = None;

    # Returns JSON, not a typed RouteDecision: see decode_json_object() in
    # schemas.jac for why a typed return cannot be used here yet. Decode with
    # parse_route_decision() below.
    def handle(message: str, conversation_log: str,
               has_diagram_blueprint: bool, canvas_summary: str) -> str
        by self.llm(
            incl_info={
                "conversation": conversation_log,
                "has_blueprint": has_diagram_blueprint,
                "canvas_state": canvas_summary
            }
        );
}
sem IntentRouter.handle = """
You are a ROUTING CLASSIFIER for JaSketch, a diagram drawing app.
Your ONLY job is to output a routing decision. You do NOT respond to users yourself (except NO_ROUTE).

OUTPUT FORMAT -- reply with a single JSON object and NOTHING else. No prose, no
code fences:

  {"route": "<ROUTE_TAG>", "reply": "<text>"}

route MUST be exactly one of:
  NO_ROUTE | ROUTE_PLAN | ROUTE_SYNTHESIZE | ROUTE_ANALYZE | ROUTE_REFINE

⚠ CRITICAL: You cannot draw diagrams — so NEVER say "I can't draw". Route to ROUTE_PLAN instead.
⚠ CRITICAL: reply MUST be "" (empty string) for every route EXCEPT NO_ROUTE. For NO_ROUTE, reply with a helpful conversational response.

ROUTING RULES — apply the first match:

ROUTE_PLAN → ANY request to create, draw, generate, design, sketch, build, or plan a diagram/chart/graph/flowchart.
  Examples: "draw a flowchart of login", "create an ER diagram", "make a sequence diagram",
            "design a microservices architecture", "draw me a state machine for checkout flow"
  → set reply = ""

ROUTE_SYNTHESIZE → ONLY when has_blueprint=true AND user explicitly says to render/draw/make it NOW.
  Examples: "draw it", "render it", "make it now", "go ahead", "yes do it"
  → set reply = ""

ROUTE_ANALYZE → user wants canvas EXPLAINED, described, or analyzed.
  Examples: "what's on the canvas?", "explain this diagram", "describe what you drew"
  → set reply = ""

ROUTE_REFINE → user wants to MODIFY existing canvas content (canvas_state non-empty).
  Examples: "change box color to red", "move the API gateway", "rename the User node", "delete that arrow"
  → set reply = ""

NO_ROUTE → ONLY for: greetings, small talk, off-topic questions, capability questions with NO drawing intent.
  Examples: "hi", "hello", "what can you do?", "how does JaSketch work?"
  → set reply = your helpful conversational response

Context available (from incl_info):
  - has_blueprint: true if a diagram blueprint is already planned and ready to render
  - canvas_state: 'empty', 'non-empty', or 'unknown' — current canvas content hint
  - conversation: recent conversation history

User message: {{message}}
""";


# ── Decoding ───────────────────────────────────────────────────────────────────

"""Turn the router's JSON reply into a RouteDecision.

Unparseable output is NOT an error the user should see: fall through to
ROUTE_PLAN, because a message that reached the router is far more likely to be a
drawing request than small talk, and drawing something wrong beats refusing."""
def:pub parse_route_decision(raw: str) -> RouteDecision {
    data: dict = decode_json_object(raw);
    label: str = str(data.get("route", "")).strip().upper();
    reply: str = str(data.get("reply", "") or "");

    by_name: dict[str, RouteTag] = {tag.name: tag for tag in RouteTag};
    if label in by_name {
        return RouteDecision(route=by_name[label], reply=reply);
    }
    if reply {
        # Well-formed JSON but an unknown tag, and it wrote something usable.
        return RouteDecision(route=RouteTag.NO_ROUTE, reply=reply);
    }
    return RouteDecision(route=RouteTag.ROUTE_PLAN, reply="");
}
