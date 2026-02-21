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

## Tech

- **Jaclang** (.cl.jac) compiled to JavaScript
- **Canvas 2D** with viewport transformations
- **Tailwind CSS v4** for styling
- **Virgil** handwriting font (default)
