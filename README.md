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

Let Claude -- or any MCP client -- draw on a canvas you have open. **Nothing to
install.**

```bash
claude mcp add --transport http jasketch https://jasketch.jaseci.org/mcp
```

Then open JaSketch, click the share button, and pick the **AI Assistant** tab: it
shows that exact command and this tab's session id, both with copy buttons. Paste
the session id when the assistant asks which canvas to draw on -- one hosted
server serves everyone, so every tool call names its target tab.

It is an endpoint of the app itself (`infrastructure/mcp_http.jac`), not a
separate deployment. `@restspec(envelope=False)` is what makes that work: MCP
clients need bare JSON-RPC, and every other endpoint here wraps its result in
`{ok, data, ...}`.

### Running it locally instead

`mcp_server/` still builds the stdio server, published to PyPI from its own
`jac.toml`. `jac build --as wheel` transpiles the Jac to Python and vendors the
runtime it touches, so the wheel needs no jac toolchain:

```bash
claude mcp add --scope user jasketch \
  --env JASKETCH_SESSION_ID=<the tab's id> \
  -- uvx jasketch-mcp-server@latest
```

Behind the microservice gateway it also needs the service prefix on the relay
URL, because the gateway does not route `/ws` at the root (jaseci-labs/jac#8772):

```
JASKETCH_RELAY_URL=wss://<host>/jasketch/ws/function/jasketch_relay
```

### Available Tools

| Tool | Description |
|------|-------------|
| `create_element` | Create a single element (rectangle, circle, diamond, line, arrow, text, freehand) |
| `create_elements` | Batch create multiple elements efficiently |
| `draw_labeled_shape` | Auto-sized shape with a centered label |
| `draw_connector` | Smart arrow/line between two shapes |
| `add_title` | Place a title on the canvas |
| `query_elements` | Query elements, optionally filtered by type or index |
| `update_element` | Update properties of an existing element |
| `delete_element` | Delete element(s) by index |
| `clear_canvas` | Clear all elements |
| `render_elements` | Replace the canvas with a full element array |
| `get_viewport` | Zoom level, pan offset, visible area |
| `get_bounding_box` | Bounding box of all elements |
| `get_canvas_elements` | All elements, defaults stripped |
| `get_drawing_guide` | Element schemas, layout rules and colour palette |
| `get_canvas_snapshot` | PNG screenshot of the canvas as base64 |

Every tool takes a `session_id` naming the canvas to act on.

## Tech

- **Jac** - one language and one binary for the client, the server, and the agent
- **Canvas 2D** with viewport transformations
- **Tailwind CSS v4** for styling
- **Virgil** handwriting font (default)
