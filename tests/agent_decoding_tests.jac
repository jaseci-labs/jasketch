"""Decoding the router's and planner's replies.

These parsers exist because a typed `by llm` return crashes the compiler's
schema path (see decode_json_object in agent/subagents/schemas.jac). That trade
moved shape enforcement from the provider to us, so the fallbacks matter: a
model that answers with prose, a fence, or a bad tag must still leave the agent
in a sane state rather than throwing at the user.
"""

import from agent.subagents.schemas { RouteTag, PlannerNextStep, decode_json_object }
import from agent.subagents.router { parse_route_decision }
import from agent.subagents.planner { parse_planner_decision }


test "a bare JSON object decodes" {
    assert decode_json_object('{"a": 1}') == {"a": 1};
}

test "a fenced JSON block decodes" {
    assert decode_json_object('```json' + chr(10) + '{"a": 1}' + chr(10) + '```') == {"a": 1};
}

test "JSON wrapped in prose decodes" {
    assert decode_json_object('Sure! {"a": 1} hope that helps') == {"a": 1};
}

test "junk decodes to an empty dict rather than raising" {
    assert decode_json_object("no json here") == {};
    assert decode_json_object("") == {};
    assert decode_json_object("{not valid}") == {};
}

test "the router maps every tag name it can emit" {
    for tag in RouteTag {
        decoded = parse_route_decision('{"route": "' + tag.name + '", "reply": ""}');
        assert decoded.route == tag;
    }
}

test "the router keeps the reply text" {
    decoded = parse_route_decision('{"route": "NO_ROUTE", "reply": "hi there"}');
    assert decoded.route == RouteTag.NO_ROUTE;
    assert decoded.reply == "hi there";
}

test "an unreadable router reply falls through to planning, not to a refusal" {
    # A message that reached the router is far likelier to be a drawing request
    # than small talk, so guessing PLAN beats answering nothing.
    decoded = parse_route_decision("the model rambled");
    assert decoded.route == RouteTag.ROUTE_PLAN;
}

test "a known-shape reply with an unknown tag still speaks to the user" {
    decoded = parse_route_decision('{"route": "NONSENSE", "reply": "here you go"}');
    assert decoded.route == RouteTag.NO_ROUTE;
    assert decoded.reply == "here you go";
}

test "the planner decodes a full blueprint" {
    decoded = parse_planner_decision(
        '{"summary": "a login flow", "next_step": "SYNTHESIZE", "blueprint": {'
        + '"title": "Login", "diagram_type": "flowchart", "description": "d",'
        + '"components": ["User", "API"], "relationships": ["User -> API"], "style": "blue"}}'
    );
    assert decoded.next_step == PlannerNextStep.SYNTHESIZE;
    assert decoded.summary == "a login flow";
    assert decoded.blueprint is not None;
    assert decoded.blueprint.title == "Login";
    assert decoded.blueprint.components == ["User", "API"];
}

test "SYNTHESIZE without a blueprint degrades to DONE instead of drawing nothing" {
    decoded = parse_planner_decision('{"summary": "s", "next_step": "SYNTHESIZE", "blueprint": null}');
    assert decoded.next_step == PlannerNextStep.DONE;
    assert decoded.blueprint is None;
}

test "an unreadable planner reply is still shown to the user" {
    decoded = parse_planner_decision("I think you want a flowchart.");
    assert decoded.next_step == PlannerNextStep.DONE;
    assert decoded.summary == "I think you want a flowchart.";
    assert decoded.blueprint is None;
}
