"""The chat transport: one streaming WebSocket endpoint on the app's own port.

What this replaces:

  browser --ws:9602--> chat server --ws:9601--> relay --ws:9601--> browser

Two hand-rolled `websockets` servers on two extra ports, plus a relay process,
so that a server-side agent could reach back into the browser for every canvas
tool call. A `jac start --scale` deployment exposes exactly one container port,
so none of that was reachable in production without a Dockerfile and bespoke
ingress rules.

Now the browser sends its canvas along with the message, the agent works on a
server-side copy of it (agent/canvas_mirror.jac), and the finished elements come
back on the same socket the request arrived on:

  browser --ws:8000/ws/function/jasketch_chat--> agent --frames--> browser

The turn runs on a worker thread because the LLM calls block, and this generator
has to keep yielding progress frames while they are in flight.
"""

import queue;
import threading;
import from typing { Any, Generator }

import from .canvas_mirror { CanvasMirror }
import from .orchestrator { run_conversation, _resolve_confirm }

# A composed diagram can take a while: several ReAct iterations, each a model
# round trip. This bounds a wedged turn, not a slow one.
glob TURN_TIMEOUT_SECONDS: float = 240.0;


"""Stream one agent turn. Frames: agent_start / agent_done / message / confirm /
elements / error / done -- `elements` carries the canvas for the browser to apply."""
@restspec(protocol=APIProtocol.WEBSOCKET)
def:pub jasketch_chat(
    message: str,
    api_key: str,
    session_id: str,
    elements: list = [],
    viewport: dict = {},
    model: str = "gpt-4o-mini"
) -> Generator {
    anchor: Root = root;

    def stream -> Generator[dict, None, None] {
        if not api_key {
            yield {"type": "error", "message": "API key required."};
            yield {"type": "done", "sessionId": session_id};
            return;
        }
        if not session_id {
            yield {"type": "error", "message": "No sessionId. Refresh the page."};
            yield {"type": "done", "sessionId": session_id};
            return;
        }
        if not message {
            yield {"type": "done", "sessionId": session_id};
            return;
        }

        canvas: CanvasMirror = CanvasMirror(
            elements=[dict(el) for el in elements],
            viewport=dict(viewport)
        );
        sink: Any = queue.Queue();
        threading.Thread(
            target=run_conversation,
            args=(session_id, message, api_key, model, sink, canvas, anchor),
            daemon=True
        ).start();

        while True {
            try {
                frame: dict = sink.get(timeout=TURN_TIMEOUT_SECONDS);
            } except queue.Empty {
                yield {"type": "error", "message": f"The agent did not finish within {TURN_TIMEOUT_SECONDS:.0f}s."};
                yield {"type": "done", "sessionId": session_id};
                return;
            }
            if frame.get("type") == "done" {
                # Hand back the canvas before closing the turn, so the browser
                # applies it in the same exchange it asked for.
                if canvas.touched {
                    yield {"type": "elements", "sessionId": session_id, "elements": canvas.elements};
                }
                yield frame;
                return;
            }
            yield frame;
        }
    }

    return stream();
}


"""Answer a `confirm` frame. Unblocks the turn thread waiting on that id."""
def:pub jasketch_chat_confirm(confirm_id: str, result: str) -> dict {
    _resolve_confirm(confirm_id, result);
    return {"ok": True};
}
