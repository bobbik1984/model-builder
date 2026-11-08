# CLAUDE.md: notes for AI agents working on this repo

## Start here
Read `AGENTS.md`, then **`docs/handover.md`** (current state, how to launch, what is tested). Update the handover before you finish.

## What this is
This is an interaction layer between 3D modelers (SketchUp, later Rhino/Grasshopper) and an AI agent. Read `README.md` and `docs/architecture.md` first.

## Ground rules
- **The protocol is the product.** `protocol/schemas/*.json` is the source of truth. Change the schema first, then the bridge and the host adapters, then `docs/protocol.md`. Bump `protocol_version` on breaking changes.
- **Units and axes:** every value in the protocol uses **meters**, **right-handed, Z-up**, world coordinates. SketchUp works in inches internally, so adapters must convert at the boundary and never let inches leak into packets.
- **Entity references** are opaque strings with a host prefix: `su:<persistent_id>` and `rh:<guid>`. Never use array indices or names as identity.
- **Scope is enforced by the host,** not only by the prompt. An edit op that touches an entity outside the active scope must be rejected.
- **Each agent change is a single undo step,** opened as a proposal and committed only on user accept.
- Keep host adapters thin, with translation only. Logic belongs in the bridge.

## Testing reality
- Development happens on a **Windows** machine with SketchUp 2024 (and optionally Rhino 8). The Linux machine where this repo was started cannot run either host.
- The bridge (Python) can be tested anywhere, using `protocol/examples/` and a fake host.
- Host code can only be verified inside the app. On the Windows machine an agent can run the **unattended self-test** (`hosts/sketchup/dev/autorun_selftest.rb`, see handover) while SketchUp is closed. It covers capture math and export, not mouse/UI. For UI behavior, say so and ask the user to run the manual test in `docs/acceptance/`.
- Keep the two statuses apart in docs and reports: "code reviewed" vs. "tested in SketchUp" (auto or manual, with a dated record in `docs/acceptance/`).

## Code conventions
- Bridge: Python ≥ 3.11, managed with `uv`, formatted with `ruff`, tested with `pytest`.
- SketchUp: Ruby, under the namespace `ModelBuilder`, with every file inside `module ModelBuilder`. Follow the SketchUp Extension Warehouse rules (no global monkey-patching, no `$globals`).
- Rhino: Python 3 (Rhino 8 ScriptEditor / RhinoCommon) first, and C# only if needed.

## Decisions
Architectural decisions go in `docs/decisions/NNNN-title.md`. Read them before proposing a change that contradicts one.
