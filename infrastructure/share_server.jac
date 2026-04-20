"""JaSketch Share Server — HTTP API for encrypted scene sharing.

Provides endpoints for storing and retrieving encrypted scene snapshots:
  POST /api/share          → store encrypted blob, return share_id
  GET /api/share/{share_id} → retrieve encrypted blob

Storage: MongoDB collection `jasketch_db.shared_scenes` with 7-day TTL.
Encryption: Client-side only (Web Crypto API); server stores ciphertext only.
"""

import from typing { Any }

import logging;
import os;
import re;
import secrets;
import from typing { Any }
import from datetime { datetime, timezone }
import from jac_scale.db { get_mongo_client }

glob SHARE_DB_NAME: str = "jasketch_db";
glob SHARE_COLLECTION: str = "shared_scenes";
glob MAX_BLOB_BYTES: int = 5 * 1024 * 1024;
glob SHARE_TTL_SECONDS: int = 604800;
glob SHARE_ID_PATTERN: str = r'^[a-zA-Z0-9_\-]{1,32}$';

glob _log: Any = logging.getLogger("jasketch.share_server");


def _validate_share_id(share_id: str) -> bool {
    if not share_id or len(share_id) > 32 {
        return False;
    }
    return bool(re.match(SHARE_ID_PATTERN, share_id));
}


def _generate_share_id() -> str {
    return secrets.token_urlsafe(16)[:22];
}


def _get_share_db() -> Any {
    return get_mongo_client()[SHARE_DB_NAME];
}


def _setup_db_indexes() -> bool {
    try {
        db = _get_share_db();
        col = db[SHARE_COLLECTION];
        col.create_index("share_id", unique=True);
        col.create_index("created_at", expireAfterSeconds=SHARE_TTL_SECONDS);
        _log.info(f"Share DB indexes created: {SHARE_DB_NAME}.{SHARE_COLLECTION}");
        return True;
    } except Exception as e {
        _log.error(f"Failed to setup share DB indexes: {e}");
        return False;
    }
}


def _make_share_routes() -> dict {
    import from fastapi { Request }
    import from starlette.responses { JSONResponse }

    async def post_share(request: Request) -> Any {
        try {
            body = await request.json();
        } except Exception as e {
            _log.warning(f"Invalid JSON in share request: {e}");
            return JSONResponse({"error": "Invalid JSON"}, status_code=400);
        }

        ciphertext = body.get("ciphertext", "");
        if not ciphertext {
            return JSONResponse({"error": "Missing ciphertext field"}, status_code=400);
        }

        if len(ciphertext) > (MAX_BLOB_BYTES * 4 / 3) {
            return JSONResponse({"error": f"Blob exceeds {MAX_BLOB_BYTES} bytes"}, status_code=413);
        }

        share_id = _generate_share_id();

        try {
            col = _get_share_db()[SHARE_COLLECTION];
            col.insert_one({
                "share_id": share_id,
                "ciphertext": ciphertext,
                "created_at": datetime.now(timezone.utc)
            });
            return JSONResponse({"share_id": share_id}, status_code=201);
        } except Exception as e {
            _log.error(f"Failed to store share: {e}");
            return JSONResponse({"error": "Database error"}, status_code=500);
        }
    }

    async def get_share(request: Request) -> Any {
        share_id = request.path_params.get("share_id", "");

        if not _validate_share_id(share_id) {
            return JSONResponse({"error": "Invalid share_id"}, status_code=400);
        }

        try {
            col = _get_share_db()[SHARE_COLLECTION];
            doc = col.find_one({"share_id": share_id});

            if doc is None {
                return JSONResponse({"error": "Share not found or expired"}, status_code=404);
            }

            return JSONResponse({"ciphertext": doc["ciphertext"]}, status_code=200);
        } except Exception as e {
            _log.error(f"Failed to retrieve share: {e}");
            return JSONResponse({"error": "Database error"}, status_code=500);
        }
    }

    return {"post": post_share, "get": get_share};
}


def _register_share_routes() -> bool {
    try {
        import from jac_scale.jserver.jfast_api { JFastApiServer }

        routes = _make_share_routes();
        orig_run_server = JFastApiServer.run_server;

        def patched_run_server(self: Any, host: str = "0.0.0.0", port: int = 8000, max_retries: int = 10) -> None {
            import from starlette.routing { Route }
            app: Any = self.create_server();
            share_routes: list[Any] = [
                Route("/api/share", routes["post"], methods=["POST"]),
                Route("/api/share/{share_id}", routes["get"], methods=["GET"]),
            ];
            app.router.routes[0:0] = share_routes;
            _log.info("Share API routes registered at /api/share");
            orig_run_server(self, host, port, max_retries);
        }

        JFastApiServer.run_server = patched_run_server;
        return True;
    } except Exception as e {
        _log.error(f"Failed to register share routes: {e}");
        return False;
    }
}


def initialize_share_server() -> bool {
    try {
        _log.info("Initializing JaSketch share server...");
        if not _setup_db_indexes() {
            _log.warning("DB index setup failed, continuing anyway");
        }
        if not _register_share_routes() {
            _log.warning("Route registration failed, continuing anyway");
        }
        _log.info("Share server initialized successfully");
        return True;
    } except Exception as e {
        _log.error(f"Share server init failed: {e}");
        return False;
    }
}

glob _share_server_ready: bool = initialize_share_server();
