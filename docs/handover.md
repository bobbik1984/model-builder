# Handover: current state of the project

**Read this first** if you are picking up development (any agent or human).
Update it at the end of every work session. Last update: **2026-11-08** (Claude Code; extension **0.5.0**, protocol **0.4**).

## Where things stand (summary)

- **Pointing and export (M1a/M1a+): code complete and auto-tested** inside SketchUp 2024:
  - calibration 10/10, real model 41/41;
  - export checks, previews, project notes.
- **AI Build (0.5) is the main entry:**
  - mark a place (click again = pin; back to the first point = outline);
  - describe it and attach files;
  - send it to an agent found on this PC (Claude Code, Antigravity, any agent) or a model API (DeepSeek, Anthropic, OpenAI-compatible, ＋ add);
  - the agent plans read-only → the designer approves → it builds without interruption → Accept/Reject.
- **Real agents verified end to end** through the live link: DeepSeek (16k tokens) and Claude Code (resumed session). See acceptance runs A5 and A6.
- **The user's first real run (0.4)** was disruptive: 39 approval pop-ups, 695k tokens, the agent could not see the reference image. That led to 0.5; evidence is in `samples/references/20261108_dialog.PNG`.
- **Not yet done by a human:** the AI Build mouse flow and dialog in the 0.5 UI. **That is the next step** (see below).
- **Studies with clean-context agents** in `docs/studies/`: the atrium roof, the north park, and the facade panels. `docs/future.md` collects the product opportunities.

## Two kinds of agents

| | Development agents | Operational agents |
|---|---|---|
| Who | Codex, Claude Code, Antigravity, Gemini, humans… Interchangeable. | Any agent that *uses* the plugin to understand or edit a model. |
| What they touch | This repo: code, schemas, docs | Context packets (and, from M1b, MCP tools exposed by the bridge) |
| Continuity comes from | `AGENTS.md` → this file → `docs/acceptance/` records → code | `docs/agent-guide.md` + the protocol (`protocol/schemas/`) |
| Requirements | Can read/write files; ideally run PowerShell + SketchUp on the Windows dev machine | Must support MCP tool calling (M1b+). Until the bridge exists: can read a JSON file and a PNG |

Nothing in the protocol or the bridge may depend on which operational agent is connected.

## Status vocabulary

Every feature is tracked on two separate axes. **Do not merge them.**

- **Code:** `written` (exists, not reviewed) → `reviewed` (read through, schema-valid, logic checked)
- **SketchUp:** `untested` → `auto-tested` (passed the unattended self-test inside real SketchUp) → `manually tested` (a human used it in the UI and filled in an acceptance record)

"Reviewed" or "auto-tested" is **not** "works for the user". Only `manually tested`, with a dated record in `docs/acceptance/`, closes a feature.

## How to launch (Windows dev machine)

Repo: `D:\OneDrive\Learning\Code\Gemini\model-builder`. SketchUp 2024 (24.0.553).

1. Install the dev loader once (writes `%APPDATA%\SketchUp\SketchUp 2024\SketchUp\Plugins\model_builder_dev.rb`, which `require`s the extension from the repo):
   `powershell -ExecutionPolicy Bypass -File tools\install-dev-loader.ps1` (`-Uninstall` removes it)
2. Start SketchUp. You get **Extensions → Model Builder** and a **Model Builder** toolbar: **AI Build** (main entry), AI Build Request (dialog), Clear Markup. The older Pin/Outline/Attach/Export commands are in the menu.
   - AI Build: click a point, then click it again for a pin; or click points and return to the first for an outline. The dialog opens: description, 📎 attachments, **Send to** (＋ adds an API), then Plan → Approve & build → Accept/Reject.
   - Agents act on the open model through the **live link** (`tools/mb_exec.py`). API keys are read from user environment variables (`DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY`, …).
3. After editing Ruby files: **Extensions → Model Builder → Dev → Reload Ruby Files** (or `ModelBuilder.reload` in the Ruby Console). Menu/toolbar changes need a restart.
4. Unattended self-test (no clicking; launches SketchUp, runs, quits without saving). SketchUp must be closed first:
   `& "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_selftest.rb"`
   Results go to `%LOCALAPPDATA%\ModelBuilder\selftest\autorun_status.txt` and `last_result.json`.
5. Probe a real model the same way (opens it, "clicks" a 9×7 grid of its saved view, verifies every capture independently, exports, quits; **point it at a copy**):
   `$env:MB_PROBE_MODEL = "<copy>.skp"; & "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_probe.rb"` → `selftest\probe_status.txt`, `probe_result.json`. Inside SketchUp: **Dev → Probe Current View**.
6. Check any exported packet: `python tools/check_packet.py` (newest) or `python tools/check_packet.py <packet.json>`.
6b. End-to-end agent test in a **separate** SketchUp instance (your open SketchUp is not touched):
   `& "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_agent_test.rb"`
   → `selftest\agent_test_status.txt`, `agent_test.json`. Optional real agents: `$env:MB_TEST_API="deepseek"`, `$env:MB_TEST_CLAUDE="1"` (costs tokens).
7. Release build (later): `tools\package-rbz.ps1` → `hosts\sketchup\dist\model_builder-<ver>.rbz`.

Output locations: packets/screenshots in `%LOCALAPPDATA%\ModelBuilder\sessions\`, log in `%LOCALAPPDATA%\ModelBuilder\logs\model_builder.log`.

## Phase M1a: "pins + export" (current)

Scope agreed with the user: exactly four features. Bridge and MCP are M1b.

| # | Feature | Code | SketchUp | Evidence |
|---|---|---|---|---|
| F1 | Menu **Extensions → Model Builder** + toolbar | reviewed | **loaded (auto)**; not yet seen by a human | Log line "Loaded Model Builder 0.1.0" on 2026-11-08 run |
| F2 | Pin tool: click → numbered marker (snaps to points/edges), Backspace = remove last, right-click menu, Clear Pins | reviewed | **untested** (needs mouse) | — |
| F3 | Per-pin data: world point (m), world normal, front-facing, snap, hit entity ref, innermost instance (component ID), full instance path with names | reviewed | **auto-tested**: calibration 10/10 (A1); real skylight model 41/41 incl. point/edge snapping, 8-level paths (A2) | `docs/acceptance/m1a-pins-export.md` runs A1, A2 |
| F4 | Export: packet JSON + viewport PNG to the session folder | reviewed | **auto-tested** (non-interactive path); dialog not seen by a human | Runs A1–A3: schema OK, PNG = viewport size, screen_px verified on image |
| F5 | Pin notes (prompt after each click; Shift+click = no prompt; right-click → edit) | reviewed | auto-tested (data path, incl. Chinese text); prompt **untested** | A3 |
| F6 | Outline tool: click points → closed outline (polygon) or line, note, metrics (area/perimeter/centroid/normal), elements touched; P = plane lock | reviewed | auto-tested (data + metrics); clicking **untested** | A3 |
| F7 | Attach Reference Image (copied into the export, with kind + note) | reviewed | auto-tested with the real skylight images (Chinese paths); file dialog **untested** | A3 |
| F8 | Task message + level of detail, asked at export | reviewed | auto-tested (data); dialog **untested** | A3 |
| F9 | Markup always visible (SketchUp 2023+ Overlay), whatever tool is active | reviewed | **untested** (needs a human to look) | — |
| F10 | Annotated screenshot (pins/outlines burned in by `raster.rb`) + `brief.md` task summary | reviewed | auto-tested; image inspected | A3 |
| F11 | Tag (layer) and material names in paths/briefs | reviewed | auto-tested on the calibration scene | A3 |
| F12 | Export checks → `warnings[]` (hidden/out-of-frame marks, outline through geometry, curved outline, unconfirmed CAD), pin `visible`, stroke `point_normals`/`points_visible`/`normal_spread_deg`, hidden marks dashed/hollow in the annotated image | reviewed | **auto-tested** (A4; occlusion with an independent camera) | A4 |
| F13 | Group summary under a pin (`instance.contents`: faces, sub-groups, top tags/materials) | reviewed | auto-tested (A4), real model no regression (A2 rerun 41/41) | A4 |
| F14 | Reference previews (≤1600 px PNG) for big images; size in packet | reviewed | auto-tested incl. orientation (synthetic image) and a real 5000 px render | A4 |
| F15 | Project notes `<model>.project.md` picked up into packet/brief/pointer | reviewed | auto-tested (A4) | A4 |
| F16 | **Confirm Selected CAD Placement...** (marks DWG/DXF imports as registered) | reviewed | attribute path auto-tested; menu/dialog **untested** | A4 |
| F17 | Outline tool snaps to bare linework (imported DWG edges without faces) | reviewed | **untested** (needs mouse) | — |
| F18 | Delete single pins/outlines: panel ✕, right-click on a mark in the tools, Delete key; numbers never reused | reviewed | data path + screen picking auto-tested (A5); mouse **untested** | A5 |
| F19 | **Panel** (toolbar first button): 1 Where (marks: note, zoom, delete) · 2 What (task, LOD, references: image/DWG/DXF/PDF/selected-in-model) · 3 Who (detected agents, API providers with key from user env vars: save/test) · Send · conversation · Accept/Reject | reviewed | state/back end auto-tested (A5); **the HTML UI itself is untested** (needs a human) | A5 |
| F20 | Live link (`live_link.rb` + `tools/mb_exec.py`): agent scripts run in the open model, one undo step each, approval or auto-approve, rollback on error, camera restored, created objects tracked → Reject | reviewed | auto-tested round trip incl. failing script + reject (A5) | A5 |
| F21 | Agent launchers: Claude Code headless (stream-json into the conversation), Antigravity IDE (`antigravity-ide chat -m agent`), Codex/Gemini CLI (flags unverified), "Any agent (copy the prompt)" | reviewed | Claude Code: see A5; Antigravity/Codex/Gemini **untested** | A5 |
| F23 | **AI Build** (main toolbar entry): one tool — click a point and click it again = pin; several points back to the first = outline; Enter = open line; right-click/Delete on a mark | reviewed | **untested** (needs mouse) | — |
| F24 | AI Build dialog: marks (chips, ✕), description, 📎 attach (image/DWG/PDF/from selection), **Send to** (agents found + model APIs, **＋** adds an API: name/type/base URL/model/key → user env var / vision flag), warning when the model cannot see attached images | reviewed | back end auto-tested (A6); **HTML untested** | A6 |
| F25 | Plan gate: planning = read-only (scripts rolled back, no prompts) → plan card → Approve & build / Revise / Cancel → build without interruption → report → Accept/Reject. One status line instead of a stream of messages | reviewed | auto-tested with the manual flow + real agents (A6) | A6 |
| F26 | `ModelBuilder::Kit` helpers for agent scripts (world bounds, around, ray, level, proposal, box, extrude, render) + **surroundings** of each mark in packet/brief | reviewed | auto-tested (nested scaled B2 world bounds, around, level) | A6 |
| F22 | Direct-API agent (`api_agent.rb`): OpenAI-compatible (DeepSeek, OpenAI, Gemini) and Anthropic, tools run_ruby/write_plan/finish, image when the provider supports it | reviewed | DeepSeek: see A5; Anthropic/OpenAI **untested** | A5 |

**Phase M1a exit criterion:** a human places pins on a real model and exports a packet whose data is accurate (acceptance record M1a-manual filled in and passing). **Not met yet.**

## What the user needs to do next (manual test)

1. Restart SketchUp so **0.5.0** loads; the toolbar changes.
2. Click **AI Build** and mark a place: click a point and click it again for a pin, or outline an area.
3. In the dialog: describe the task, 📎 attach the reference, then **Send to** an agent or model. Pick a model that can see images, or describe the image in the text; DeepSeek is text-only.
4. Check:
   - planning causes no pop-ups;
   - the plan card appears, and **Approve & build** runs without interruption;
   - **Accept** / **Reject** work.
5. Try **＋** to add an API, and **Revise…** on a plan.
6. Record the result as "Manual test M3 (AI Build)" in `docs/acceptance/m1a-pins-export.md`.

Earlier manual tests (M1 pins, M2 handoff) are still open but superseded by this flow.

## Known limitations / open questions

- Pins live in memory only. They are lost on restart and not saved in the .skp (M2).
- **Verified:** `view.write_image` does NOT include overlay (or tool) drawing; the clean and "annotated" images were byte-identical. The annotated image is therefore drawn by `raster.rb` (reads a temp BMP from write_image, draws, writes PNG with zlib). Only digits and S/P/R exist in its pixel font; notes appear in the brief, not on the image.
- Outline points over a void (e.g. an atrium opening) hit whatever is below unless you snap to the rim edges or press **P** (plane lock at the first point's height).
- `scope` is always `{mode: none}`. Selection is reported but not enforced (M2).
- Snapped pins (endpoint/edge) are only exercised manually. If a snapped point does not lie on the entity under the cursor, the code re-aims a ray at it, or falls back to the exact surface hit (logged).
- Faces cut away by section planes can still be hit by `raytest`.
- Requires SketchUp 2020+ (local-coordinate API semantics). Only 2024 has been tested.
- `.rbz` built with Windows PowerShell 5.1 uses backslash zip paths. That's fine on Windows; check before any Mac use.
- Unnamed groups (common in real models, e.g. the skylight sample) give agents identity without meaning. Candidate: add tag/layer and material names to `path_detail` (additive, v0.3).
- Sample models, references and agent results are committed under `samples/` with **Git LFS** (`samples/README.md`). They are real project material.
- The protocol is **v0.4** (additive: warnings, cad_imports, project_notes, visibility, point normals, previews, surroundings, in-model references). See `docs/protocol.md`.
- Live-link scripts run arbitrary Ruby in the open model. Planning is read-only (always rolled back), and building is permitted by the approved plan. Reject removes created top-level objects only, not modifications of existing ones.
- API planning state (the conversation) lives in memory: restarting SketchUp loses an unapproved plan. Claude Code tasks resume through `--resume <session>`.
- Codex/Gemini CLI flags are unverified (not installed). Antigravity opens its IDE chat; whether its agent runs `mb_exec.py` is untested.
- The CLI launcher hides the console (WScript.Shell) and cannot be killed from the panel; Cancel only stops accepting scripts.

## Next steps (in order)

1. **User:** manual test M3 (AI Build, above). Fix whatever it finds, especially in the dialog HTML, which no human has used yet.
2. Make the panel's Cancel stop agent programs (track the PID instead of using WScript.Shell).
3. Save pins/outlines and tasks in the .skp (attribute dictionaries), so a plan survives a restart.
4. Model map (`docs/future.md` §1) and the generator library (§3), to cut agent exploration further.
3. **M1b bridge:** Python MCP server (`bridge/`). Start with a *file-based* `get_context` that reads `sessions/latest.json` (no socket needed yet). Then add the TCP `hello`/`context.push` link per `docs/protocol.md`.
4. Connect an operational agent (Claude Code first) over MCP. Run the M1 acceptance question from `docs/roadmap.md`: "what is each pin on, and how far apart are pins 1 and 2?"
5. Then M2 per roadmap. **Read `docs/studies/atrium-roof-build.md` first**: a dev agent built the missing atrium roof by hand-written Ruby, and the study lists the steps, information and ops that the build actually needed (mesh-level ops, boundary loops, raycast, render with hide/isolate, generator + parameters).

## Session log

| Date | Agent | Summary |
|---|---|---|
| 2026-11-08 | Claude Code (Opus 5.5) | Plugin 0.5.0 after the user's first real run (39 approval pop-ups, 695k tokens): AI Build tool + dialog, plan gate (read-only planning, approve/revise, uninterrupted build), Kit helpers + mark surroundings, ＋ add API, vision warning, stage limits; run A6 PASS (DeepSeek 16k tokens, Claude Code resumed session) |
| 2026-11-08 | Claude Code (Opus 5.5) | Plugin 0.4.0: Model Builder panel (where/what/who/send, conversation, accept/reject), delete single marks, live link (`mb_exec.py`), agent launchers (Claude Code headless, Antigravity IDE, any agent), direct-API agent (DeepSeek tested); run A5 PASS incl. real Claude Code + DeepSeek builds |
| 2026-11-08 | Claude Code (Opus 5.5) | `docs/future.md`: opportunities/improvements from the three studies (model map, plan→approve→build, generator library, camera-matched references, quantities, benchmark suite) |
| 2026-11-08 | Claude Code (Opus 5.5) | Plugin 0.3.0 / protocol 0.4: export checks + warnings, visibility, point normals, group contents, reference previews, project notes, CAD registration command (F12–F17); runs A4 PASS + A2 rerun 41/41 |
| 2026-11-08 | Claude Code (Opus 5.5) | Decision 0003 (agent connection: executable presets / direct API with env-var keys / SketchUp chat panel), accepted by the user |
| 2026-11-08 | Claude Code (Opus 5.5) | Study: facade panels via clean-context subagent (`docs/studies/facade-handoff.md`); first project notes file `samples/models/20260330_Massing.project.md` |
| 2026-11-08 | Claude Code (Opus 5.5) | Study: designer markup → clean-context subagent built the north park (`docs/studies/park-handoff.md`); found the export can carry false geometry claims (DWG "registered" but 44° off); Outline tool now snaps to bare DWG linework (mouse test pending) |
| 2026-11-08 | Claude Code (Opus 5.5) | Study: built the atrium skylight roof proposal on a copy of the skylight model (`docs/studies/atrium-roof-build.md`, `hosts/sketchup/dev/studies/atrium_roof/`, generic runner `dev/autorun_script.rb`); result `samples/models/20261020_skylight_model_roof_proposal_v2.skp`, not reviewed by the user |
| 2026-11-07 | (initial) | Skeleton: docs, schema v0.1, folders |
| 2026-11-08 | Claude Code (Opus 5.5) | Task handoff: pin notes, Outline tool, reference images, task message, overlay, raster-annotated image, brief.md, tags/materials in paths; protocol 0.3; run A3 PASS |
| 2026-11-08 | Claude Code (Opus 5.5) | Real-model probe (`dev/model_probe.rb`, `autorun_probe.rb`): skylight sample 41/41 (run A2) |
| 2026-11-08 | Claude Code (Opus 5.5) | M1a: extension (F1–F4), protocol v0.2, dev loader + installer, calibration scene, self-test (10/10 in SketchUp 24.0.553), packet checker, rbz script, handover/acceptance/agent docs |
