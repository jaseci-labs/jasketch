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

import asyncio;
import json;
import os;
import sys;
import threading;
import time;
import uuid;

import from jasketch_mcp.canvas_tool_provider { CanvasToolProvider }
import from typing { Any }
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
import from .subagents.analyzer { _set_analyst_provider }
import from .subagents.synthesizer { _set_composer_provider }
import from .subagents.refiner { _set_editor_provider }

# ── Globals ────────────────────────────────────────────────────────────────────

glob RELAY_URL: str = os.environ.get("JASKETCH_RELAY_URL", "ws://localhost:9601");
glob REQUEST_TIMEOUT: float = 40.0;

# WebSocket relay state (same pattern as MCP server)
glob _lock = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _pending: dict[str, Any] = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();

# Agent singletons (typed Any to avoid annotation-eval NameError at spawn time;
# visit dispatch uses actual runtime type so abilities still fire correctly)
glob _intent_router: Any = None;
glob _diagram_planner: Any = None;
glob _diagram_analyst: Any = None;
glob _diagram_composer: Any = None;
glob _diagram_editor: Any = None;

# Session context cache (ephemeral, per user lifetime)
glob _sessions: dict[str, SessionContext] = {};

def log(msg: str) -> None {
    print(f"[jasketch-orchestrator] {msg}", file=sys.stderr, flush=True);
}


# ── Session management ──────────────────────────────────────────────────────────

def _find_or_create_session(session_id: str) -> SessionContext {
    import from .session { SessionContext }
    if session_id not in _sessions {
        ctx: SessionContext = SessionContext();
        ctx.session_id = session_id;
        root() ++> ctx;
        _sessions[session_id] = ctx;
    }
    return _sessions[session_id];
}


# ── Relay connection (reuse MCP pattern) ──────────────────────────────────────

async def _connect_to_relay() -> None {
    global _ws, _connected;
    import websockets;

    while True {
        try {
            async with websockets.connect(RELAY_URL, compression=None) as ws {
                _ws = ws;
                _connected = True;
                log(f"Connected to relay at {RELAY_URL}");
                await ws.send(json.dumps({"role": "controller"}));

                async for raw in ws {
                    try {
                        msg: dict[str, Any] = json.loads(raw);
                        request_id: str = msg.get("requestId", "");
                        entry: Any = None;
                        with _lock {
                            entry = _pending.pop(request_id, None);
                        }
                        if entry is not None {
                            (evt, res) = entry;
                            if msg.get("success") {
                                res["data"] = msg.get("data");
                            } else {
                                res["error"] = msg.get("error", "Unknown error");
                            }
                            evt.set();
                        }
                    } except Exception as error {
                        log(f"Bad message: {error}");
                    }
                }
            }
        } except Exception as error {
            log(f"Relay connection error: {error}");
        }

        _ws = None;
        _connected = False;
        log("Disconnected from relay, reconnecting in 3s...");
        await asyncio.sleep(3);
    }
}

def _start_relay_thread() -> None {
    global _relay_loop;
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();
    _relay_loop.run_until_complete(_connect_to_relay());
}

def _send_command(action: str, data: dict | None = None, session_id: str = "", timeout: float | None = None) -> Any {
    if (not _connected) or (_ws is None) {
        raise Exception(f"Not connected to relay at {RELAY_URL}");
    }
    if not _relay_ready.wait(timeout=5) {
        raise Exception("Relay event loop not ready");
    }

    request_id: str = str(uuid.uuid4());
    evt: Any = threading.Event();
    res: dict[str, Any] = {};

    with _lock {
        _pending[request_id] = (evt, res);
    }

    payload: str = json.dumps({
        "requestId": request_id,
        "sessionId": session_id,
        "action": action,
        "data": data if data is not None else {}
    });

    try {
        future: Any = asyncio.run_coroutine_threadsafe(_ws.send(payload), _relay_loop);
        future.result(timeout=5);
    } except Exception as error {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Failed to send command: {error}");
    }

    effective_timeout: float = timeout if timeout is not None else REQUEST_TIMEOUT;
    if not evt.wait(timeout=effective_timeout) {
        with _lock {
            _pending.pop(request_id, None);
        }
        raise Exception(f"Request timed out ({effective_timeout}s)");
    }

    if "error" in res {
        raise Exception(res["error"]);
    }
    return res.get("data");
}


# ── Confirmation flow ─────────────────────────────────────────────────────────
"""Show confirm dialog and poll for result (max 30s)."""
def _request_confirm(provider: CanvasToolProvider, message: str) -> bool {
    confirm_id: str = str(uuid.uuid4());
    provider.call_tool("show_confirm", {"confirmId": confirm_id, "message": message});
    deadline: float = time.time() + 30.0;
    while time.time() < deadline {
        result: dict[str, Any] = json.loads(provider.call_tool("get_confirm_result", {"confirmId": confirm_id}));
        if result.get("result") == "ok" { return True; }
        if result.get("result") == "cancel" { return False; }
        time.sleep(0.5);
    }
    return False;
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


# ── WebSocket send helper ─────────────────────────────────────────────────────

"""Send JSON message to WebSocket asynchronously from thread context."""
def _send_ws(ws: Any, msg: dict[str, str], event_loop: Any) -> None {
    try {
        future: Any = asyncio.run_coroutine_threadsafe(ws.send(json.dumps(msg)), event_loop);
        future.result(timeout=5);
    } except Exception as error {
        log(f"WebSocket send error: {error}");
    }
}


# ── AgentOrchestrator ─────────────────────────────────────────────────────────

walker AgentOrchestrator {
    has session_id: str;
    has message: str;
    has api_key: str;
    has model: str;
    has ws: Any;
    has event_loop: Any;

    # Context state (populated during traversal)
    has _provider: CanvasToolProvider | None = None;
    has _session_context: SessionContext | None = None;

    can init_context with Root entry {
        # Find or create SessionContext for this session
        self._provider = CanvasToolProvider(
            send_fn=lambda (action: str, data: dict[str, Any]) -> Any {_send_command(action, data, self.session_id);}
        );

        # Find or create session context (persists across turns)
        self._session_context = _find_or_create_session(self.session_id);

        # Ensure agent singletons exist
        _ensure_agent_singletons(self.api_key, self.model);

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
            _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": "Canvas cleared."}, self.event_loop);
            _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
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
        decision: RouteDecision = _intent_router.handle(
            self.message,
            self._session_context.conversation_log,
            has_blueprint,
            self._session_context.canvas_summary
        );
        log(f"route_intent: route = {decision.route}");

        # Append user message to context
        self._session_context.append_turn("user", self.message);

        if decision.route == RouteTag.NO_ROUTE {
            self._session_context.append_turn("router", decision.reply);
            _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": decision.reply}, self.event_loop);
            _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
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
            _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": decision.reply}, self.event_loop);
            _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
        }
    }

    can build_blueprint with DiagramPlanner entry {
        if self._session_context is None { return; }
        if _diagram_planner is None { return; }

        log("build_blueprint: calling DiagramPlanner");

        # Call DiagramPlanner LLM — returns typed PlannerDecision
        decision: PlannerDecision = _diagram_planner.reason(
            self.message,
            self._session_context.conversation_log
        );
        log(f"build_blueprint: next_step = {decision.next_step}");

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
        _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": decision.summary}, self.event_loop);

        if decision.next_step == PlannerNextStep.SYNTHESIZE {
            log("build_blueprint: chaining to DiagramComposer");
            if _diagram_composer is not None { visit _diagram_composer; }
        } else {
            _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
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

        if not canvas_empty {
            # Canvas non-empty: request confirmation
            confirmed: bool = _request_confirm(
                self._provider,
                "Replace canvas content with new diagram?"
            );
            if not confirmed {
                log("compose_diagram: user declined to replace canvas");
                self._session_context.canvas_summary = "non-empty, user kept";
                _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": "Diagram creation cancelled. Canvas kept as-is."}, self.event_loop);
                _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
                return;
            }
            log("compose_diagram: user confirmed replacement");
        }

        if canvas_mode == "additive" {
            try {
                existing_elements_json = self._provider.call_tool("get_canvas_elements", {});
            } except Exception as e {
                log(f"compose_diagram: error fetching elements: {e}");
            }
        }

        # Set provider for DiagramComposer
        _set_composer_provider(self._provider);

        if _diagram_composer is None { return; }

        # Call DiagramComposer LLM
        response: str = _diagram_composer.compose(
            self.message,
            self._session_context.conversation_log,
            self._session_context.diagram_blueprint,
            canvas_mode,
            existing_elements_json
        );
        log(f"compose_diagram: response = {response[:80]}");

        self._session_context.clear_diagram_blueprint();
        self._session_context.append_turn("composer", response);
        _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": response}, self.event_loop);
        _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
        log("compose_diagram: done");
    }

    can explain_canvas with DiagramAnalyst entry {
        if self._session_context is None { return; }
        if self._provider is None { return; }
        if _diagram_analyst is None { return; }

        log("explain_canvas: starting DiagramAnalyst");
        _set_analyst_provider(self._provider);

        response: str = _diagram_analyst.explain(
            self.message,
            self._session_context.conversation_log
        );
        log(f"explain_canvas: response = {response[:80]}");

        self._session_context.append_turn("analyst", response);
        _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": response}, self.event_loop);
        _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
        log("explain_canvas: done");
    }

    can edit_canvas with DiagramEditor entry {
        if self._session_context is None { return; }
        if self._provider is None { return; }
        if _diagram_editor is None { return; }

        log("edit_canvas: starting DiagramEditor");
        _set_editor_provider(self._provider);

        response: str = _diagram_editor.revise(
            self.message,
            self._session_context.conversation_log
        );
        log(f"edit_canvas: response = {response[:80]}");

        self._session_context.append_turn("editor", response);
        _send_ws(self.ws, {"type": "message", "sessionId": self.session_id, "content": response}, self.event_loop);
        _send_ws(self.ws, {"type": "done", "sessionId": self.session_id}, self.event_loop);
        log("edit_canvas: done");
    }
}


# ── Helper functions ──────────────────────────────────────────────────────────

"""Create agent singleton nodes (idempotent)."""
def _ensure_agent_singletons(api_key: str, model_name: str) -> None {
    global _intent_router, _diagram_planner, _diagram_analyst, _diagram_composer, _diagram_editor;

    root_node: Any = root();

    if _intent_router is None {
        new_ir: IntentRouter = IntentRouter(model=model_name, api_key=api_key);
        _intent_router = new_ir;
        root_node ++> new_ir;
    }
    if _diagram_planner is None {
        new_dp: DiagramPlanner = DiagramPlanner(model=model_name, api_key=api_key);
        _diagram_planner = new_dp;
        root_node ++> new_dp;
    }
    if _diagram_analyst is None {
        new_da: DiagramAnalyst = DiagramAnalyst(model=model_name, api_key=api_key);
        _diagram_analyst = new_da;
        root_node ++> new_da;
    }
    if _diagram_composer is None {
        new_dc: DiagramComposer = DiagramComposer(model=model_name, api_key=api_key);
        _diagram_composer = new_dc;
        root_node ++> new_dc;
    }
    if _diagram_editor is None {
        new_de: DiagramEditor = DiagramEditor(model=model_name, api_key=api_key);
        _diagram_editor = new_de;
        root_node ++> new_de;
    }
}


# ── Public API ─────────────────────────────────────────────────────────────────
"""Run a single conversation turn via AgentOrchestrator."""
def _run_conversation(session_id: str, message: str, api_key: str, model: str, ws: Any, event_loop: Any) -> None {
    log(f"Running conversation for session {session_id}: {message[:50]}");

    try {
        # Spawn walker on root — triggers init_context ability and graph traversal
        root() spawn AgentOrchestrator(
            session_id=session_id,
            message=message,
            api_key=api_key,
            model=model,
            ws=ws,
            event_loop=event_loop
        );
    } except Exception as e {
        import traceback;
        log(f"ERROR in _run_conversation: {e}");
        log(traceback.format_exc());
        # Try to send error to client
        try {
            future: Any = asyncio.run_coroutine_threadsafe(
                ws.send(json.dumps({"type": "error", "sessionId": session_id, "message": str(e)})),
                event_loop
            );
            future.result(timeout=5);
        } except Exception { _ = None; }
    }
}

"""Boot the orchestrator and start relay connection."""
def _boot() -> None {
    log("Starting orchestrator");
    relay_thread: Any = threading.Thread(target=_start_relay_thread, daemon=True);
    relay_thread.start();
    _relay_ready.wait(timeout=5);
    log("Orchestrator ready");
}
