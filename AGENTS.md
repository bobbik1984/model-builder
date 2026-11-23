# AGENTS.md: start here (development agents)

This repo is developed by a succession of interchangeable agents (Codex, Claude Code, Antigravity, Gemini, …) and humans. Continuity lives in the repo, not in any agent's memory.

1. **`docs/handover.md`**: current state, how to launch, feature status (code vs. tested in SketchUp), next steps. **Update it before you finish.**
2. **`CLAUDE.md`**: ground rules and conventions (the name is historical; they apply to every agent).
3. **`docs/acceptance/`**: test records. Append a dated run for anything you test; never claim "works" without one.
4. `README.md`, `docs/architecture.md`, `docs/protocol.md`, `docs/decisions/` for design.

Agents that *use* the plugin (operational agents) read `docs/agent-guide.md` instead.

Key rules in one breath: the protocol schema is the source of truth (change it first), meters/Z-up at every boundary, refs are `su:<persistent_id>` plus paths, host code stays thin, and **"code reviewed" ≠ "tested in SketchUp"**. Host code can only be verified inside SketchUp on the Windows machine. The unattended self-test (`hosts/sketchup/dev/autorun_selftest.rb`) covers capture math, but not the mouse or UI.
