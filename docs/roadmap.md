# Roadmap

Each milestone ends with something **usable on the Windows machine**, together with acceptance criteria.

## M0: Skeleton ✅ (2026-11-07)
- [x] Repo structure, docs, draft protocol schema

## M1: Grounding spike (SketchUp)
Goal: prove the agent understands *where* you are pointing.
- [ ] SketchUp extension loads from the repo (dev loader), and a toolbar plus menu appear
- [ ] Pin tool: click → pin with point, normal, entity ref and path, drawn as a numbered marker
- [ ] Context packet builder: camera, selection, pins, viewport and annotated screenshots, written to the session folder
- [ ] Bridge: TCP listener, `hello`, `context.push`; MCP tools `get_context` and `get_entity`
- [ ] Claude Code is connected to the bridge over MCP

**Accept:** with 3 pins on different elements of a sample building, Claude answers "what is each pin on, and how far apart are pins 1 and 2?" correctly without any extra description.

## M2: Scoped edits + proposals
- [ ] Scope from the selection, enforced in both bridge and host
- [ ] `open_proposal` / `close_proposal`, ghost preview, accept/reject in the panel, one undo step
- [ ] Ops: `create_box`, `push_pull`, `move`, `set_tags`, `measure`, `render_view`
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
