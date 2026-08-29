"""Shared schemas for JaSketch multi-agent routing and planning."""

# ── Routing ────────────────────────────────────────────────────────────────────

enum RouteTag {
    NO_ROUTE = "NO_ROUTE",
    ROUTE_PLAN = "ROUTE_PLAN",
    ROUTE_SYNTHESIZE = "ROUTE_SYNTHESIZE",
    ROUTE_ANALYZE = "ROUTE_ANALYZE",
    ROUTE_REFINE = "ROUTE_REFINE"
}
sem RouteTag.NO_ROUTE = "Handle directly — send a conversational reply to the user, no agent needed";
sem RouteTag.ROUTE_PLAN = "User wants to discuss, plan, or draw a diagram — route to DiagramPlanner";
sem RouteTag.ROUTE_SYNTHESIZE = "Blueprint already exists and user explicitly wants to render it now";
sem RouteTag.ROUTE_ANALYZE = "User wants the canvas explained, described, or analyzed";
sem RouteTag.ROUTE_REFINE = "User wants to modify, update, or edit the existing canvas diagram";

obj RouteDecision {
    has route: RouteTag;
    has reply: str;
}
sem RouteDecision = "The routing decision from IntentRouter";
sem RouteDecision.route = "The classified route tag";
sem RouteDecision.reply = "Direct reply to send to the user when route=NO_ROUTE; empty string otherwise";

# ── Planning ───────────────────────────────────────────────────────────────────

obj BlueprintSpec {
    has title: str;
    has diagram_type: str;
    has description: str;
    has components: list[str];
    has relationships: list[str];
    has style: str;
}
sem BlueprintSpec = "Structured plan for a diagram to be rendered";
sem BlueprintSpec.title = "Short descriptive title for the diagram";
sem BlueprintSpec.diagram_type = "One of: architecture, sequence, mindmap, entity-relationship, flowchart, state, class, other";
sem BlueprintSpec.description = "1-2 sentence summary of what the diagram shows";
sem BlueprintSpec.components = "List of key shapes or entities to include as nodes";
sem BlueprintSpec.relationships = "Descriptions of how components connect, e.g. 'User sends request to API Gateway'";
sem BlueprintSpec.style = "Color scheme or visual style preferences, e.g. 'blue tones, minimal'";

enum PlannerNextStep {
    DONE = "DONE",
    SYNTHESIZE = "SYNTHESIZE"
}
sem PlannerNextStep.DONE = "Planning complete, no drawing needed this turn";
sem PlannerNextStep.SYNTHESIZE = "Blueprint is ready and the diagram should be rendered immediately";

obj PlannerDecision {
    has summary: str;
    has next_step: PlannerNextStep;
    has blueprint: BlueprintSpec | None;
}
sem PlannerDecision = "The planning decision from DiagramPlanner";
sem PlannerDecision.summary = "Full explanation or reasoning text to display to the user";
sem PlannerDecision.next_step = "Set SYNTHESIZE when user asked to draw a diagram and blueprint is ready; otherwise DONE";
sem PlannerDecision.blueprint = "Structured diagram plan; null for pure conceptual discussions";


# ── Decoding LLM JSON ──────────────────────────────────────────────────────────
#
# The router and planner ask for JSON in the prompt and decode it here, rather
# than declaring a typed return and letting byllm generate a JSON schema.
#
# Not a style choice. byllm builds that schema from the compiler's
# FunctionInfo.return_type, which for these functions arrives as the bare type
# NAME instead of a ClassInfo, and it then dereferences .fields on that string:
#
#     AttributeError: 'str' object has no attribute 'fields'
#
# It fires before any request, so every routed turn died regardless of the API
# key. A `str` return skips schema generation entirely (see
# MTRuntime.get_output_schema: `if self.resp_type is str { return None; }`),
# which is why jacBuilder never hit this -- five of its six by-llm functions
# return str, and its one structured call sits in the same file as its type.
#
# Revisit once the compiler emits a ClassInfo here: typed returns are better,
# because the provider enforces the shape instead of us hoping for valid JSON.

import json;
import from typing { Any }


"""Pull a JSON object out of a model reply, tolerating prose and code fences."""
def:pub decode_json_object(raw: str) -> dict {
    text: str = (raw or "").strip();
    if text.startswith("```") {
        # ```json ... ``` -- drop the fence line and anything after the closer
        parts: list[str] = text.split("```");
        if len(parts) > 1 {
            text = parts[1];
            if text.startswith("json") {
                text = text[4:];
            }
        }
        text = text.strip();
    }
    # Models often wrap the object in a sentence; take the outermost braces.
    start: int = text.find("{");
    end: int = text.rfind("}");
    if start < 0 or end <= start {
        return {};
    }
    try {
        parsed: Any = json.loads(text[start:end + 1]);
    } except Exception {
        return {};
    }
    return parsed if isinstance(parsed, dict) else {};
}
