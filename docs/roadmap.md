# Roadmap

Each milestone ends with something **usable on the Windows machine**, together with acceptance criteria.

## M0: Skeleton ✅ (2026-11-07)
- [x] Repo structure, docs, draft protocol schema

## M1: Grounding spike (SketchUp)
Goal: prove the agent understands *where* you are pointing.

Legend: [x] = tested in SketchUp with a manual record in `docs/acceptance/`; [~] = code reviewed and/or auto-tested, no manual test yet; [ ] = not started.

### M1a: pins + export (host only)
- [~] SketchUp extension loads from the repo (dev loader), and a toolbar plus menu appear (loading auto-tested)
- [~] Pin tool: click → pin with point, normal, entity ref and path, drawn as a numbered marker (capture auto-tested 10/10; clicking untested)
- [~] Context packet export: camera, selection, pins, viewport screenshot, written to the session folder (auto-tested). Whether the screenshot shows the markers depends on whether `write_image` includes tool drawing (to check).

**Accept (M1a):** a human places pins on a real model and the exported packet is accurate (manual record in `docs/acceptance/m1a-pins-export.md`).

### M1a+: task handoff (host only)
- [~] Pin notes, Outline tool (polygon/line + metrics), reference images, task message + LOD, overlay, annotated image, brief.md (auto-tested, run A3; mouse/dialogs untested)

**Accept (M1a+):** the user marks a real problem (e.g. "atrium roof missing") with an outline, pin and references, and an operational agent restates the task correctly from the export alone.

### M1c: AI Build (built ahead of M1b/M2, from user feedback)
- [~] AI Build tool + request dialog; send to agents found on the PC or model APIs (＋ add); plan gate (read-only planning → approve → uninterrupted build → accept/reject); live link (`tools/mb_exec.py`); Kit helpers + mark surroundings (auto-tested A5/A6 with real Claude Code and DeepSeek; UI not yet used by a human)

**Accept (M1c):** the user marks a real place, attaches a reference, sends it to an agent, approves its plan, and accepts a correct result, all without leaving SketchUp and without pop-ups during the build.

### M1b: bridge + agent
- [ ] Bridge: file-based `get_context` first (reads the session folder), then TCP listener, `hello`, `context.push`; MCP tools `get_context` and `get_entity`
- [ ] Claude Code (or any MCP-capable agent) is connected to the bridge over MCP
- [ ] Agent connection per `docs/decisions/0003-agent-connection.md`: plugin starts the bridge; Option A (agent executable, Claude Code preset first, then Custom); SketchUp chat panel (threads, markup chips, proposal cards); Option B (direct API, keys in user env vars) after that

**Accept:** with 3 pins on different elements of a sample building, Claude answers "what is each pin on, and how far apart are pins 1 and 2?" correctly without any extra description.

## M2: Scoped edits + proposals
- [ ] Scope from the selection, enforced in both bridge and host
- [ ] `open_proposal` / `close_proposal`, ghost preview, accept/reject in the panel, one undo step
- [ ] Ops: `create_box`, `push_pull`, `move`, `set_tags`, `measure`, `render_view`
- [ ] From the atrium-roof study (`docs/studies/atrium-roof-build.md`): `get_geometry` (face loops), `raycast`, `add_mesh`, `extrude_faces`, `sweep_box`, `render_view` with hide/isolate, and proposals as generator + parameters
- [ ] HtmlDialog panel: connection status, message box, "Send to agent", proposal queue
- [ ] Pins, tags and threads are saved in the .skp (attribute dictionaries)

**Accept:** "Make the window at pin 1 200 mm deeper" changes only that window, previews it, and undoes in one step. An attempt to edit outside the scope is refused.

## M3: References + detail ops
- [ ] Insert a reference image/PDF page and register it to a face by 2 points plus a known distance
- [ ] Markup strokes ray-cast onto geometry
- [ ] Ops: `extrude_profile`, `offset_face`, `array_*`, `mirror`, `apply_material`, `find_entities`
- [ ] Agent self-check loop: render → compare with the reference → iterate

**Accept:** with a sill section detail registered on a facade, the agent builds the sill profile along the window width within ±5 mm of the drawing's dimensions.

## M4: Materials + propagation
- [ ] `material_from_reference` (crop a photo to texture)
- [ ] "Apply to all similar" through tags or `similar_to`
- [ ] Per-pin conversation threads visible in the panel

## M5: Rhino + Grasshopper
- [ ] Rhino 8 adapter (Python), with the same protocol
- [ ] `create_gh_definition`: the agent writes a parametric definition and exposes sliders, and the user tunes them without re-prompting
- [ ] First case: a louver/fin facade on a selected surface

## Open questions
- **Where does the conversation live?** Claude Code/Desktop as the chat with the host panel used only for pointing, or the host panel as the chat calling the Claude API directly? M1 uses Claude Code. Revisit at M2.
- **Proposal preview mechanism in SketchUp:** a separate tag plus a translucent material, versus keeping the geometry in an isolated group until accept. Spike it in M2.
- **PDF references:** rasterize in the bridge (e.g. with `pypdfium2`), or require PNG exports for now?
- **Voice + pointing:** later.
