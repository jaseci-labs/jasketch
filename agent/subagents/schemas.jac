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
