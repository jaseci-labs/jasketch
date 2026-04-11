"""JaSketch Chat Agent - relay + byllm ReAct chat handler."""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import websockets;
import from byllm.lib { Model, StreamEvent }
import from typing { Any }
import from jasketch_mcp.canvas_tool_provider { CanvasToolProvider }

glob RELAY_URL: str = os.environ.get("JASKETCH_RELAY_URL", "ws://localhost:9601");
glob CHAT_PORT: int = int(os.environ.get("JASKETCH_CHAT_PORT", "9602"));
glob REQUEST_TIMEOUT: float = 30.0;
glob MAX_ITERS: int = 10;

def log(msg: str) -> None { print(f"[jasketch-chat] {msg}", file=sys.stderr, flush=True); }


# ============================================================
# Relay
# ============================================================

glob _lock: Any = threading.Lock();
glob _ws: Any = None;
glob _connected: bool = False;
glob _canvas_sessions: Any = set();  # set of currently connected sessionIds
glob _pending: dict = {};
glob _relay_loop: Any = None;
glob _relay_ready: Any = threading.Event();

async def _relay_connect() -> None {
    global _ws, _connected, _canvas_sessions;
    while True {
        try {
            async with websockets.connect(RELAY_URL, compression=None) as ws {
                _ws = ws; _connected = True;
                log(f"Connected to relay at {RELAY_URL}");
                await ws.send(json.dumps({"role": "controller"}));
                async for raw in ws {
                    try {
                        m: dict = json.loads(raw);
                        mt: str = m.get("type", "");
                        if mt == "registered" {
                            # Relay sends currently connected sessions on registration
                            existing: list = m.get("connectedSessions", []);
                            for sid in existing { _canvas_sessions.add(sid); }
                            continue;
                        }
                        if mt == "canvasConnected" { _canvas_sessions.add(m.get("sessionId", "")); continue; }
                        if mt == "canvasDisconnected" { _canvas_sessions.discard(m.get("sessionId", "")); continue; }
                        rid: str = m.get("requestId", "");
                        e: Any = None;
                        with _lock { e = _pending.pop(rid, None); }
                        if e is not None {
                            (evt, res) = e;
                            if m.get("success") { res["data"] = m.get("data"); }
                            else { res["error"] = m.get("error", "Error"); }
                            evt.set();
                        }
                    } except Exception as ex { log(f"Relay err: {ex}"); }
                }
            }
        } except Exception as ex { log(f"Relay conn err: {ex}"); }
        _ws = None; _connected = False; _canvas_sessions = set();
        await asyncio.sleep(3);
    }
}

def _relay_thread() -> None {
    global _relay_loop;
    _relay_loop = asyncio.new_event_loop();
    asyncio.set_event_loop(_relay_loop);
    _relay_ready.set();
    _relay_loop.run_until_complete(_relay_connect());
}

def send_command(action: str, data: dict | None = None, session_id: str = "") -> Any {
    if (not _connected) or (_ws is None) { raise Exception("Not connected to relay."); }
    if not session_id { raise Exception("No sessionId provided."); }
    if session_id not in _canvas_sessions { raise Exception(f"No canvas for session '{session_id}'. Open JaSketch in browser."); }
    _relay_ready.wait(timeout=5);
    rid: str = str(uuid.uuid4());
    evt: Any = threading.Event();
    res: dict = {};
    with _lock { _pending[rid] = (evt, res); }
    try {
        f: Any = asyncio.run_coroutine_threadsafe(
            _ws.send(json.dumps({"requestId": rid, "sessionId": session_id, "action": action, "data": data or {}})), _relay_loop);
        f.result(timeout=5);
    } except Exception as ex {
        with _lock { _pending.pop(rid, None); }
        raise Exception(f"Send failed: {ex}");
    }
    if not evt.wait(timeout=REQUEST_TIMEOUT) {
        with _lock { _pending.pop(rid, None); }
        raise Exception("Timed out");
    }
    if "error" in res { raise Exception(res["error"]); }
    return res.get("data");
}


# ============================================================
# System prompt
# ============================================================

glob SYSTEM_PROMPT: str = """You are an AI sketch assistant in JaSketch, a hand-drawn whiteboard.

CANVAS: (0,0) top-left, X right, Y down, ~2000x1500. Start at (100,100).

RULES:
- Use create_elements for 2+ items (batch)
- Use draw_labeled_shape for shapes with text (auto-sizes)
- Use draw_connector to connect shapes by index (auto edges)
- Use add_title for titles
- Check get_bounding_box before adding to existing content

LAYOUT: Shapes min 140x60. Gap 200px H, 150px V.
COLORS: #1971c2 blue #1e1e1e black #e03131 red #2b8a3e green #f08c00 amber #0c8599 teal #9c36b5 purple #868e96 gray
FILLS: #e7f5ff #fff3bf #f3f0ff #ebfbee

Keep responses brief.""";


# ============================================================
# Agent node
# ============================================================

node AgentNode {
    has session_id: str;
    has llm: Model;
    has tool_provider: CanvasToolProvider;

    def use_canvas_tool(name: str, arguments: str) -> str {
        args: dict = {};
        try {
            if isinstance(arguments, dict) { args = arguments; }
            elif arguments { args = json.loads(arguments); }
        } except Exception { args = {}; }
        return self.tool_provider.call_tool(name, args);
    }

    def run_agent(message: str, chat_history: list[dict], system_prompt: str) -> str
        by self.llm(
            tools=[self.use_canvas_tool],
            max_react_iterations=MAX_ITERS,
            stream=True,
            logging=True,
            incl_info={
                "system_instructions": system_prompt,
                "conversation_history": chat_history,
                "available_canvas_tools": self.tool_provider.list_tools()
            }
        );
}

sem AgentNode.use_canvas_tool = """
Execute a JaSketch canvas tool by name.
The complete list of available tools with their descriptions and argument schemas
is in available_canvas_tools in your context — use those exact names.
Pass arguments as a flat dict matching the tool's inputSchema.
Returns the tool result as a JSON string.
""";
sem AgentNode.use_canvas_tool.name = "Tool name from available_canvas_tools, e.g. 'create_elements'.";
sem AgentNode.use_canvas_tool.arguments = "Tool arguments as a JSON-encoded string. Pass '{}' if no arguments needed.";

sem AgentNode.run_agent = """You are an AI sketch assistant in JaSketch, a hand-drawn whiteboard.

CANVAS: (0,0) top-left, X right, Y down, ~2000x1500. Start at (100,100).
RULES: Use create_elements for 2+ items. Use draw_labeled_shape for shapes with text.
Use draw_connector to connect shapes by index. Use add_title for titles.
Check get_bounding_box before adding to existing content.
LAYOUT: Shapes min 140x60. Gap 200px H, 150px V.
COLORS: #1971c2 blue #1e1e1e black #e03131 red #2b8a3e green #f08c00 amber #868e96 gray
Keep responses brief.""";
sem AgentNode.run_agent.message = "The user's latest message.";
sem AgentNode.run_agent.chat_history = "Prior conversation turns [{role, content}, ...].";
sem AgentNode.run_agent.system_prompt = "High-level canvas assistant instructions.";


# ============================================================
# Chat WebSocket handler
# ============================================================

async def _ws_send(ws: Any, t: str, **kw: Any) -> None {
    kw["type"] = t;
    await ws.send(json.dumps(kw));
}

async def _chat_loop(ws: Any, api_key: str, model: str, msgs: list, session_id: str) -> None {
    llm: Model = Model(model_name=model, api_key=api_key, call_params={});

    def _session_send(action: str, data: dict | None = None) -> Any {
        return send_command(action, data, session_id);
    }
    tool_provider: CanvasToolProvider = CanvasToolProvider(send_fn=_session_send);

    agent: AgentNode = AgentNode(
        session_id=session_id, llm=llm, tool_provider=tool_provider
    );

    non_system_msgs: list = [msg for msg in msgs if msg.get("role") != "system"];
    chat_history: list = non_system_msgs[:-1];
    last_msg: dict[str, Any] = non_system_msgs[-1] if non_system_msgs else {};
    user_message: str = str(last_msg.get("content", ""));

    event_loop: Any = asyncio.get_event_loop();

    def _run_in_thread() -> None {
        try {
            for stream_event in agent.run_agent(
                message=user_message,
                chat_history=chat_history,
                system_prompt=SYSTEM_PROMPT
            ) {
                event_type: str = stream_event.event_type;
                event_data: dict = stream_event.data;

                if event_type == "chunk" {
                    asyncio.run_coroutine_threadsafe(
                        _ws_send(ws, "token", content=event_data.get("content", "")),
                        event_loop
                    ).result();
                } elif event_type == "tool_call" {
                    asyncio.run_coroutine_threadsafe(
                        _ws_send(ws, "tool_call",
                            name=event_data.get("tool", ""),
                            arguments=json.dumps(event_data.get("args", {}))),
                        event_loop
                    ).result();
                } elif event_type == "tool_result" {
                    asyncio.run_coroutine_threadsafe(
                        _ws_send(ws, "tool_result",
                            name=event_data.get("tool", ""),
                            result=str(event_data.get("result", ""))),
                        event_loop
                    ).result();
                }
                # thought / steps_done / usage events dropped (not in WS protocol)
            }
            asyncio.run_coroutine_threadsafe(_ws_send(ws, "done"), event_loop).result();
        } except Exception as error {
            asyncio.run_coroutine_threadsafe(
                _ws_send(ws, "error", message=str(error)), event_loop
            ).result();
        }
    }

    await asyncio.to_thread(_run_in_thread);
}

async def _handler(ws: Any) -> None {
    log("Chat client connected");
    try {
        async for raw in ws {
            try {
                m: dict = json.loads(raw);
                if m.get("type") != "chat" { continue; }
                ak: str = m.get("apiKey", ""); md: str = m.get("model", "gpt-4o-mini");
                um: str = m.get("message", ""); hi: list = m.get("history", []);
                sid: str = m.get("sessionId", "");
                if not ak { await _ws_send(ws, "error", message="API key required."); continue; }
                if not um { continue; }
                if not sid { await _ws_send(ws, "error", message="No sessionId. Refresh the page."); continue; }
                log(f"Chat: {md}, session={sid}, {um[:60]}");
                msgs: list = [{"role": "system", "content": SYSTEM_PROMPT}];
                for h in hi { msgs.append({"role": h.get("role", "user"), "content": h.get("content", "")}); }
                msgs.append({"role": "user", "content": um});
                try { await _chat_loop(ws, ak, md, msgs, sid); }
                except Exception as e { log(f"LLM err: {e}"); await _ws_send(ws, "error", message=str(e)); }
            } except Exception as e {
                try { await _ws_send(ws, "error", message=str(e)); }
                except Exception { _ = 0; }
            }
        }
    } except websockets.ConnectionClosed { _ = 0; }
    log("Chat client disconnected");
}


# ============================================================
# Boot
# ============================================================

def _boot() -> None {
    log("Booting...");
    # Relay is started at app level in main.jac before this agent loads
    threading.Thread(target=_relay_thread, daemon=True).start();
    _relay_ready.wait(timeout=5);

    def _ws_server() -> None {
        loop: Any = asyncio.new_event_loop();
        asyncio.set_event_loop(loop);
        async def _s() -> None {
            async with websockets.serve(_handler, "0.0.0.0", CHAT_PORT) {
                log(f"Chat WS on :{CHAT_PORT}");
                await asyncio.Future();
            }
        }
        loop.run_until_complete(_s());
    }
    threading.Thread(target=_ws_server, daemon=True).start();
}
