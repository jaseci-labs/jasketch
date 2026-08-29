"""The collaboration relay, as one broadcast WebSocket endpoint on the app port.

This used to be a standalone `websockets` server on port 9601 that kept a socket
per browser tab and routed each message to exactly the peers that needed it. A
`jac start --scale` deployment exposes exactly one containerPort, so that server
was unreachable in production without the Dockerfile and hand-written ingress
rules -- which is the whole reason both are gone.

Jac's own WebSocket support gives one fan-out primitive: `broadcast=True` sends
each frame this endpoint yields to EVERY client connected to it. So delivery is
now broadcast-plus-filter rather than point-to-point:

  - Every envelope carries the `room_id` (or `session_id`) it is addressed to,
    and clients drop what is not theirs.
  - Room scene payloads are ENCRYPTED in the browser under the room key from the
    URL fragment (services/scene_sharing.cl.jac), which the server never sees.
    So the bytes reaching an unrelated tab are opaque, and the server itself
    cannot read a scene either -- an improvement on the old relay, which handled
    every room's canvas in plaintext.
  - Presence is heartbeat-based. A broadcast endpoint gets no disconnect
    callback, so a member that has not been heard from within
    MEMBER_TIMEOUT_SECONDS is pruned and announced as left.

Multi-replica deployments MUST set `[scale.websocket] backplane = "redis"`, or a
broadcast only reaches the clients that happen to share a worker with the sender.
"""

import time;
import from typing { Any, Generator }

# Clients send a keepalive well inside this; three missed beats and the member is
# considered gone. Generous, because a laptop lid closing is not a departure.
glob MEMBER_TIMEOUT_SECONDS: float = 45.0;

glob CURSOR_COLORS: list[str] = [
    "#e74c3c", "#3498db", "#2ecc71", "#f39c12",
    "#9b59b6", "#1abc9c", "#e67e22", "#34495e"
];

# room_id -> {"host": session_id, "members": {session_id: {"username", "color", "seen"}}}
glob _rooms: dict[str, dict] = {};


def _now() -> float {
    return time.monotonic();
}


"""Drop members that stopped heart-beating; returns their leave envelopes."""
def _reap(room_id: str) -> list[dict] {
    room: dict = _rooms.get(room_id) or {};
    members: dict = room.get("members") or {};
    cutoff: float = _now() - MEMBER_TIMEOUT_SECONDS;
    stale: list[str] = [sid for (sid, m) in members.items() if m.get("seen", 0.0) < cutoff];
    envelopes: list[dict] = [];
    for sid in stale {
        members.pop(sid, None);
        envelopes.append({"kind": "room_member_left", "room_id": room_id, "session_id": sid});
    }
    if not members {
        _rooms.pop(room_id, None);
    }
    return envelopes;
}


def _join(room_id: str, session_id: str, username: str) -> list[dict] {
    if room_id not in _rooms {
        _rooms[room_id] = {"host": session_id, "members": {}};
    }
    room: dict = _rooms[room_id];
    members: dict = room["members"];
    known: bool = session_id in members;
    color: str = CURSOR_COLORS[len(members) % len(CURSOR_COLORS)];
    if known {
        color = str(members[session_id]["color"]);
    }
    members[session_id] = {"username": username or "Anonymous", "color": color, "seen": _now()};

    roster: dict = {
        sid: {"username": m["username"], "color": m["color"]}
        for (sid, m) in members.items() if sid != session_id
    };
    envelopes: list[dict] = [{
        "kind": "room_joined",
        "room_id": room_id,
        "session_id": session_id,
        "username": members[session_id]["username"],
        "cursor_color": color,
        "host_session_id": room["host"],
        "members": roster
    }];
    if not known {
        envelopes.append({
            "kind": "room_member_joined",
            "room_id": room_id,
            "session_id": session_id,
            "username": members[session_id]["username"],
            "cursor_color": color
        });
    }
    return envelopes;
}


"""Refresh a member's heartbeat. False when the sender is not in the room."""
def _touch(room_id: str, session_id: str) -> bool {
    members: dict = (_rooms.get(room_id) or {}).get("members") or {};
    if session_id not in members {
        return False;
    }
    member: dict = members[session_id];
    member["seen"] = _now();
    return True;
}


"""One relay exchange. Every yielded envelope reaches EVERY connected client;
each one names the room or session it belongs to so the rest can drop it."""
@restspec(protocol=APIProtocol.WEBSOCKET, broadcast=True)
def:pub jasketch_relay(
    kind: str = "",
    session_id: str = "",
    room_id: str = "",
    username: str = "",
    payload: str = "",
    x: float = 0.0,
    y: float = 0.0,
    request_id: str = "",
    action: str = "",
    data: dict = {},
    success: bool = False,
    error: str = ""
) -> Generator {
    def stream -> Generator[dict, None, None] {
        # Housekeeping first, so a departure is announced even on an unrelated frame.
        if room_id {
            for gone in _reap(room_id) {
                yield gone;
            }
        }

        if kind == "join_room" {
            if not (room_id and session_id) {
                return;
            }
            for envelope in _join(room_id, session_id, username) {
                yield envelope;
            }
            return;
        }

        if kind == "heartbeat" {
            _touch(room_id, session_id);
            return;
        }

        if kind == "leave_room" {
            room: dict = _rooms.get(room_id) or {};
            if (room.get("members") or {}).pop(session_id, None) is not None {
                yield {"kind": "room_member_left", "room_id": room_id, "session_id": session_id};
            }
            if not (room.get("members") or {}) {
                _rooms.pop(room_id, None);
            }
            return;
        }

        if kind == "end_session" {
            if room_id in _rooms {
                _rooms.pop(room_id, None);
                yield {"kind": "session_ended", "room_id": room_id};
            }
            return;
        }

        if kind == "room_broadcast" {
            # `payload` is ciphertext: only room members hold the key.
            if not _touch(room_id, session_id) {
                return;
            }
            yield {
                "kind": "room_update",
                "room_id": room_id,
                "session_id": session_id,
                "payload": payload
            };
            return;
        }

        if kind == "cursor_move" or kind == "update_username" {
            if not _touch(room_id, session_id) {
                return;
            }
            members: dict = (_rooms.get(room_id) or {}).get("members") or {};
            member: dict = members[session_id];
            if username {
                member["username"] = username;
            }
            yield {
                "kind": "cursor_update",
                "room_id": room_id,
                "session_id": session_id,
                "username": member["username"],
                "cursor_color": member["color"],
                "x": x,
                "y": y
            };
            return;
        }

        # ── Controller <-> canvas passthrough (the MCP bridge) ────────────────
        # Addressed by session_id / request_id; the canvas that owns the session
        # answers and the controller matches the reply by request_id.
        if kind == "command" {
            yield {
                "kind": "command",
                "session_id": session_id,
                "request_id": request_id,
                "action": action,
                "data": data
            };
            return;
        }
        if kind == "response" {
            yield {
                "kind": "response",
                "session_id": session_id,
                "request_id": request_id,
                "success": success,
                "data": data,
                "error": error
            };
            return;
        }
    }

    return stream();
}
