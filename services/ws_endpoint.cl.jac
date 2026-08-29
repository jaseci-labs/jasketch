"""Where the WebSocket endpoints live, which is not the same in every topology.

A single-process `jac start` serves them at `/ws/function/<name>`. A `--scale`
deploy puts a microservice gateway in front, and that gateway learns its routes
from each service's OpenAPI spec -- which deliberately EXCLUDES WebSocket
targets. So `/ws/...` never matches a service and the gateway answers every
upgrade with close code 1008, while the same socket is reachable under the
service's own prefix at `/<service>/ws/...`.

(HTTP is not affected: `/function/<name>` IS in the OpenAPI spec, so the RPC
stubs are learned at the root and work either way. Only sockets are asymmetric.)

Rather than pin one shape, ask: try the root, and if the gateway rejects the
upgrade with 1008, fall back to the prefix and remember it for the rest of the
session. Correct in both topologies with nothing to configure, and it self-heals
if the upstream gap is closed.
"""

# Set once the first successful shape is known, so later sockets skip the probe.
glob _ws_prefix: str | None = None;

# The gateway mounts each service under its [project] name.
glob _SERVICE_PREFIX: str = "/jasketch";

# Close code the gateway sends when no service claims the path.
glob WS_NO_ROUTE: int = 1008;


"""Origin as a ws:// or wss:// base."""
def:pub ws_origin() -> str {
    scheme = "wss:" if window.location.protocol == "https:" else "ws:";
    return scheme + "//" + window.location.host;
}


"""URL for `target` (e.g. "function/jasketch_chat"), using whatever shape works."""
def:pub ws_url(target: str) -> str {
    prefix = _ws_prefix if _ws_prefix is not None else "";
    return ws_origin() + prefix + "/ws/" + target;
}


"""True if this close means "try the other shape". Flips the cached prefix."""
def:pub ws_should_retry_under_prefix(close_code: int) -> bool {
    if close_code != WS_NO_ROUTE {
        return False;
    }
    if _ws_prefix is not None and _ws_prefix != "" {
        return False;      # already prefixed and still rejected; a real failure
    }
    _ws_prefix = _SERVICE_PREFIX;
    console.log("[JaSketch] gateway rejected /ws at the root; using " + _SERVICE_PREFIX);
    return True;
}
