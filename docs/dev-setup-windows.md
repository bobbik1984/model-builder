# Dev setup (Windows)

> Section 1 verified 2026-11-08 on the dev machine (SketchUp 2024 24.0.553, repo at `D:\OneDrive\Learning\Code\Gemini\model-builder`). Python/uv sections are still a draft until M1b.

## Prerequisites
- **SketchUp** 2024 or newer (Ruby 3.x)
- **Python** 3.11+ and **uv** (`winget install astral-sh.uv`)
- **Git**, with the repo cloned to e.g. `C:\dev\model-builder`
- **Claude Code** (or Claude Desktop) for the MCP connection
- Optional: **Rhino 8** (needed from M5)
- Recommended: VS Code with the Ruby LSP and Python extensions

## 1. Load the SketchUp extension from the repo (dev loader)
Don't copy files into Plugins. Instead, install a small loader that points at the repo:
```powershell
powershell -ExecutionPolicy Bypass -File tools\install-dev-loader.ps1     # options: -SketchUpVersion 2024, -Uninstall
```
It writes `%APPDATA%\SketchUp\SketchUp 2024\SketchUp\Plugins\model_builder_dev.rb`, which `require`s `hosts/sketchup/src/model_builder.rb` from this checkout. The absolute path is baked in, so re-run the script if the repo moves. No globals are used.

To reload after editing: **Extensions → Model Builder → Dev → Reload Ruby Files**, or `ModelBuilder.reload` in **Window → Ruby Console**. Restart SketchUp for menu/toolbar changes.

Unattended self-test (SketchUp must be closed; it starts, tests, and quits without saving):
```powershell
& "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "D:\OneDrive\Learning\Code\Gemini\model-builder\hosts\sketchup\dev\autorun_selftest.rb"
Get-Content "$env:LOCALAPPDATA\ModelBuilder\selftest\autorun_status.txt"
python tools\check_packet.py
```
Set the environment variable `MB_AUTORUN_KEEP_OPEN=1` to keep SketchUp open afterwards. OneDrive note: mark the repo folder "Always keep on this device", or SketchUp may fail to load files that are only online.

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

## 4. Smoke test
- M1a (now): "Manual test M1" in `docs/acceptance/m1a-pins-export.md`.
- M1b (later): Pin tool → click 2–3 faces → Export (later "Send to agent") → in Claude Code: *"What are the pins on?"*

## Debugging
- Ruby errors: the Ruby Console. Errors inside `UI.start_timer` callbacks can be silent, so wrap them and log to `%LOCALAPPDATA%\ModelBuilder\logs\`.
- Bridge logs: stderr. **Never write to stdout**, because stdout is the MCP channel.
- Port conflict: change `--port` and the host setting together.
