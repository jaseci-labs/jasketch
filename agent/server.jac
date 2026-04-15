"""JaSketch Chat Agent — thin shim that delegates to orchestrator.

Maintains chat WebSocket server infrastructure, delegates agent logic to multi-agent orchestrator.
"""

import asyncio;
import json;
import os;
import sys;
import threading;

import websockets;
import from typing { Any }
import from .orchestrator { _boot as _orchestrator_boot, _run_conversation }

glob CHAT_PORT: int = int(os.environ.get("JASKETCH_CHAT_PORT", "9602"));

def log(msg: str) -> None { print(f"[jasketch-chat] {msg}", file=sys.stderr, flush=True); }


# ============================================================
# Chat WebSocket handler
# ============================================================

async def _ws_send(ws: Any, t: str, **kw: Any) -> None {
    kw["type"] = t;
    await ws.send(json.dumps(kw));
}

async def _handler(ws: Any) -> None {
    log("Chat client connected");
    try {
        async for raw in ws {
            try {
                m: dict[str, Any] = json.loads(raw);
                if m.get("type") != "chat" { continue; }
                ak: str = m.get("apiKey", "");
                md: str = m.get("model", "gpt-4o-mini");
                um: str = m.get("message", "");
                sid: str = m.get("sessionId", "");

                if not ak {
                    await _ws_send(ws, "error", message="API key required.");
                    continue;
                }
                if not um { continue; }
                if not sid {
                    await _ws_send(ws, "error", message="No sessionId. Refresh the page.");
                    continue;
                }

                log(f"Chat: {md}, session={sid}, {um[:60]}");

                # Delegate to orchestrator (run in thread to avoid blocking async handler)
                loop: Any = asyncio.get_event_loop();
                loop.run_in_executor(None, _run_conversation, sid, um, ak, md, ws, loop);

            } except Exception as e {
                try { await _ws_send(ws, "error", message=str(e)); }
                except Exception { _ = None; }
            }
        }
    } except websockets.ConnectionClosed { _ = None; }
    log("Chat client disconnected");
}


# ============================================================
# Boot
# ============================================================

def _boot() -> None {
    log("Booting chat agent...");

    # Start orchestrator
    _orchestrator_boot();

    def _ws_server() {
        loop: Any = asyncio.new_event_loop();
        asyncio.set_event_loop(loop);
        async def _s() {
            server: Any = await websockets.serve(_handler, "0.0.0.0", CHAT_PORT);
            log(f"Chat WS on :{CHAT_PORT}");
            await asyncio.Future();
        }
        loop.run_until_complete(_s());
    }

    threading.Thread(target=_ws_server, daemon=True).start();
    log("Chat agent ready");
}
