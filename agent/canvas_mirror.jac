"""A server-side stand-in for the browser's canvas, for the duration of one turn.

The agent used to hold a second WebSocket open back to the browser and make a
network round trip for every tool call -- get the elements, add one, get them
again. That reverse channel is why the app needed a relay process on its own
port, and why an agent could only work on a canvas that happened to be online.

Instead the browser ships its element list with the chat message, the agent's
tools mutate this copy, and the finished list is streamed back for the browser
to apply. `CanvasToolProvider` is unchanged: it still speaks the same eleven
actions through its injected `send_fn` -- that function just resolves them here
now instead of over a socket.
"""

import uuid;
import from typing { Any }


obj CanvasMirror {
    """One turn's working copy of a canvas."""

    has elements: list[dict] = [],
        viewport: dict = {},
        touched: bool = False;

    # ── send_fn ───────────────────────────────────────────────────────────────

    """Resolve one relay action. Bind as a CanvasToolProvider send_fn."""
    def handle(action: str, data: dict | None = None) -> Any {
        payload: dict = data if data is not None else {};
        handlers: dict = {
            "getElements":            self._get_elements,
            "addElement":             self._add_element,
            "addMultipleElements":    self._add_multiple,
            "setElements":            self._set_elements,
            "updateElement":          self._update_element,
            "removeElement":          self._remove_element,
            "removeMultipleElements": self._remove_multiple,
            "clearElements":          self._clear,
            "getViewport":            self._get_viewport,
            "getBoundingBox":         self._get_bounding_box,
            # The browser produced this by reading pixels off its <canvas>. There
            # are no pixels here, so say so rather than returning a fake.
            "getCanvasSnapshot":      self._no_snapshot,
        };
        fn: Any = handlers.get(action);
        if fn is None {
            raise Exception(f"Unknown canvas action: {action}");
        }
        return fn(payload);
    }

    # ── Reads ─────────────────────────────────────────────────────────────────

    def _get_elements(data: dict) -> dict {
        wanted: Any = data.get("type");
        matched: list = [
            {"id": el.get("id", ""), "element": el}
            for el in self.elements
            if not wanted or el.get("type") == wanted
        ];
        return {"elements": matched, "total": len(self.elements)};
    }

    def _get_viewport(data: dict) -> dict {
        return dict(self.viewport) if self.viewport else {
            "zoom": 1.0,
            "panOffset": {"x": 0, "y": 0},
            "canvasWidth": 1200,
            "canvasHeight": 800,
            "visibleArea": {"x": 0, "y": 0, "width": 1200, "height": 800}
        };
    }

    def _no_snapshot(data: dict) -> dict {
        raise Exception("Canvas snapshots are only available from a live browser canvas");
    }

    """Axis-aligned box around every element, mirroring the browser's own maths."""
    def _get_bounding_box(data: dict) -> dict {
        if not self.elements {
            return {"boundingBox": None, "elementCount": 0};
        }
        xs: list[float] = [];
        ys: list[float] = [];
        for el in self.elements {
            kind: str = el.get("type", "");
            if kind in ("line", "arrow") {
                xs += [float(el.get("x1", 0)), float(el.get("x2", 0))];
                ys += [float(el.get("y1", 0)), float(el.get("y2", 0))];
            } elif kind == "freehand" {
                for pt in (el.get("points") or []) {
                    point: dict = pt;
                    xs.append(float(point.get("x", 0)));
                    ys.append(float(point.get("y", 0)));
                }
            } elif kind == "text" {
                x: float = float(el.get("x", 0));
                y: float = float(el.get("y", 0));
                size: float = float(el.get("fontSize", 16));
                xs += [x, x + size * len(str(el.get("text", ""))) * 0.6];
                ys += [y, y + size * 1.2];
            } else {
                x: float = float(el.get("x", 0));
                y: float = float(el.get("y", 0));
                xs += [x, x + float(el.get("width", 0))];
                ys += [y, y + float(el.get("height", 0))];
            }
        }
        if not xs or not ys {
            return {"boundingBox": None, "elementCount": len(self.elements)};
        }
        return {
            "boundingBox": {
                "x": min(xs), "y": min(ys),
                "width": max(xs) - min(xs),
                "height": max(ys) - min(ys)
            },
            "elementCount": len(self.elements)
        };
    }

    # ── Writes ────────────────────────────────────────────────────────────────

    """Give an element the id the browser would have minted for it."""
    def _ensure_id(el: dict) -> dict {
        if not el.get("id") {
            el["id"] = str(uuid.uuid4());
        }
        return el;
    }

    def _add_element(data: dict) -> dict {
        el: dict = self._ensure_id(dict(data));
        self.elements.append(el);
        self.touched = True;
        return {"id": el["id"], "action": "created"};
    }

    def _add_multiple(data: dict) -> dict {
        added: list[str] = [];
        for raw in (data.get("elements") or []) {
            el: dict = self._ensure_id(dict(raw));
            self.elements.append(el);
            added.append(el["id"]);
        }
        self.touched = True;
        return {"ids": added, "count": len(added), "action": "created"};
    }

    def _set_elements(data: dict) -> dict {
        self.elements = [self._ensure_id(dict(el)) for el in (data.get("elements") or [])];
        self.touched = True;
        return {"action": "replaced", "count": len(self.elements)};
    }

    def _update_element(data: dict) -> dict {
        target: str = str(data.get("id", ""));
        changes: dict = data.get("changes") or {};
        for (idx, el) in enumerate(self.elements) {
            if el.get("id") == target {
                self.elements[idx] = {**el, **changes};
                self.touched = True;
                return {"id": target, "action": "updated"};
            }
        }
        raise Exception(f"Element not found: {target}");
    }

    def _remove_element(data: dict) -> dict {
        target: str = str(data.get("id", ""));
        self.elements = [el for el in self.elements if el.get("id") != target];
        self.touched = True;
        return {"id": target, "action": "deleted"};
    }

    def _remove_multiple(data: dict) -> dict {
        targets: set = set(data.get("ids") or []);
        self.elements = [el for el in self.elements if el.get("id") not in targets];
        self.touched = True;
        return {"ids": list(targets), "action": "deleted"};
    }

    def _clear(data: dict) -> dict {
        self.elements = [];
        self.touched = True;
        return {"action": "cleared"};
    }
}
