# JaSketch

A sketching and diagramming app built with [Jaclang](https://docs.jaseci.org/) and Canvas 2D.

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

## Getting Started

```bash
python -m venv .venv
source .venv/bin/activate
pip install jaclang jac-client jac-scale
jac start
```

## Project Structure

```
jasketch/
├── main.jac                  # App entry point
├── styles.css                # Global styles (Tailwind)
├── components/
│   ├── Canvas.cl.jac         # Main canvas with drawing logic
│   ├── canvas/
│   │   ├── CanvasRenderer    # Canvas rendering layer
│   │   ├── ContextMenu       # Right-click context menu
│   │   └── TextInput         # Inline text editing
│   └── layout/
│       ├── TopBar            # Toolbar with tool selection
│       └── Sidebar           # Properties panel
├── hooks/                    # React hooks for state management
├── services/                 # Canvas rendering, collision, export, geometry
├── constants/                # Colors, fonts, tools, canvas defaults
└── assets/                   # Icon files
```

## MCP Server (AI Integration)

JaSketch includes an MCP (Model Context Protocol) server that lets AI assistants like Claude create and manipulate diagrams programmatically.

### Setup with Claude Code

```bash
claude mcp add --scope user jasketch -- npx -y jasketch-mcp-server
```

Or manually add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "jasketch": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "jasketch-mcp-server"]
    }
  }
}
```

### Setup with Claude Desktop

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS):

```json
{
  "mcpServers": {
    "jasketch": {
      "command": "npx",
      "args": ["-y", "jasketch-mcp-server"]
    }
  }
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JASKETCH_RELAY_URL` | `ws://localhost:9601` | WebSocket relay URL connecting the MCP server to the canvas |

### Available Tools

| Tool | Description |
|------|-------------|
| `create_element` | Create a single element (rectangle, circle, diamond, line, arrow, text, freehand) |
| `create_elements` | Batch create multiple elements efficiently |
| `query_elements` | Query elements on canvas, optionally filter by type or index |
| `update_element` | Update properties of an existing element by index |
| `delete_element` | Delete element(s) by index |
| `clear_canvas` | Clear all elements from the canvas |

### Usage

Make sure JaSketch is running (`jac start`) so the canvas is connected to the relay, then ask Claude to draw diagrams — e.g., "draw a flowchart showing user authentication".

## Tech

- **Jaclang** (.cl.jac) compiled to JavaScript
- **Canvas 2D** with viewport transformations
- **Tailwind CSS v4** for styling
- **Virgil** handwriting font (default)
