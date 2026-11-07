# Dev setup (Windows)

> Draft. Verify paths and versions on the actual machine and update this file.

## Prerequisites
- **SketchUp** 2024 or newer (Ruby 3.x)
- **Python** 3.11+ and **uv** (`winget install astral-sh.uv`)
- **Git**, with the repo cloned to e.g. `C:\dev\model-builder`
- **Claude Code** (or Claude Desktop) for the MCP connection
- Optional: **Rhino 8** (needed from M5)
- Recommended: VS Code with the Ruby LSP and Python extensions

## 1. Load the SketchUp extension from the repo (dev loader)
Don't copy files into Plugins. Instead, put a one-line loader there that points at the repo:

`%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins\model_builder_dev.rb`
```ruby
# Dev loader: points SketchUp at the git checkout
$LOAD_PATH.unshift('C:/dev/model-builder/hosts/sketchup/src') unless $LOAD_PATH.include?('C:/dev/model-builder/hosts/sketchup/src')
require 'model_builder'
```
(This is the only place where a global is acceptable, because the file is dev-only and never shipped.)

To reload after editing: in **Window → Ruby Console**, run `ModelBuilder.reload` (to be implemented in M1), or restart SketchUp.

## 2. Run the bridge
```powershell
cd C:\dev\model-builder\bridge
uv sync
uv run model-builder-bridge --port 8765
```

## 3. Connect Claude Code to the bridge (MCP)
```powershell
claude mcp add model-builder -- uv run --directory C:\dev\model-builder\bridge model-builder-bridge
```
Claude Code then starts the bridge itself over stdio, so step 2 is only needed for manual testing.

## 4. Smoke test (from M1)
1. Open `samples/models/` → a test model in SketchUp
2. Use the ModelBuilder toolbar → Pin tool → click 2–3 faces → "Send to agent"
3. In Claude Code: *"What are the pins on?"*

## Debugging
- Ruby errors: the Ruby Console. Errors inside `UI.start_timer` callbacks can be silent, so wrap them and log to `%LOCALAPPDATA%\ModelBuilder\logs\`.
- Bridge logs: stderr. **Never write to stdout**, because stdout is the MCP channel.
- Port conflict: change `--port` and the host setting together.
