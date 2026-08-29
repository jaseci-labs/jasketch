"""DiagramPlanner — answers conceptual questions and plans diagram structure.

Returns a typed PlannerDecision with an optional BlueprintSpec and a next_step
that tells the orchestrator whether to chain directly into DiagramComposer.
"""

import from typing { Any }
import from .schemas { PlannerDecision, PlannerNextStep, BlueprintSpec, decode_json_object }

node DiagramPlanner {
    has model: str = "";
    has api_key: str = "";
    has llm: Any = None;

    # Returns JSON, not a typed PlannerDecision -- same reason as the router;
    # see decode_json_object() in schemas.jac. Decode with parse_planner_decision().
    def reason(message: str, conversation_log: str) -> str
        by self.llm(
            max_react_iterations=1,
            incl_info={
                "conversation": conversation_log
            }
        );
}

sem DiagramPlanner.reason = """
Answer conceptual/architectural questions and plan diagram structures.

Inputs:
  - message: the user's current message
  - conversation (from incl_info): rolling transcript of recent turns

Decision logic:
  - If the user asked to draw/create/render a diagram: set next_step=SYNTHESIZE, populate blueprint
  - If the user is asking a conceptual question or wants to discuss without drawing: set next_step=DONE, blueprint=null

OUTPUT FORMAT -- reply with a single JSON object and NOTHING else. No prose
outside it, no code fences:

  {
    "summary": "<your full explanation for the user>",
    "next_step": "DONE" | "SYNTHESIZE",
    "blueprint": null | {
      "title": "<short title>",
      "diagram_type": "architecture|sequence|mindmap|entity-relationship|flowchart|state|class|other",
      "description": "<1-2 sentences>",
      "components": ["<node>", ...],
      "relationships": ["<A sends X to B>", ...],
      "style": "<colour/style preferences>"
    }
  }

Use next_step=SYNTHESIZE with a populated blueprint when the user asked to draw;
DONE with blueprint=null for pure discussion.

BlueprintSpec fields to populate when next_step=SYNTHESIZE:
  - title: short descriptive title for the diagram
  - diagram_type: one of architecture, sequence, mindmap, entity-relationship, flowchart, state, class, other
  - description: 1-2 sentence summary of what the diagram shows
  - components: list of key shapes/entities to include as nodes
  - relationships: list describing how components connect, e.g. "User sends request to API Gateway"
  - style: color scheme or visual style preferences, e.g. "blue tones, minimal"

Never call tools. This is pure reasoning and planning only.

User message: {{message}}

Respond now.
""";


# ── Decoding ───────────────────────────────────────────────────────────────────

"""Turn the planner's JSON reply into a PlannerDecision.

Unparseable output still carries the model's prose, so hand that back as the
summary and stop -- the user sees the answer, and nothing is drawn from a reply
we could not read."""
def:pub parse_planner_decision(raw: str) -> PlannerDecision {
    data: dict = decode_json_object(raw);
    if not data {
        return PlannerDecision(
            summary=(raw or "").strip(), next_step=PlannerNextStep.DONE, blueprint=None
        );
    }

    summary: str = str(data.get("summary", "") or "").strip() or (raw or "").strip();
    step: PlannerNextStep = (
        PlannerNextStep.SYNTHESIZE
        if str(data.get("next_step", "")).strip().upper() == "SYNTHESIZE"
        else PlannerNextStep.DONE
    );

    raw_bp: Any = data.get("blueprint");
    if step != PlannerNextStep.SYNTHESIZE or not isinstance(raw_bp, dict) {
        return PlannerDecision(summary=summary, next_step=PlannerNextStep.DONE, blueprint=None);
    }

    bp: dict = raw_bp;
    blueprint: BlueprintSpec = BlueprintSpec(
        title=str(bp.get("title", "") or ""),
        diagram_type=str(bp.get("diagram_type", "") or "other"),
        description=str(bp.get("description", "") or ""),
        components=[str(c) for c in (bp.get("components") or [])],
        relationships=[str(r) for r in (bp.get("relationships") or [])],
        style=str(bp.get("style", "") or "")
    );
    return PlannerDecision(summary=summary, next_step=step, blueprint=blueprint);
}
