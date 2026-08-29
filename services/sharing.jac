"""Server half of scene sharing: an encrypted-blob store behind two endpoints.

The server never sees a scene. The browser generates an AES-GCM key, encrypts
the element array, and keeps the key in the URL fragment -- which browsers do
not send to the server -- so what lands here is ciphertext and nothing else
(client half: services/scene_sharing.cl.jac).

Scenes live on `root.shared`, the deployment's public commons graph, because a
share link has to resolve for anyone who opens it, not just its author. That
also means the feature needs no MongoDB: it works on the default SQLite backend
and on Mongo/Redis in production, whatever [scale.database] says.
"""

import secrets;
import from datetime { datetime, timedelta, timezone }

# A share link is a throwaway. Seven days matches the TTL the previous
# Mongo-backed store set with expireAfterSeconds.
glob SHARE_TTL_DAYS: int = 7;

# 5 MiB of scene, base64 -> ~4/3 the characters. Rejecting oversized blobs at
# the endpoint keeps one tab from filling the shared graph.
glob MAX_CIPHERTEXT_CHARS: int = (5 * 1024 * 1024 * 4) // 3;


node SharedScene {
    has share_id: str;
    has ciphertext: str;
    has created_at: str;
}


obj ShareRef {
    has share_id: str = "";
    has error: str = "";
}
sem ShareRef = "Result of storing a scene: the id half of the share link, or why it failed";
sem ShareRef.share_id = "Opaque id to put in the #json=<id>,<key> fragment; empty when error is set";
sem ShareRef.error = "Human-readable failure reason; empty on success";


obj SharePayload {
    has ciphertext: str = "";
    has error: str = "";
}
sem SharePayload = "A stored scene, still encrypted -- the caller decrypts with the key from the URL fragment";
sem SharePayload.ciphertext = "base64url(iv || AES-GCM ciphertext); empty when error is set";
sem SharePayload.error = "Human-readable failure reason; empty on success";


"""Drop scenes past their TTL. Cheap enough to run on every write."""
def _prune_expired() -> None {
    cutoff: datetime = datetime.now(timezone.utc) - timedelta(days=SHARE_TTL_DAYS);
    for scene in [root.shared --> [?:SharedScene]] {
        try {
            if datetime.fromisoformat(scene.created_at) < cutoff {
                del scene;
            }
        } except ValueError {
            # A created_at we cannot parse is from an older schema; treat it as
            # expired rather than letting it pin the row forever.
            del scene;
        }
    }
}


"""Store an encrypted scene snapshot and return its share id."""
def:pub create_share(ciphertext: str) -> ShareRef {
    if not ciphertext {
        return ShareRef(error="Missing ciphertext");
    }
    if len(ciphertext) > MAX_CIPHERTEXT_CHARS {
        return ShareRef(error=f"Scene exceeds the {MAX_CIPHERTEXT_CHARS} character limit");
    }
    _prune_expired();
    share_id: str = secrets.token_urlsafe(16)[:22];
    root.shared ++> SharedScene(
        share_id=share_id,
        ciphertext=ciphertext,
        created_at=datetime.now(timezone.utc).isoformat()
    );
    return ShareRef(share_id=share_id);
}


"""Fetch a stored scene by share id. Still encrypted -- the key never came here."""
def:pub read_share(share_id: str) -> SharePayload {
    if not share_id {
        return SharePayload(error="Missing share id");
    }
    # Alias the parameter: inside the filter, `share_id` is the NODE's field,
    # so comparing it to a parameter of the same name compares it to itself.
    wanted: str = share_id;
    found: list[SharedScene] = [root.shared --> [?:SharedScene, share_id == wanted]];
    if not found {
        return SharePayload(error="Share not found or expired");
    }
    return SharePayload(ciphertext=found[0].ciphertext);
}
