# Model Builder

An interaction layer for building 3D models with an AI agent. It runs inside the modeler you already use: **SketchUp** first, then **Rhino + Grasshopper**.

## The problem

Current models can already build detailed geometry from an image. What's hard is **pointing**: telling the agent *which* element, *where* exactly, and *how big*. Today that takes screenshots, markup, careful wording, and pasting into a chat box. A screenshot also throws away what the modeler already knows: the camera, entity IDs, coordinates, units and the selection.

## The idea

You work in the modeler. You rotate to a view, drop pins on the geometry, draw markup, select a scope, and attach a sketch, CAD detail or rendering registered to the model. The plugin packs all of this into a structured **context packet** and sends it to the agent. The agent replies with **proposals** (ghost geometry) that you accept or reject.

```
SketchUp extension (Ruby) ─┐
                           ├─ localhost socket ─ Bridge / MCP server (Python) ─ Claude
Rhino plugin (Python) ─────┘
```

## Repository layout

| Path | Contents |
|---|---|
| `docs/` | Vision, architecture, protocol, ops, roadmap, dev setup, decision records |
| `protocol/schemas/` | JSON Schemas, which are the source of truth for the packet format |
| `protocol/examples/` | Example packets used in docs and tests |
| `bridge/` | Python MCP server that owns protocol, ops and proposal state |
| `hosts/sketchup/` | SketchUp extension (Ruby) |
| `hosts/rhino/` | Rhino plugin and Grasshopper components (later) |
| `samples/` | Small test models and reference images |

## Start here

1. [docs/vision.md](docs/vision.md): what we are building and why
2. [docs/architecture.md](docs/architecture.md): components and data flow
3. [docs/protocol.md](docs/protocol.md): context packet and host↔bridge messages
4. [docs/ops.md](docs/ops.md): operations the agent can call
5. [docs/roadmap.md](docs/roadmap.md): milestones and acceptance criteria
6. [docs/dev-setup-windows.md](docs/dev-setup-windows.md): setting up the dev machine

## Status

Pre-alpha. Only the docs and folder skeleton exist. Next step: **M1, the SketchUp pin + context packet spike** (see roadmap).
