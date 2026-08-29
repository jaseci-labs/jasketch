# JaSketch

A collaborative whiteboard built in [Jac](https://docs.jaseci.org/) - canvas, AI drawing
agent, share links and live rooms, all in one `.jac` project.

![JaSketch](assets/jasketch.png)

## Features

- Freehand drawing, lines, arrows, rectangles, diamonds, ellipses, and text
- Image import (file picker + clipboard paste)
- Click-to-place lines/arrows with draggable bend points for curves
- Select, move, resize, group/ungroup elements
- Copy/paste, duplicate, undo/redo
- Export as PNG, SVG, or PDF
- Zoom and pan with scroll
- localStorage persistence
- **Share links** - the scene is encrypted in your browser; the server stores ciphertext
- **Live rooms** - several people on one canvas, end-to-end encrypted
- **AI agent** - describe a diagram in chat and it draws it

## Getting Started

Everything ships in the `jac` binary: there is no virtualenv to make and no
`jaclang` / `jac-client` / `jac-scale` / `byllm` to pip install.

```bash
# 1. Get the toolchain this project is pinned to (see [project] jac-version).
#    The installer drops a self-contained binary in ~/.local/bin; it bundles its
#    own runtime, so there is no system Python or pip involved.
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh \
  | bash -s -- --version 0.34.14

# 2. Resolve dependencies (PyPI + npm) into .jac/
jac install

# 3. Run it
jac start
```

Then open http://localhost:8000. The first start builds the client bundle, which
takes a minute; after that it is seconds.

`jac start --dev` adds hot module reload for client code. Server modules and
`glob`s evaluate once at boot, so those still need a restart.

## Project Structure

```
jasketch/
├── main.jac                  # Entry point: endpoint registration + the app shell
├── styles.css                # Global styles (Tailwind)
├── agent/                    # The AI drawing agent
│   ├── chat.jac              #   streaming WebSocket endpoint (the only chat transport)
│   ├── orchestrator.jac      #   walker that routes between the subagents
│   ├── canvas_mirror.jac     #   server-side stand-in for the browser canvas
│   ├── canvas_tools.jac      #   the tool surface the agent draws through
│   └── subagents/            #   router, planner, analyst, composer, editor
├── infrastructure/
│   └── relay.jac             # Live-room fan-out (broadcast WebSocket endpoint)
├── services/
│   ├── sharing.jac           # Share endpoints + the SharedScene store (server)
│   ├── scene_sharing.cl.jac  # Web Crypto + the RPC calls (client)
│   └── canvas / collision / export / geometry
├── components/               # Canvas, toolbar, sidebar, dialogs
├── hooks/                    # Reactive state: elements, selection, viewport, sockets
├── constants/                # Colors, fonts, tools, canvas defaults
├── mcp_server/               # MCP server: drive a live canvas from an AI assistant
│   ├── jac.toml              #   its own manifest; published to PyPI as jasketch-mcp-server
│   └── jasketch_mcp_server/  #   package dir (name must match project.name)
└── tests/e2e/                # Playwright suite (the functional gate)
```

## Architecture notes

**Everything is on one port.** The app used to run three servers - the web app on
8000, a WebSocket relay on 9601, and a chat socket on 9602 - which needed a
Dockerfile and hand-written ingress to deploy. All three are now endpoints of the
one Jac server, so `jac start --scale` deploys the whole thing with no image
build and no registry.

**The agent works on a copy of your canvas.** Rather than reaching back into the
browser for every tool call, the browser sends its elements with the message; the
agent draws on a server-side mirror and the finished scene streams back for the
browser to apply.

**The server never sees your drawings.** Share links and live rooms both encrypt
client-side (AES-GCM, Web Crypto). The key lives in the URL fragment, which
browsers do not send to the server.

## Testing

```bash
jac -m playwright install chromium     # once
jac -m pytest tests/e2e/ -v
```

The suite starts its own server with the binary this project pins - set `JAC_BIN`
to override. A `jac` on `PATH` is often a dev build tracking `main`, and a green
run against a different compiler than the deploy uses proves nothing.

## Deployment

```bash
jac start --scale --dry-run     # lint the plan: HPA bounds, resource units, secrets
jac start --scale               # deploy
jac scale status main.jac       # component health
```

Multi-replica deployments need `MONGODB_URI` (SQLite does not survive more than
one replica) and `[scale.websocket] backplane = "redis"` - without the Redis
backplane a room broadcast only reaches clients that share a worker with the
sender.

**How jac gets into the pods.** You do not install it there, and there is no
image to build. `[project] jac-version` is resolved against published
`jaseci-labs/jaseci` releases, that exact binary is downloaded by whoever runs
the deploy, and it is shipped to the cluster on the bundle PVC alongside your
source. Pods boot a stock base image and run it from there. A pin that matches no
published release aborts the deploy rather than quietly falling back to latest, so
the version CI tested on is the version production runs. The only machine that
needs `jac` installed is the one running `jac start --scale`.

## MCP Server (AI Integration)

`mcp_server/` lets an assistant like Claude draw on a canvas you have open. It is
published to PyPI from its own `jac.toml`, so installing it needs no jac
toolchain: `jac build --as wheel` transpiles the Jac to Python and vendors the
runtime modules it touches.

```bash
claude mcp add --scope user jasketch -- uvx jasketch-mcp-server@latest
```

### Usage

1. Open JaSketch in a browser ([jasketch.jaseci.org](https://jasketch.jaseci.org/))
2. Copy that tab's session id - `sessionStorage.getItem('jasketch_session_id')` in
   the devtools console - and set `JASKETCH_SESSION_ID` for the bridge. The relay
   is a broadcast endpoint with no connection registry, so the target tab has to
   be named.
3. Ask Claude to draw - e.g. "draw a flowchart showing user authentication"

### Available Tools

| Tool | Description |
|------|-------------|
| `create_element` | Create a single element (rectangle, circle, diamond, line, arrow, text, freehand) |
| `create_elements` | Batch create multiple elements efficiently |
| `query_elements` | Query elements on canvas, optionally filter by type or index |
| `update_element` | Update properties of an existing element by index |
| `delete_element` | Delete element(s) by index |
| `clear_canvas` | Clear all elements from the canvas |
| `get_viewport` | Get zoom level, pan offset, and visible canvas area |
| `get_bounding_box` | Get bounding box of all elements (useful for layout planning) |
| `get_canvas_snapshot` | Get a PNG screenshot of the canvas as base64 |

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `JASKETCH_RELAY_URL` | `wss://jasketch.jaseci.org/ws/function/jasketch_relay` | The app's relay endpoint |
| `JASKETCH_SESSION_ID` | - | Which browser tab to draw on (required) |
| `JASKETCH_MCP_TRANSPORT` | `stdio` | Transport mode: `stdio` or `streamable-http` |
| `JASKETCH_MCP_PORT` | `3003` | HTTP port (only used when transport is `streamable-http`) |
| `JASKETCH_MCP_HOST` | `0.0.0.0` | HTTP bind address (only used when transport is `streamable-http`) |

## Tech

- **Jac** - one language and one binary for the client, the server, and the agent
- **Canvas 2D** with viewport transformations
- **Tailwind CSS v4** for styling
- **Virgil** handwriting font (default)
