"""Multi-agent orchestration for JaSketch — AgentOrchestrator routes intent between specialized agents.

Graph topology:
  Root (singleton)
   ├──> IntentRouter (singleton, text-only router, no tools)
   ├──> DiagramPlanner (singleton, conceptual thinking, no tools)
   ├──> DiagramAnalyst (singleton, diagram explanation)
   ├──> DiagramComposer (singleton, diagram generation)
   ├──> DiagramEditor (singleton, diagram modification)
   └──> SessionContext (per-session, conversation history + canvas state)

Routing flow:
  Root → init_context → [keyword pre-check]
    → clear-canvas keywords → call clear_canvas directly, done (no LLM)
    → else → IntentRouter (text-only, tool-free router)
      → NO_ROUTE       → send decision.reply to user
      → ROUTE_PLAN     → DiagramPlanner
      → ROUTE_SYNTHESIZE → DiagramComposer
      → ROUTE_ANALYZE  → DiagramAnalyst
      → ROUTE_REFINE   → DiagramEditor

  DiagramPlanner:
    → next_step=DONE       → send decision.summary, done
    → next_step=SYNTHESIZE → send decision.summary, visit DiagramComposer
"""

import json;
import sys;
import threading;
import uuid;

import from typing { Any }
import from .canvas_mirror { CanvasMirror }
import from .canvas_tools { CanvasToolProvider }
import from .session { SessionContext }
import from .subagents {
    RouteTag,
    RouteDecision,
    PlannerNextStep,
    BlueprintSpec,
    PlannerDecision,
    IntentRouter,
    DiagramPlanner,
    DiagramAnalyst,
    DiagramComposer,
    DiagramEditor
}
import from .subagents.synthesizer { _set_composer_provider }
import from .subagents.refiner { _set_editor_provider }
import from .llm_factory { create_llm }

# ── Globals ────────────────────────────────────────────────────────────────────

glob _lock = threading.Lock();

# Confirmations in flight. The orchestrator runs on a worker thread and blocks on
# the Event while the browser's answer arrives as a SEPARATE request, which
# resolves it -- see resolve_confirm() in agent/chat.jac.
glob _pending_confirms: dict[str, tuple[Any, dict]] = {};

# Agent singletons, one per archetype, hung off root on first use.
glob _intent_router: IntentRouter | None = None;
glob _diagram_planner: DiagramPlanner | None = None;
glob _diagram_analyst: DiagramAnalyst | None = None;
glob _diagram_composer: DiagramComposer | None = None;
glob _diagram_editor: DiagramEditor | None = None;

# Session context cache (ephemeral, per user lifetime)
glob _sessions: dict[str, SessionContext] = {};

def log(msg: str) -> None {
    print(f"[jasketch-orchestrator] {msg}", file=sys.stderr, flush=True);
}


# ── Session management ──────────────────────────────────────────────────────────

def _find_or_create_session(anchor: Root, session_id: str) -> SessionContext {
    if session_id not in _sessions {
        ctx: SessionContext = SessionContext();
        ctx.session_id = session_id;
        anchor ++> ctx;
        _sessions[session_id] = ctx;
    }
    return _sessions[session_id];
}


"""Resolve a pending confirmation via chat WebSocket (called from server.jac)."""
def _resolve_confirm(confirm_id: str, result: str) -> None {
    entry: tuple[Any, dict] | None = None;
    with _lock {
        entry = _pending_confirms.pop(confirm_id, None);
    }
    if entry is not None {
        (evt, res) = entry;
        res["result"] = result;
        evt.set();
    }
}

"""Ask the browser a yes/no question and block until it answers (max 60s)."""
def _chat_confirm(sink: Any, session_id: str, message: str) -> str {
    confirm_id: str = str(uuid.uuid4());
    evt: Any = threading.Event();
    res: dict = {};
    with _lock {
        _pending_confirms[confirm_id] = (evt, res);
    }
    _emit(sink, {"type": "confirm", "sessionId": session_id, "confirmId": confirm_id, "message": message});
    if not evt.wait(timeout=60.0) {
        with _lock {
            _pending_confirms.pop(confirm_id, None);
        }
        return "cancel";
    }
    with _lock {
        _pending_confirms.pop(confirm_id, None);
    }
    return res.get("result", "cancel");
}


# ── Canvas inspection helper ──────────────────────────────────────────────────

"""Fast non-LLM check of canvas state via provider tool."""
def _check_canvas_empty(provider: CanvasToolProvider) -> bool {
    try {
        result: str = provider.call_tool("get_canvas_elements", {});
        data: dict = json.loads(result);
        return data.get("total", 0) == 0;
    } except Exception {
        return True;  # default to empty if error
    }
}


# ── Frame sink ────────────────────────────────────────────────────────────────

"""Hand one progress frame to the streaming endpoint draining this turn."""
def _emit(sink: Any, msg: dict[str, Any]) -> None {
    try {
        sink.put(msg);
    } except Exception as error {
        log(f"Frame sink error: {error}");
    }
}


# ── AgentOrchestrator ─────────────────────────────────────────────────────────

walker AgentOrchestrator {
    has session_id: str;
    has message: str;
    has api_key: str;
    has model: str;
    has sink: Any;
    has canvas: CanvasMirror;
    # The graph node the agent singletons and session contexts hang off. Passed
    # in rather than read from the ambient `root` because the turn runs on a
    # worker thread, off the request that started it.
    has anchor: Root;

    # Context state (populated during traversal)
    has _provider: CanvasToolProvider | None = None;
    has _session_context: SessionContext | None = None;

    can init_context with Root entry {
        # Find or create SessionContext for this session
        self._provider = CanvasToolProvider(send_fn=self.canvas.handle);

        # Find or create session context (persists across turns)
        self._session_context = _find_or_create_session(self.anchor, self.session_id);

        # Ensure agent singletons exist
        _ensure_agent_singletons(self.anchor, self.api_key, self.model);

        # Pre-routing: handle clear canvas directly without LLM
        msg_lower: str = self.message.lower();
        CLEAR_KEYWORDS: list[str] = [
            "clear canvas", "reset canvas", "delete everything", "clean canvas", "erase canvas",
            "clear the canvas", "wipe the canvas", "reset the canvas", "wipe canvas"
        ];
        is_clear_request: bool = False;
        for kw in CLEAR_KEYWORDS {
            if kw in msg_lower {
                is_clear_request = True;
                break;
            }
        }
        if is_clear_request {
            log("init_context: pre-routing clear canvas");
            if self._provider is not None {
                self._provider.call_tool("clear_canvas", {});
            }
            if self._session_context is not None {
                self._session_context.append_turn("user", self.message);
                self._session_context.append_turn("router", "Canvas cleared.");
            }
            _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": "Canvas cleared."});
            _emit(self.sink, {"type": "done", "sessionId": self.session_id});
            return;
        }

        if _intent_router is not None {
            visit _intent_router;
        }
    }

    can route_intent with IntentRouter entry {
        if self._session_context is None { return; }
        if _intent_router is None { return; }

        # Prepare context for IntentRouter
        has_blueprint: bool = len(self._session_context.diagram_blueprint) > 0;

        # Call IntentRouter LLM — returns typed RouteDecision
        log("route_intent: calling IntentRouter");
        _emit(self.sink, {"type": "agent_start", "sessionId": self.session_id, "agent": "Routing"});
        decision: RouteDecision = _intent_router.handle(
            self.message,
            self._session_context.conversation_log,
            has_blueprint,
            self._session_context.canvas_summary
        );
        log(f"route_intent: route = {decision.route}");
        _emit(self.sink, {"type": "agent_done", "sessionId": self.session_id, "agent": "Routing"});

        # Append user message to context
        self._session_context.append_turn("user", self.message);

        if decision.route == RouteTag.NO_ROUTE {
            self._session_context.append_turn("router", decision.reply);
            _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": decision.reply});
            _emit(self.sink, {"type": "done", "sessionId": self.session_id});
            log("route_intent: NO_ROUTE, done");
        } elif decision.route == RouteTag.ROUTE_PLAN {
            if _diagram_planner is not None { visit _diagram_planner; }
        } elif decision.route == RouteTag.ROUTE_SYNTHESIZE {
            if _diagram_composer is not None { visit _diagram_composer; }
        } elif decision.route == RouteTag.ROUTE_ANALYZE {
            if _diagram_analyst is not None { visit _diagram_analyst; }
        } elif decision.route == RouteTag.ROUTE_REFINE {
            if _diagram_editor is not None { visit _diagram_editor; }
        } else {
            # Fallback — treat as NO_ROUTE
            log(f"route_intent: unhandled route {decision.route}, sending fallback");
            _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": decision.reply});
            _emit(self.sink, {"type": "done", "sessionId": self.session_id});
        }
    }

    can build_blueprint with DiagramPlanner entry {
        if self._session_context is None { return; }
        if _diagram_planner is None { return; }

        log("build_blueprint: calling DiagramPlanner");

        _emit(self.sink, {"type": "agent_start", "sessionId": self.session_id, "agent": "Planning"});
        # Call DiagramPlanner LLM — returns typed PlannerDecision
        decision: PlannerDecision = _diagram_planner.reason(
            self.message,
            self._session_context.conversation_log
        );
        log(f"build_blueprint: next_step = {decision.next_step}");
        _emit(self.sink, {"type": "agent_done", "sessionId": self.session_id, "agent": "Planning"});

        # Persist blueprint to session if one was produced
        if decision.blueprint is not None {
            bp: BlueprintSpec = decision.blueprint;
            self._session_context.diagram_blueprint = json.dumps({
                "title": bp.title,
                "diagram_type": bp.diagram_type,
                "description": bp.description,
                "components": bp.components,
                "relationships": bp.relationships,
                "style": bp.style
            });
        }

        self._session_context.append_turn("planner", decision.summary);
        _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": decision.summary});

        if decision.next_step == PlannerNextStep.SYNTHESIZE {
            log("build_blueprint: chaining to DiagramComposer");
            if _diagram_composer is not None { visit _diagram_composer; }
        } else {
            _emit(self.sink, {"type": "done", "sessionId": self.session_id});
            log("build_blueprint: done");
        }
    }

    can compose_diagram with DiagramComposer entry {
        if self._session_context is None { return; }
        if self._provider is None { return; }

        log("compose_diagram: starting DiagramComposer");

        # Fast canvas check (non-LLM) to determine mode
        canvas_empty: bool = _check_canvas_empty(self._provider);
        log(f"compose_diagram: canvas_empty = {canvas_empty}");

        canvas_mode: str = "replace";
        existing_elements_json: str = "[]";
        existing_bounding_box: str = "{}";

        if not canvas_empty {
            # Canvas non-empty: request confirmation via chat
            confirm_result: str = _chat_confirm(
                self.sink,
                self.session_id,
                "Canvas is not empty. **Approve** to clear it and render the new diagram, or **Deny** to place it beside the existing content."
            );
            if confirm_result == "ok" {
                log("compose_diagram: user approved replace");
                # canvas_mode stays "replace"
            } else {
                log("compose_diagram: user denied replace, switching to additive mode");
                canvas_mode = "additive";
            }
        }

        if canvas_mode == "additive" {
            try {
                elements_result: str = self._provider.call_tool("get_canvas_elements", {});
                # call_tool returns JSON string; parse and re-serialize to ensure proper format
                parsed_els: dict = json.loads(elements_result);
                # Extract just the elements array if it's wrapped in a dict
                if isinstance(parsed_els, dict) and "elements" in parsed_els {
                    existing_elements_json = json.dumps(parsed_els["elements"]);
                } else {
                    existing_elements_json = elements_result;
                }
                log(f"compose_diagram: fetched {len(parsed_els) if isinstance(parsed_els, list) else len(parsed_els.get('elements', []))} existing elements");
            } except Exception as e {
                log(f"compose_diagram: error fetching elements: {e}");
                existing_elements_json = "[]";
            }
            try {
                bb_result: str = self._provider.call_tool("get_bounding_box", {});
                # call_tool returns JSON string; verify it's valid JSON
                parsed_bb: dict = json.loads(bb_result);
                existing_bounding_box = json.dumps(parsed_bb);
                log(f"compose_diagram: bounding box = {existing_bounding_box}");
            } except Exception as e {
                log(f"compose_diagram: error fetching bounding box: {e}");
                existing_bounding_box = "{}";
            }
        }

        # Set provider for DiagramComposer
        _set_composer_provider(self._provider);

        if _diagram_composer is None { return; }

        _emit(self.sink, {"type": "agent_start", "sessionId": self.session_id, "agent": "Synthesizing"});
        # Call DiagramComposer LLM
        response: str = _diagram_composer.compose(
            self.message,
            self._session_context.conversation_log,
            self._session_context.diagram_blueprint,
            canvas_mode,
            existing_elements_json,
            existing_bounding_box
        );
        log(f"compose_diagram: response = {response[:80]}");
        _emit(self.sink, {"type": "agent_done", "sessionId": self.session_id, "agent": "Synthesizing"});

        self._session_context.clear_diagram_blueprint();
        self._session_context.canvas_summary = "non-empty";
        self._session_context.append_turn("composer", response);
        _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": response});
        _emit(self.sink, {"type": "done", "sessionId": self.session_id});
        log("compose_diagram: done");
    }

    can explain_canvas with DiagramAnalyst entry {
        if self._session_context is None { return; }
        if self._provider is None { return; }
        if _diagram_analyst is None { return; }

        log("explain_canvas: starting DiagramAnalyst");

        _emit(self.sink, {"type": "agent_start", "sessionId": self.session_id, "agent": "Analyzing"});
        # Pre-fetch canvas elements directly (same pattern as _check_canvas_empty)
        canvas_elements_json: str = '{"elements":[],"total":0}';
        try {
            canvas_elements_json = self._provider.call_tool("get_canvas_elements", {});
        } except Exception as e {
            log(f"explain_canvas: error fetching elements: {e}");
        }
        log(f"explain_canvas: canvas_elements_json = {canvas_elements_json[:120]}");

        response: str = _diagram_analyst.explain(
            self.message,
            self._session_context.conversation_log,
            canvas_elements_json
        );
        log(f"explain_canvas: response = {response[:80]}");
        _emit(self.sink, {"type": "agent_done", "sessionId": self.session_id, "agent": "Analyzing"});

        self._session_context.append_turn("analyst", response);
        _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": response});
        _emit(self.sink, {"type": "done", "sessionId": self.session_id});
        log("explain_canvas: done");
    }

    can edit_canvas with DiagramEditor entry {
        if self._session_context is None { return; }
        if self._provider is None { return; }
        if _diagram_editor is None { return; }

        log("edit_canvas: starting DiagramEditor");
        _set_editor_provider(self._provider);

        _emit(self.sink, {"type": "agent_start", "sessionId": self.session_id, "agent": "Editing"});
        response: str = _diagram_editor.revise(
            self.message,
            self._session_context.conversation_log
        );
        log(f"edit_canvas: response = {response[:80]}");
        _emit(self.sink, {"type": "agent_done", "sessionId": self.session_id, "agent": "Editing"});

        self._session_context.append_turn("editor", response);
        _emit(self.sink, {"type": "message", "sessionId": self.session_id, "content": response});
        _emit(self.sink, {"type": "done", "sessionId": self.session_id});
        log("edit_canvas: done");
    }
}


# ── Helper functions ──────────────────────────────────────────────────────────

"""Create agent singleton nodes (idempotent)."""
def _ensure_agent_singletons(anchor: Root, api_key: str, model_name: str) -> None {

    llm_model: Any = create_llm(model_name, api_key);

    if _intent_router is None {
        new_ir: IntentRouter = IntentRouter(model=model_name, api_key=api_key);
        _intent_router = new_ir;
        anchor ++> new_ir;
    }
    _intent_router.llm = llm_model;

    if _diagram_planner is None {
        new_dp: DiagramPlanner = DiagramPlanner(model=model_name, api_key=api_key);
        _diagram_planner = new_dp;
        anchor ++> new_dp;
    }
    _diagram_planner.llm = llm_model;

    if _diagram_analyst is None {
        new_da: DiagramAnalyst = DiagramAnalyst(model=model_name, api_key=api_key);
        _diagram_analyst = new_da;
        anchor ++> new_da;
    }
    _diagram_analyst.llm = llm_model;

    if _diagram_composer is None {
        new_dc: DiagramComposer = DiagramComposer(model=model_name, api_key=api_key);
        _diagram_composer = new_dc;
        anchor ++> new_dc;
    }
    _diagram_composer.llm = llm_model;

    if _diagram_editor is None {
        new_de: DiagramEditor = DiagramEditor(model=model_name, api_key=api_key);
        _diagram_editor = new_de;
        anchor ++> new_de;
    }
    _diagram_editor.llm = llm_model;
}


# ── Public API ─────────────────────────────────────────────────────────────────

"""Run one conversation turn against `canvas`, streaming frames into `sink`.

Runs on a worker thread: the LLM calls are blocking, and the endpoint draining
`sink` needs to keep yielding while they are in flight."""
def run_conversation(
    session_id: str,
    message: str,
    api_key: str,
    model: str,
    sink: Any,
    canvas: CanvasMirror,
    anchor: Root
) -> None {
    log(f"Running conversation for session {session_id}: {message[:50]}");
    try {
        # Spawn walker on root — triggers init_context ability and graph traversal
        anchor spawn AgentOrchestrator(
            session_id=session_id,
            message=message,
            api_key=api_key,
            model=model,
            sink=sink,
            canvas=canvas,
            anchor=anchor
        );
    } except Exception as e {
        import traceback;
        log(f"ERROR in run_conversation: {e}");
        log(traceback.format_exc());
        _emit(sink, {"type": "error", "sessionId": session_id, "message": str(e)});
        _emit(sink, {"type": "done", "sessionId": session_id});
    }
}
