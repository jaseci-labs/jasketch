"""DiagramPlanner — answers conceptual questions and plans diagram structure.

Returns a typed PlannerDecision with an optional BlueprintSpec and a next_step
that tells the orchestrator whether to chain directly into DiagramComposer.
"""

import from typing { Any }
import from .schemas { PlannerDecision, PlannerNextStep, BlueprintSpec }

node DiagramPlanner {
    has model: str = "";
    has api_key: str = "";

    def reason(message: str, conversation_log: str) -> PlannerDecision
        by llm(
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

Return a PlannerDecision with:
  - summary: your full explanation or reasoning text to display to the user
  - next_step: SYNTHESIZE when user asked to draw a diagram and blueprint is ready; DONE otherwise
  - blueprint: a BlueprintSpec object when next_step=SYNTHESIZE; null for pure conceptual discussions

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
