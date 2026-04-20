"""JaSketch WebSocket Relay Server - session-isolated, multi-controller.

Each browser tab registers as a canvas with a unique sessionId.
Controllers (AI agents, MCP tools) are global — they can target any session.
Commands are routed to the correct canvas via sessionId in each message.
Responses route back to the originating controller via requestId tracking.

Protocol:
  Canvas:     {"role": "canvas",      "sessionId": "<uuid>"}
  Controller: {"role": "controller"}
  Command:    {"requestId": "r1", "sessionId": "<uuid>", "action": "...", "data": {...}}
  Response:   {"requestId": "r1", "success": true, "data": {...}}

State:
  _canvases[sessionId]    = ws                              (one canvas per tab)
  _controllers            = [ws, ...]                       (all agents, global)
  _request_map[requestId] = {"ctrl": ws, "session_id": str} (response routing)
"""

import asyncio;
import json;
import os;
import re;
import sys;
import threading;

import websockets;
import from typing { Any }

glob PORT: int = int(os.environ.get("JASKETCH_RELAY_PORT", "9601"));

glob _canvases: dict = {};      # sessionId -> ws
glob _controllers: Any = [];    # [ws, ...]
glob _request_map: dict = {};   # requestId -> {"ctrl": ws, "session_id": str}

# Collaboration room state
glob _rooms: dict = {};         # room_id -> {"members": {session_id: ws}, "cursor_states": {session_id: {username, color, x, y}}}

glob CURSOR_COLORS: list = [    # Palette for room member cursors
    "#e74c3c", "#3498db", "#2ecc71", "#f39c12",
    "#9b59b6", "#1abc9c", "#e67e22", "#34495e"
];

glob ROOM_ID_PATTERN: str = r'^[0-9a-f]{20}$';


def log(msg: str) -> None {
    print(f"[relay] {msg}", file=sys.stderr, flush=True);
}

def _valid_session_id(sid: str) -> bool {
    if not sid or len(sid) > 128 { return False; }
    return bool(re.match(r'^[a-zA-Z0-9_\-]+$', sid));
}

def _valid_room_id(room_id: str) -> bool {
    if not room_id or len(room_id) != 20 { return False; }
    return bool(re.match(ROOM_ID_PATTERN, room_id));
}

"""Assign cursor color to a new room member (round-robin from palette)."""
def _assign_cursor_color(room_id: str, session_id: str) -> str {
    room = _rooms.get(room_id, {});
    member_count = len(room.get("members", {}));
    return CURSOR_COLORS[member_count % len(CURSOR_COLORS)];
}

"""Delete room state and notify remaining members."""
async def _cleanup_room(room_id: str) -> None {
    if room_id not in _rooms { return; }
    room: Any = _rooms[room_id];

    members: Any = room.get("members", {});
    member_ids: Any = list(members.keys());
    mi = 0;
    while mi < len(member_ids) {
        sid = member_ids[mi];
        ws = members[sid];
        try {
            await ws.send(json.dumps({"type": "session_ended", "roomId": room_id}));
        } except Exception { _ = 0; }
        mi = mi + 1;
    }

    _rooms.pop(room_id, None);
    log(f"Room cleanup: {room_id}");
}


async def handler(ws: Any) -> None {
    role: str | None = None;
    session_id: str = "";

    try {
        async for raw in ws {
            msg: dict = {};
            try {
                msg = json.loads(raw);

                # ── Registration (first message only) ────────────────────────
                if msg.get("role") is not None and role is None {
                    role = msg["role"];

                    if role == "controller" {
                        _controllers.append(ws);
                        log(f"Controller connected ({len(_controllers)} total)");
                        sessions: Any = list(_canvases.keys());
                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "controller",
                            "connectedSessions": sessions
                        }));

                    } elif role == "canvas" {
                        sid: str = msg.get("sessionId", "");
                        if not _valid_session_id(sid) {
                            await ws.send(json.dumps({
                                "type": "error",
                                "message": "Invalid or missing sessionId. Must be alphanumeric/hyphens, max 128 chars."
                            }));
                            return;
                        }
                        session_id = sid;
                        _canvases[session_id] = ws;
                        log(f"Canvas connected: session={session_id}");

                        # Check for room join
                        room_id: str = msg.get("roomId", "");
                        if room_id and _valid_room_id(room_id) {
                            # ── Room Join Logic ────────────────────────────────────
                            username: str = msg.get("username", "Anonymous");
                            cursor_color: str = msg.get("cursorColor", "");
                            encrypted_scene: str = msg.get("encrypted_scene", "");

                            # Initialize room if first member
                            if room_id not in _rooms {
                                _rooms[room_id] = {"members": {}, "cursor_states": {}, "host_session_id": session_id};
                                log(f"Room created: {room_id}");
                            }

                            room: Any = _rooms[room_id];

                            # Assign cursor color if not provided
                            if not cursor_color {
                                cursor_color = _assign_cursor_color(room_id, session_id);
                            }

                            # Add member to room
                            room["members"][session_id] = ws;
                            room["cursor_states"][session_id] = {
                                "username": username,
                                "color": cursor_color,
                                "x": 0.0,
                                "y": 0.0
                            };

                            log(f"Member joined room {room_id}: {session_id} ({username})");

                            # Build existing members dict for the new joiner (exclude self)
                            rj_existing_members = {};
                            for msid in room.get("cursor_states", {}) {
                                if msid != session_id {
                                    mcs = room.get("cursor_states", {})[msid];
                                    rj_existing_members[msid] = {"username": mcs["username"], "color": mcs["color"]};
                                }
                            }

                            # Notify new member of room join + their cursor color + existing members
                            await ws.send(json.dumps({
                                "type": "room_joined",
                                "roomId": room_id,
                                "sessionId": session_id,
                                "username": username,
                                "cursorColor": cursor_color,
                                "member_count": len(room["members"]),
                                "hostSessionId": room.get("host_session_id", ""),
                                "members": rj_existing_members
                            }));

                            # Broadcast member_joined to all existing members except new one
                            existing_ids: Any = list(room["members"].keys());
                            ei = 0;
                            while ei < len(existing_ids) {
                                eid = existing_ids[ei];
                                if eid != session_id {
                                    try {
                                        ews = room["members"][eid];
                                        await ews.send(json.dumps({
                                            "type": "room_member_joined",
                                            "sessionId": session_id,
                                            "username": username,
                                            "cursorColor": cursor_color
                                        }));
                                    } except Exception { _ = 0; }
                                }
                                ei = ei + 1;
                            }
                        }

                        await ws.send(json.dumps({
                            "type": "registered",
                            "role": "canvas",
                            "sessionId": session_id
                        }));
                        # Notify all controllers that this canvas is ready
                        dead_ctrls: list = [];
                        for ctrl in _controllers {
                            try { await ctrl.send(json.dumps({"type": "canvasConnected", "sessionId": session_id})); }
                            except Exception { dead_ctrls.append(ctrl); }
                        }
                        # Prune dead controllers
                        for ctrl in dead_ctrls {
                            if ctrl in _controllers { _controllers.remove(ctrl); }
                            dead_reqs: list = [rid for (rid, e) in list(_request_map.items()) if e["ctrl"] is ctrl];
                            for rid in dead_reqs { _request_map.pop(rid, None); }
                        }
                    }
                    continue;
                }

                # ── Controller → Canvas ───────────────────────────────────────
                if role == "controller" {
                    rid: str = msg.get("requestId", "");
                    target_sid: str = msg.get("sessionId", "");

                    if not _valid_session_id(target_sid) {
                        if rid {
                            await ws.send(json.dumps({
                                "requestId": rid, "success": False,
                                "error": "Command missing valid sessionId."
                            }));
                        }
                        continue;
                    }

                    if rid { _request_map[rid] = {"ctrl": ws, "session_id": target_sid}; }

                    canvas_ws: Any = _canvases.get(target_sid);
                    if canvas_ws is not None {
                        try { await canvas_ws.send(raw); }
                        except Exception {
                            if rid {
                                _request_map.pop(rid, None);
                                await ws.send(json.dumps({
                                    "requestId": rid, "success": False, "error": "Canvas send failed."
                                }));
                            }
                        }
                    } elif rid {
                        _request_map.pop(rid, None);
                        await ws.send(json.dumps({
                            "requestId": rid, "success": False,
                            "error": f"No canvas for session '{target_sid}'. Open JaSketch in browser."
                        }));
                    }
                }

                # ── Canvas Room Messages (room_broadcast, cursor_move, update_username, end_session) ────
                elif role == "canvas" {
                    msg_type: str = msg.get("type", "");

                    if msg_type == "room_broadcast" {
                        # Element update from room member — broadcast to all room members except sender
                        room_id: str = msg.get("roomId", "");
                        if room_id and room_id in _rooms {
                            room: Any = _rooms[room_id];
                            members: Any = room.get("members", {});
                            sender_sid: str = msg.get("sessionId", "");

                            # Broadcast to all except sender
                            for mid in list(members.keys()) {
                                if mid != sender_sid {
                                    try {
                                        member_ws = members[mid];
                                        await member_ws.send(json.dumps({
                                            "type": "room_update",
                                            "payload": msg.get("payload", "")
                                        }));
                                    } except Exception { _ = 0; }
                                }
                            }
                        }
                        continue;
                    }

                    if msg_type == "join_room" {
                        # Allow already-connected canvas to join/create a room (handles host who connected before starting session)
                        jr_room_id: str = msg.get("roomId", "");
                        jr_username: str = msg.get("username", "Anonymous");
                        if jr_room_id and _valid_room_id(jr_room_id) {
                            if jr_room_id not in _rooms {
                                _rooms[jr_room_id] = {"members": {}, "cursor_states": {}, "host_session_id": session_id};
                                log(f"Room created via join_room: {jr_room_id}");
                            }

                            jr_room: Any = _rooms[jr_room_id];
                            jr_color: str = _assign_cursor_color(jr_room_id, session_id);

                            jr_room["members"][session_id] = ws;
                            jr_room["cursor_states"][session_id] = {
                                "username": jr_username,
                                "color": jr_color,
                                "x": 0.0,
                                "y": 0.0
                            };

                            log(f"Member joined room {jr_room_id} via join_room: {session_id} ({jr_username})");

                            # Build existing members dict for the new joiner (exclude self)
                            jr_existing_members = {};
                            for msid in jr_room.get("cursor_states", {}) {
                                if msid != session_id {
                                    mcs = jr_room.get("cursor_states", {})[msid];
                                    jr_existing_members[msid] = {"username": mcs["username"], "color": mcs["color"]};
                                }
                            }

                            await ws.send(json.dumps({
                                "type": "room_joined",
                                "roomId": jr_room_id,
                                "sessionId": session_id,
                                "username": jr_username,
                                "cursorColor": jr_color,
                                "member_count": len(jr_room["members"]),
                                "hostSessionId": jr_room.get("host_session_id", ""),
                                "members": jr_existing_members
                            }));

                            jr_existing_ids: Any = list(jr_room["members"].keys());
                            jrei: int = 0;
                            while jrei < len(jr_existing_ids) {
                                jr_eid: str = jr_existing_ids[jrei];
                                if jr_eid != session_id {
                                    try {
                                        jr_ews: Any = jr_room["members"][jr_eid];
                                        await jr_ews.send(json.dumps({
                                            "type": "room_member_joined",
                                            "sessionId": session_id,
                                            "username": jr_username,
                                            "cursorColor": jr_color
                                        }));
                                    } except Exception { _ = 0; }
                                }
                                jrei = jrei + 1;
                            }
                        }
                        continue;
                    }

                    if msg_type == "cursor_move" {
                        # Update cursor position and broadcast to room members
                        room_id: str = msg.get("roomId", "");
                        if room_id and room_id in _rooms {
                            room: Any = _rooms[room_id];
                            cursor_states: Any = room.get("cursor_states", {});
                            sender_sid: str = msg.get("sessionId", "");

                            if sender_sid in cursor_states {
                                cs: Any = cursor_states[sender_sid];
                                cs["x"] = msg.get("x", 0.0);
                                cs["y"] = msg.get("y", 0.0);

                                # Broadcast cursor position to all room members except sender
                                members: Any = room.get("members", {});
                                for mid in list(members.keys()) {
                                    if mid != sender_sid {
                                        try {
                                            member_ws = members[mid];
                                            await member_ws.send(json.dumps({
                                                "type": "cursor_update",
                                                "sessionId": sender_sid,
                                                "username": cs["username"],
                                                "cursorColor": cs["color"],
                                                "x": cs["x"],
                                                "y": cs["y"]
                                            }));
                                        } except Exception { _ = 0; }
                                    }
                                }
                            }
                        }
                        continue;
                    }

                    if msg_type == "update_username" {
                        # Update member's username in cursor state
                        room_id: str = msg.get("roomId", "");
                        new_username: str = msg.get("username", "Anonymous");
                        if room_id and room_id in _rooms {
                            room: Any = _rooms[room_id];
                            cursor_states: Any = room.get("cursor_states", {});
                            sender_sid: str = msg.get("sessionId", "");

                            if sender_sid in cursor_states {
                                cs: Any = cursor_states[sender_sid];
                                cs["username"] = new_username;

                                # Broadcast username change to all room members except the sender
                                members: Any = room.get("members", {});
                                for mid in list(members.keys()) {
                                    if mid != sender_sid {
                                        try {
                                            member_ws = members[mid];
                                            await member_ws.send(json.dumps({
                                                "type": "cursor_update",
                                                "sessionId": sender_sid,
                                                "username": new_username,
                                                "cursorColor": cs["color"],
                                                "x": cs["x"],
                                                "y": cs["y"]
                                            }));
                                        } except Exception { _ = 0; }
                                    }
                                }
                            }
                        }
                        continue;
                    }

                    if msg_type == "end_session" {
                        # Host ends the session — cleanup room and notify members
                        room_id: str = msg.get("roomId", "");
                        if room_id {
                            await _cleanup_room(room_id);
                        }
                        continue;
                    }
                }

                # ── Canvas → Controller (response keyed by requestId) ─────────
                if role == "canvas" {
                    rid: str = msg.get("requestId", "");
                    if rid {
                        entry: Any = _request_map.pop(rid, None);
                        if entry is not None {
                            ctrl_ws: Any = entry["ctrl"];
                            try { await ctrl_ws.send(raw); }
                            except Exception { _ = 0; }
                        }
                    }
                }
            } except Exception {
                log("Bad message");
            }
        }
    } except Exception {
        _ = 0;
    }

    # ── Cleanup on disconnect ─────────────────────────────────────────────────
    if role == "canvas" and session_id and _canvases.get(session_id) is ws {
        _canvases.pop(session_id, None);
        log(f"Canvas disconnected: session={session_id}");

        # ── Room cleanup for this canvas ──────────────────────────────────────
        room_ids_to_clean: Any = [];
        for rid in list(_rooms.keys()) {
            room: Any = _rooms[rid];
            members: Any = room.get("members", {});
            if session_id in members {
                # Remove member from room
                members.pop(session_id, None);
                cursor_states: Any = room.get("cursor_states", {});
                cursor_states.pop(session_id, None);

                log(f"Room {rid}: member {session_id} removed ({len(members)} remaining)");

                # Broadcast member_left to remaining members
                for mid in list(members.keys()) {
                    try {
                        member_ws = members[mid];
                        await member_ws.send(json.dumps({
                            "type": "room_member_left",
                            "sessionId": session_id
                        }));
                    } except Exception { _ = 0; }
                }

                # If room is empty, mark for cleanup
                if len(members) == 0 {
                    room_ids_to_clean.append(rid);
                }
            }
        }

        # Clean up empty rooms
        for rid in room_ids_to_clean {
            _rooms.pop(rid, None);
            log(f"Room {rid} deleted (no members remaining)");
        }

        # Actively fail all pending requests targeting this session
        dead: Any = [];
        items: Any = list(_request_map.items());
        for (rid_key, entry_val) in items {
            ev: Any = entry_val;
            if ev["session_id"] == session_id { dead.append(rid_key); }
        }
        for dead_rid in dead {
            dead_entry: Any = _request_map.pop(dead_rid, None);
            if dead_entry is not None {
                ctrl_ws: Any = dead_entry["ctrl"];
                try {
                    await ctrl_ws.send(json.dumps({
                        "requestId": dead_rid, "success": False,
                        "error": "Canvas disconnected."
                    }));
                } except Exception { _ = 0; }
            }
        }

        # Notify all controllers, prune dead ones
        dead_ctrls: list = [];
        for ctrl in _controllers {
            try { await ctrl.send(json.dumps({"type": "canvasDisconnected", "sessionId": session_id})); }
            except Exception { dead_ctrls.append(ctrl); }
        }
        for ctrl in dead_ctrls {
            if ctrl in _controllers { _controllers.remove(ctrl); }
            dead_reqs: list = [rid for (rid, e) in list(_request_map.items()) if e["ctrl"] is ctrl];
            for rid in dead_reqs { _request_map.pop(rid, None); }
        }

    } elif role == "controller" {
        if ws in _controllers { _controllers.remove(ws); }
        log(f"Controller disconnected ({len(_controllers)} remaining)");

        # Release pending requests from this controller (no error response needed — controller is gone)
        dead: Any = [];
        items: Any = list(_request_map.items());
        for (rid_key, entry_val) in items {
            ev: Any = entry_val;
            if ev["ctrl"] is ws { dead.append(rid_key); }
        }
        for dead_rid in dead { _request_map.pop(dead_rid, None); }
    }
}


"""Start relay in a background daemon thread. Blocks until the port is listening."""
def start_relay_server() -> None {
    ready: Any = threading.Event();

    def _thread() -> None {
        loop: Any = asyncio.new_event_loop();
        asyncio.set_event_loop(loop);
        async def _start() {
            _srv: Any = await websockets.serve(handler, "0.0.0.0", PORT);
            log(f"WebSocket relay running on port {PORT}");
            ready.set();
            await asyncio.Future();
        }
        loop.run_until_complete(_start());
    }

    threading.Thread(target=_thread, daemon=True).start();
    if not ready.wait(timeout=5) { raise Exception(f"Relay server failed to start on port {PORT} within 5 seconds."); }
}


