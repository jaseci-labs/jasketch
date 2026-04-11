"""JaSketch Chat Agent - relay + LLM chat handler."""

import asyncio;
import json;
import os;
import sys;
import threading;
import uuid;

import subprocess;
import websockets;
import litellm;
import from typing { Any }
import from chat.agent_tools { get_tools, execute }

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
# Chat WebSocket handler
# ============================================================

async def _ws_send(ws: Any, t: str, **kw: Any) -> None {
    kw["type"] = t;
    await ws.send(json.dumps(kw));
}

async def _acc_tc(acc: dict, tc: Any) -> None {
    i: Any = getattr(tc, "index", 0);
    if i not in acc { acc[i] = {"id": "", "name": "", "arguments": ""}; }
    tid: Any = getattr(tc, "id", None);
    if tid { acc[i]["id"] = tid; }
    fn: Any = getattr(tc, "function", None);
    if fn is not None {
        n: Any = getattr(fn, "name", None);
        a: Any = getattr(fn, "arguments", None);
        if n { acc[i]["name"] = n; }
        if a { acc[i]["arguments"] = acc[i]["arguments"] + a; }
    }
}

async def _chat_loop(ws: Any, api_key: str, model: str, msgs: list, session_id: str) -> None {
    tools: list = get_tools();
    # Closure capturing session_id — passed directly into execute() per call.
    # Never stored globally, so concurrent users never share send context.
    def _session_send(action: str, data: dict | None = None) -> Any {
        return send_command(action, data, session_id);
    }
    it: int = 0;
    while it < MAX_ITERS {
        it = it + 1;
        resp: Any = await litellm.acompletion(model=model, messages=msgs, tools=tools, api_key=api_key, stream=True);
        content: str = "";
        tca: dict = {};
        async for chunk in resp {
            ch: Any = getattr(chunk, "choices", None);
            if not ch or len(ch) == 0 { continue; }
            d: Any = getattr(ch[0], "delta", None);
            if d is None { continue; }
            c: Any = getattr(d, "content", None);
            if c { content = content + c; await _ws_send(ws, "token", content=c); }
            tl: Any = getattr(d, "tool_calls", None);
            if tl is not None { for tc in tl { await _acc_tc(tca, tc); } }
        }
        if len(tca) == 0 { await _ws_send(ws, "done"); return; }
        calls: list = [];
        for (_, td) in sorted(tca.items()) {
            calls.append({"id": td["id"], "type": "function", "function": {"name": td["name"], "arguments": td["arguments"]}});
        }
        am: dict = {"role": "assistant", "tool_calls": calls};
        if content { am["content"] = content; }
        msgs.append(am);
        for ci in calls {
            tn: str = ci["function"]["name"];
            ta: str = ci["function"]["arguments"];
            await _ws_send(ws, "tool_call", name=tn, arguments=ta);
            try { parsed: dict = json.loads(ta); }
            except Exception { parsed = {}; }
            tr: Any = await asyncio.to_thread(execute, tn, parsed, _session_send);
            await _ws_send(ws, "tool_result", name=tn, result=tr);
            msgs.append({"role": "tool", "tool_call_id": ci["id"], "content": tr});
        }
    }
    await _ws_send(ws, "error", message="Max iterations.");
    await _ws_send(ws, "done");
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
    # Start relay server as a subprocess — keeps it fully isolated, avoids Jac import issues
    subprocess.Popen(["jasketch-relay"], stderr=sys.stderr, stdout=sys.stdout);
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

glob _booted: Any = _boot();
