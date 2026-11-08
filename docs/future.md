# Where this could go: opportunities and improvements (2026-11-08)

Written after three end-to-end studies (`docs/studies/atrium-roof-build.md`, `park-handoff.md`, `facade-handoff.md`). This is a direction document, not a commitment; the roadmap stays the plan of record.

## What the studies showed

| Observation | Evidence | Meaning for the product |
|---|---|---|
| Intent transfers well | 2/2 clean-context agents restated the task correctly from the export alone | The pointing + brief format works; keep it |
| Tokens and time go on *discovering the model*, not on building | ~225–250k tokens and 20–27 min per task, most of it spent on frames, unnamed groups, tags and levels | The biggest win is giving the agent a **map of the model**, not more markup |
| Designers make markup mistakes | DWG called "registered" while 44° off; billboard outline vs. render; misleading tag hint | Checks at export time (now in 0.3.0) plus "plan → approve → build" |
| Agents use general tools heavily | Python (shapely), image viewing, scripts, JSON analysis | Coding agents are the strongest operators; the direct-API mode needs a comparable toolset |
| References give intent, rarely numbers | Pitch, spacing, panel sizes were all assumed | The output should be a **generator + parameters** the user tunes, not baked geometry |
| Each check costs a SketchUp restart (10–50 s) | All three studies | The live bridge (M1b) is the main speed fix |
| The same building blocks recur | Triangulated roof over an outline; regions from CAD linework; panels along curved bands; scattering trees | A **generator library** makes agents cheaper and more reliable |

## 1. Understand the model (biggest lever)

- **Model map:** a cached, incrementally updated summary per model, along the lines of `model_map.json` + `.md`:
  - levels detected from horizontal faces and slabs;
  - per group: footprint, z-range, faces, tags, materials, a guessed role (slab, wall band, tower, core, glazing, CAD import, context);
  - frames and CAD imports;
  - named zones.

  The agent reads this in ~5k tokens instead of rediscovering it in 200k. It should be served by `get_model_map` and updated when the model changes (observers).
- **Auto-naming with confirmation:** suggest names for unnamed groups ("Podium band L3 east", "Tower B"), and the user accepts in bulk. Real projects are full of `Group#23`.
- **Project notes as a first-class feature:** facts, decisions, assumptions vs. confirmations, open questions. Stored in the .skp and mirrored to `<model>.project.md`. The panel shows open questions so the user can answer them in one place.
- **Frames and registration:** a two-point align tool for CAD and images, with stored control points. Check alignment against the model (outline overlap) and suggest a fit, as the park agent did by hand.

## 2. Point and say better

- **Plan → approve → build:** the agent returns a plan with a restatement, a parameter table and assumptions *before* building. Cheap to review, and it prevents 20 minutes spent on a wrong assumption (the 44° fit).
- **Scope:** selected groups or outlined areas become the edit scope, enforced by the bridge (M2). It doubles as "what the agent must not touch".
- **Dimensions on markup:** type a value on an outline segment ("this is 12.5 m", "pitch 8°"). Numbers the references don't give come from the user directly.
- **Freehand sketch on the viewport**, projected onto surfaces: the natural designer gesture (circle, arrow, hatch).
- **Voice notes** transcribed into pin notes, for site walks and reviews.
- **Reference types beyond images:** an in-model DWG (`cad_in_model`), PDF pages (rasterised, with a scale), and links to other proposals ("like the park bridge").
- **Camera-matched references:** use SketchUp's Match Photo (or solve from 4+ clicked correspondences) to put a render's camera into the model. Then render pixels map to model surfaces, and the agent can compare its result with the reference pixel by pixel. This is how "as in the rendering" becomes checkable.

## 3. Build reliably: a generator library

Recurring tasks become parametric generators the agent calls with parameters instead of writing 400 lines of Ruby:

| Generator | From study | Parameters |
|---|---|---|
| `roof_over_opening` (gable/diagrid/flat, panels, beams, sprinklers) | atrium roof | outline, pitch, spacing, sweep, build-up layers |
| `regions_from_linework` (closed regions from DWG lines, classified by a colour legend) | park | layers, legend image, gap tolerance |
| `parking_layout` (bays, aisles, counts) | park | outline, stall size, aisle width, angle |
| `scatter` (trees, furniture) | park | regions, density, species, spacing |
| `panelize_bands` (strips along curved faces, staggered, tone gradient) | facade | target faces, strip heights, lengths, tones, relief |
| `stair`, `ramp`, `bridge_deck` | park | levels, width, run/rise |
| `media_surface` (LED mesh, billboard) | facade | outline, texture |

- Generators run in the **proposal** (ghost geometry, one undo step) and keep their parameters on the result, so "pitch 8°" re-runs in seconds. That's also the Rhino/Grasshopper path (M5).
- **Agent-written generators get promoted:** when an agent writes a good script through the approved-script escape hatch, save it as a candidate generator with a parameter schema.
- **Geometry hygiene:** components for repeated panels (the facade's 44k faces → ~15 MB growth); proxies and LOD switching; consistent tags per proposal.

## 4. Verify like a reviewer

- **Geometric checks:** clashes and clearance (rays, solids), planarity, gaps along outlines, heights against limits. Some already exist (`check.rb`, 0.3.0 export checks).
- **Quantities as proof:** stall count vs. the site plan, panel counts per tone, fire-panel area, GFA per level. Numbers are easier to review than pictures, and they feed cost estimates.
- **Visual compare:** a render from the camera-matched reference view next to the reference (and a diff), plus standard views (top, axonometric, eye level).
- **Rules:** project rules in the notes ("all skylight panels fire-rated", "parking ratio ≥ x"), checked after each build.

## 5. Outputs beyond geometry

- **Presentation:** scenes for the user's renderer (Enscape/D5/V-Ray cameras), LayOut sheets, before/after views.
- **Schedules:** CSV/Excel of quantities from the generators' parameters.
- **Issues:** each pin thread exportable as BCF for Revit/Navisworks teams; review comments flow back as pins.
- **Decision log:** what was proposed, accepted or rejected, and why, per pin and per project.

## 6. Agents and evaluation

- **Agent pack:** the agent guide, MCP tool descriptions and project-notes rules shipped as a skill/instructions bundle for each supported agent (CLAUDE.md snippet, Codex/Gemini equivalents), so any agent behaves consistently.
- **Benchmark suite:** the three studies become repeatable tasks (inputs, export, expected checks: restatement correct, outline respected, counts, no edits outside scope) and are run per agent and model. This answers "which agent/model?" with data (quality, tokens, time, cost), including continuous vs. fresh + notes.
- **Model routing:** a cheap model for questions and map queries, a strong one for builds; the model map and notes keep both cheap.

## 7. Platform and adoption

- **Speed:** the live bridge, streaming progress in the panel, and early partial previews. 20+ minutes with no feedback is the biggest adoption risk.
- **Trust:** an assumptions table always visible, nothing committed without Accept, automatic versioned copies before each accepted proposal.
- **Real-world mess:** DWG imports, nested unnamed groups, huge models. The model map, hygiene tools and scope limits matter more than new features.
- **Cross-platform:** paths (`%LOCALAPPDATA%`) and the launcher are Windows-only today, and SketchUp users include many Macs.
- **Privacy and offline:** project data goes to cloud models. Offer a local/self-hosted endpoint option (OpenAI-compatible), and redact paths/names in packets on request.
- **Distribution:** Extension Warehouse rules (bundled executables, signing). The bridge may need to ship separately or as a signed installer.
- **Other hosts:** the protocol is host-neutral. Rhino/Grasshopper (parametric), then Revit (BIM data, families) and Blender are natural next adapters.

## Suggested order (next steps)

1. **M1b bridge** with a live session, `get_context`, `get_model_map`, and plan → approve → build in the SketchUp chat panel (decision 0003). This fixes speed and trust.
2. **Model map + auto-naming + project notes in the .skp.** This fixes the token and time cost.
3. **Proposals (ghost, accept, one undo) + the first three generators** (`roof_over_opening`, `regions_from_linework`, `panelize_bands`), with a parameter panel.
4. **Two-point CAD/image registration and camera-matched references**, plus a visual compare.
5. **Quantities and the benchmark suite**, so improvements are measured, not guessed.
