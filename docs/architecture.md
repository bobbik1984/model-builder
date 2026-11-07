# Architecture

## Components

```
┌────────────────────────── Windows PC ───────────────────────────┐
│                                                                  │
│  SketchUp                          Rhino 8 (later)               │
│  ┌──────────────────────┐          ┌──────────────────────┐      │
│  │ ModelBuilder ext.    │          │ ModelBuilder plugin  │      │
│  │  - Pin / Markup tool │          │  - same tools        │      │
│  │  - HtmlDialog panel  │          │  - DisplayConduit    │      │
│  │  - Op executor       │          │  - GH definitions    │      │
│  │  - Socket client     │          │  - Socket client     │      │
│  └─────────┬────────────┘          └─────────┬────────────┘      │
│            │  JSON-RPC 2.0, NDJSON over TCP 127.0.0.1:8765       │
│            └───────────────┬─────────────────┘                   │
│                  ┌─────────▼──────────┐                          │
│                  │ Bridge (Python)    │                          │
│                  │  - MCP server      │◄──── stdio ──── Claude   │
│                  │  - packet store    │     (Claude Code /       │
│                  │  - op validation   │      Claude Desktop)     │
│                  │  - proposal state  │                          │
│                  │  - pin threads     │                          │
│                  └────────────────────┘                          │
└──────────────────────────────────────────────────────────────────┘
```

### Host adapter (SketchUp extension, Rhino plugin)
The host adapter is thin and does only translation:
- **Capture:** pins, strokes, selection, camera, viewport images, registered references → context packet
- **Execute:** run validated ops against the model, inside one undoable operation
- **Preview:** show proposals as ghost geometry, accept/reject
- **Persist:** store tags, pins and threads in the model (SketchUp attribute dictionaries, Rhino user text/user data)
- **UI:** a side panel (SketchUp `HtmlDialog`, Rhino Eto/WebView) with chat, the pin list and the proposal queue

### Bridge (Python MCP server)
The bridge is the stable core:
- Exposes MCP **tools** to the agent: query, edit and verify ops (see `ops.md`)
- Exposes MCP **resources**: the latest context packet, pin threads and registered references
- Validates every op against the schema **and** the active scope before forwarding it to the host
- Keeps proposal state: open, previewing, accepted, rejected
- Stores session artifacts (packets, screenshots) under `.runtime/`, which is gitignored

### Agent
Claude, connected through MCP. The bridge has no model-specific code. The host panel can also send the user's text message, so a turn can start from inside SketchUp. See the open question in `roadmap.md`.

## Data flow: one interaction

1. The user selects the scope, drops pins #1 and #2, draws a circle, attaches `sill_detail.pdf` registered to a face, and types *"make the sill match the detail"*.
2. The host builds a **context packet** (JSON plus images) and sends `context.push` to the bridge.
3. The agent reads the packet through an MCP resource or `get_context`. It may call `render_view` or `get_entity` for more.
4. The agent calls edit ops. The bridge validates scope and forwards them, and the host executes them inside a **proposal** shown as ghost geometry.
5. The agent calls `render_view` to self-check against the reference, and iterates if needed.
6. The user accepts or rejects in the panel. On accept, the proposal is committed as one undo step and logged in the thread of pin #1.

## Key technical constraints
| Constraint | Consequence |
|---|---|
| SketchUp Ruby is single-threaded and the UI must not block | The socket uses non-blocking reads, polled with `UI.start_timer` (~50–100 ms) |
| SketchUp's internal unit is the inch | Convert to meters at the adapter boundary |
| SketchUp geometry is mesh-only | Curved profiles are segmented, and the segment count is a parameter |
| Bridge lifecycle follows the MCP client | The host client reconnects with backoff, and the panel shows connection status |
| Proposals must be undoable as one step | One `start_operation(…, true)` per proposal, or proposal geometry kept in an isolated group until accept |

## Why this split
- A protocol shared by all hosts means a Rhino adapter later doesn't duplicate logic.
- The bridge is testable on any OS without a modeler, using recorded packets and a fake host.
- Host adapters stay small, which keeps the code that has to be tested on Windows small.

See `decisions/0001-host-strategy.md` and `decisions/0002-transport.md`.
