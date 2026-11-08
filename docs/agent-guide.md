# Guide for operational agents

You are an agent **using** Model Builder to understand what a person is pointing at in their 3D model. (If you are developing this repo, read `AGENTS.md` instead.)

## How you get context

- **From M1b (planned):** through MCP tools served by the bridge (`get_context`, `get_entity`, …; see `docs/ops.md`). Any MCP-capable agent works; nothing is specific to one vendor.
- **Now (M1a):** the user exports from SketchUp, and you read files directly:
  - `%LOCALAPPDATA%\ModelBuilder\sessions\latest.json`: a pointer with absolute `brief_path`, `packet_path`, `image_path`, `annotated_image_path`, `reference_paths`
  - **start with the brief** (`brief_path`, Markdown): the task, warnings, images, outlines, pins in plain language
  - if the brief names **project notes** (`<model>.project.md`), read them first: facts earlier agents found (frames, where things are, decisions, open questions). **Update them when you finish**; mark what you assumed vs. what the user confirmed.
  - **Warnings** were checked by the plugin at export. Take them seriously. "Imported CAD … not confirmed to line up" means: check the CAD's position against the model before building from it. "Segment passes through …" means: the outline may be in the wrong place or frame.
  - large reference images have a **preview** (≤1600 px); view that first and open the original only for detail
  - the packet JSON is the source of truth (schema: `protocol/schemas/context_packet.schema.json`, v0.3)
  - images: `viewport` (clean), `annotated` (numbered red pins, orange outlines labelled S1…), and `refs/` (the user's sketches/renders); paths in the packet are relative to the session folder

## AI Build tasks (plugin 0.5): plan first, then build

The designer marks a place with **AI Build**, describes the task, attaches files and sends it to you. You get a task folder `<session>/tasks/<task_id>/` and work in two stages:

1. **Plan** (`prompt.md`):
   - Read the brief. Each mark comes with what is **around** it: the floor/ceiling heights and nearby groups with world bounds. Start there; don't survey the whole model.
   - Query the model only as needed. In this stage every script is **rolled back** (read-only), so queries are free and can't do harm.
   - Write `plan.md` (task, where, what you'll build, assumptions, questions) and **stop**.
   - The designer approves it, asks for changes, or cancels.
2. **Build** (`prompt_build.md`, after approval):
   - Scripts now take effect, each one undo step. There are **no prompts** to the designer during the build; the approved plan is the permission.
   - Build into `ModelBuilder::Kit.proposal('<title>')`, check once at the end, then write `reply.md`.
   - The designer then Accepts, or Rejects, which removes what you created.

Run scripts with `python tools/mb_exec.py --task <task_dir> script.rb`, where the script defines `MBScript.run(model, out_dir)`.

Use the **`ModelBuilder::Kit` helpers**. They work in meters and world coordinates and apply every group transform for you; raw `bounds` of nested groups are local:
- `Kit.mark('p1')`: where a mark is.
- `Kit.around(pt, r)`: what is near a point.
- `Kit.world_bounds(ref)`: the world bounds of a group or component.
- `Kit.ray(pt, dir)` and `Kit.level_at(x, y, z)`: hits, and the floor and ceiling at a point.
- `Kit.proposal(title)`, `Kit.box(...)`, `Kit.extrude(...)`: build.
- `Kit.render(out_dir, name, eye:, target:)`: render a view.

Direct-API agents get the same flow as tools: `run_ruby`, `submit_plan`, `finish`.

## Reading a packet

- **Units and axes:** meters, right-handed, **Z up**, world coordinates. `host.model_units` is only what the user sees; ignore it for math.
- **Pins** are numbered `p1, p2, …` in click order; the user will say "pin 1", "#2" and so on. For each pin:
  - `point`: exact world position. Distances between pins are plain Euclidean distances of these.
  - `normal`: unit normal of the face's front side in world space. `front_facing: false` means the user clicked a face seen from behind (or the camera moved since).
  - `snap`: `point` = snapped to a vertex/midpoint/intersection (exact corner), `edge` = on an edge, `face` = somewhere on a face.
  - `entity`: the face hit. `entity.ref` alone is **not** unique, because faces inside a component definition share a ref across all copies. Identify an occurrence by `entity.path`.
  - `instance`: the innermost group/component around the face (its name, definition and world `bounds`). This is usually "the thing" the user means (a window, a beam).
  - `path_detail`: the full chain from model root to the face, with names. Read it like a breadcrumb: `group:Facade_East > component:Window_02 (Window 1200x1500) > face`.
  - `screen_px` / `in_frame`: where the pin is in the PNG (origin top-left; the image size equals `camera.viewport_px`). This does not check occlusion: a pin can be in frame but hidden behind something.
- **Pins (v0.4)**: `visible: false` = hidden behind geometry in the screenshot (drawn hollow in the annotated image). `instance.contents` tells you what the containing group holds (faces, sub-groups, top tags/materials). Use it to recognise unnamed groups.
- **Outlines (`strokes`)**: `point_normals` gives the surface normal under each point. If `metrics.normal_spread_deg` is large, the outline lies on a curved/folded surface and the best-fit `normal` is not the surface. Hidden points are drawn dashed.
- **Outlines, general**: `polygon` = a closed area the user drew on the model, `line` = a path. `world` points in meters; `point_snaps` tells you whether each point is a precise corner/edge (`point`/`edge`), on a face, or projected onto a horizontal plane (`plane`, used over voids). `metrics` gives area, perimeter, centroid and best-fit normal. `hit_names` lists the elements the outline touches. An outline + note like "roof missing" means: the thing to build fills that outline.
- **References**: the user's images with `kind` (sketch, render, photo, cad, section) and a `note`. `registration: none` means they are not placed in the model; use them for design intent (pattern, profile, materials), and take dimensions from the model/outline, not from the image, unless the note says otherwise.
- **Notes**: pins and outlines may carry the user's note (any language). The task is in `message`, with `lod`.
- **Camera:** `eye`, `target`, `up`, `fov_deg` (+`fov_axis`) or `ortho_height_m`. Use it to describe directions as the user sees them ("left", "front").
- **Selection** is informational in M1. **Scope** is `none` until M2: you may not edit anything yet.

## Answering well

- Name the element from `path_detail`/`instance` (names, definitions, tags/layers, materials), and give coordinates or distances in meters (or in `model_units` if the user prefers).
- Before modeling, restate the task: what to build, where (outline/pins with coordinates), at what size, following which reference. Ask about anything the references leave open.
- If two pins share `entity.ref` but have different paths, they are on **different copies** of the same component. Say so.
- If something is ambiguous (no names, `in_frame: false`), say what you can determine and ask.
