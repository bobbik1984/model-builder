# Protocol (v0.4, draft)

The source of truth is `protocol/schemas/`. This document explains the schemas.

## Conventions
- **Units:** meters. **Axes:** right-handed, Z-up, world coordinates. **Angles:** degrees.
- **Points and vectors** are `[x, y, z]` arrays of numbers.
- **Entity refs** are opaque strings: `su:<persistent_id>` (SketchUp) or `rh:<guid>` (Rhino).
- **Entity path:** the list of refs from the model root to the entity (the group/component nesting). It's needed because the same component definition can appear in several places.
- **IDs** made by the host or bridge (`pin_id`, `packet_id`, `proposal_id`) are short strings such as `p1`, `pk_20261107_001` or `pr_7`.
- **Images** are referenced by a path relative to the session folder, never inlined into JSON. The bridge serves them to the agent.

## Transport: host ↔ bridge
- TCP `127.0.0.1:8765` (configurable). The **bridge listens** and the host connects as a client.
- **NDJSON:** one JSON-RPC 2.0 message per line, UTF-8.
- Both sides can send requests. Images are written to a shared session folder, `%LOCALAPPDATA%\ModelBuilder\sessions\<id>\`, and only the paths travel over the socket.

### Host → bridge
| Method | Purpose |
|---|---|
| `hello` | `{host, host_version, protocol_version, model}`. Handshake |
| `context.push` | Send a context packet (the user pressed "Send to agent") |
| `proposal.decision` | `{proposal_id, decision: accept \| reject, note?}` |
| `model.changed` | Notification that the user edited the model (invalidates cached context) |

### Bridge → host
| Method | Purpose |
|---|---|
| `op.execute` | Run one op (see `ops.md`) inside a proposal. Returns the result and the affected refs |
| `query.*` | Read-only queries: entity info, tags, bounds |
| `view.render` | Render an image from a given camera / style / section |
| `proposal.open` / `proposal.close` | Start or finish grouping ops into a previewable proposal |
| `panel.message` | Show agent text in the host panel |

## Context packet
Schema: `protocol/schemas/context_packet.schema.json`. Example: `protocol/examples/context_packet.example.json`.

| Field | Meaning |
|---|---|
| `protocol_version` | `"0.4"` |
| `session_id` | The host session; `views[].path` is relative to its folder |
| `packet_id`, `created_at` | Identity and time (ISO 8601) |
| `host` | `{app, version, model_units}`, where `model_units` is what the user sees, for display only |
| `model` | `{name, path, bounds}` |
| `message` | The user's text instruction |
| `lod` | `massing \| schematic \| detail`, the requested level of detail |
| `camera` | `{eye, target, up, perspective, fov_deg + fov_axis (vertical/horizontal) or ortho_height_m, viewport_px:[w,h]}`. Exported images are exactly `viewport_px` in size |
| `views` | Images: `{kind: viewport \| annotated \| section, path, camera?}`. `annotated` has pins and strokes burned in |
| `scope` | `{mode: selection \| bbox \| none, refs[], bbox?}`. The editable region |
| `selection` | An entity summary for each selected item (ref, path, kind, name, tags, bounds) |
| `pins` | The pins, see below |
| `strokes` | Markup strokes projected onto the model |
| `references` | Registered reference images and drawings |

### Pin
```json
{ "id": "p1", "label": "sill", "point": [12.4, 3.1, 0.9], "normal": [1,0,0],
  "front_facing": true, "snap": "face", "screen_px": [812, 455], "in_frame": true,
  "entity": { "ref": "su:48221", "path": ["su:1002","su:48213","su:48221"], "kind": "face" },
  "instance": { "ref": "su:48213", "path": ["su:1002","su:48213"], "kind": "component",
                "name": "Window_02", "definition": "Window 1200x1500", "bounds": {"min": [12.0,2.4,0.9], "max": [12.1,3.6,2.4]} },
  "path_detail": [ {"ref": "su:1002", "kind": "group", "name": "Facade_East"},
                   {"ref": "su:48213", "kind": "component", "name": "Window_02", "definition": "Window 1200x1500"},
                   {"ref": "su:48221", "kind": "face"} ],
  "note": "drip edge here" }
```

| Field | Meaning |
|---|---|
| `point` | World position, meters |
| `normal` | World unit normal of the face's front side (correct under rotation, non-uniform scale and mirroring). Absent if not on a face |
| `front_facing` | The export camera sees the front side |
| `snap` | `point` (vertex/midpoint/intersection), `edge`, `face` (exact ray hit), `none` |
| `screen_px`, `in_frame` | Pixel in the exported viewport image (top-left origin); in front of the camera and inside the frame (occlusion not checked) |
| `entity` | The hit entity. Its `ref` is shared by every copy of a component definition, so `path` is what identifies the occurrence |
| `instance` | Innermost group/component around the hit entity (absent at model root) |
| `path_detail` | `entity.path` with kinds and names |

v0.2 changes (additive): `session_id`, `camera.fov_axis`, and the pin fields `front_facing`, `snap`, `in_frame`, `instance`, `path_detail`.

v0.3 changes (additive): `layer` (tag) and `material` on path elements and entity summaries; stroke kind `polygon` plus `point_snaps`, `in_frame`, `hit_paths`, `hit_names`, `metrics {length_m, area_m2, centroid, normal, bounds}`. The host now fills `message`, `lod`, `strokes`, `references` (registration `none`) and an `annotated` view.

v0.4 changes (additive, from the park/facade handoff studies):
- **`warnings[]`**: what the plugin found at export:
  - marks out of frame or hidden behind geometry, and pins on back faces;
  - outline segments passing through geometry;
  - outlines on curved or folded surfaces;
  - imported CAD whose placement is unconfirmed;
  - missing or failed references.
- **`project_notes`**: the path of `<model>.project.md` next to the .skp, if it exists.
- **`cad_imports[]`**: top-level DWG/DXF components with `origin`, `rotation_z_deg` and `registration` (`unconfirmed`, or the user's confirmation from **Confirm Selected CAD Placement...**).
- **Pin `visible`**: false when hidden behind geometry. `in_frame` only checks the frame.
- **`instance.contents`** on pins: `{faces, edges, instances, tags[{name,count}], materials[{name,count}]}`, so unnamed groups can be identified.
- **Stroke fields:**
  - `point_normals`: the face normal at each point, or null;
  - `points_visible`;
  - `metrics.normal_spread_deg`: over 15° means a curved or folded surface.
- **Reference fields:** `size_px`, and `preview` (a downscaled PNG, longest side 1600 px) for images over 2400 px or 4 MB.

### Session folder (M1a)
```
%LOCALAPPDATA%\ModelBuilder\sessions\
  latest.json                 pointer: {packet_id, session_dir, packet_path, image_path, created_at}
  s_YYYYMMDD_HHMMSS\          one per SketchUp run (= session_id)
    latest.json               copy of the newest packet
    latest_brief.md           copy of the newest brief
    packets\pk_..._NNN.json
    briefs\pk_..._NNN.md       readable task summary (absolute paths)
    views\pk_..._NNN_viewport.png
    views\pk_..._NNN_annotated.png   pins/outlines burned in
    refs\pk_..._NNN_r1.png    copies of attached reference images
```

### Stroke
A polyline or closed outline drawn on the model (SketchUp: Outline tool, points snapped/ray-cast onto geometry, or projected onto a horizontal plane).
`{id, kind: polygon | line | circle | arrow | freehand, screen_px: [[x,y],...], world: [[x,y,z]|null,...], point_snaps: [...], hit_refs: [...], hit_paths: [[...]], hit_names: [...], metrics: {length_m, area_m2, centroid, normal, bounds}, note}`.
An arrow keeps its world-space direction, so it can be read as "move/extend this way".

### Reference
```json
{ "id": "r1", "kind": "cad", "file": "refs/sill_detail.png", "source": "sill_detail.pdf#page=2",
  "registration": { "type": "plane", "origin": [10,3,0], "u_axis": [1,0,0], "v_axis": [0,0,1],
                    "meters_per_px": 0.0005, "anchor_px": [[120,880],[1720,880]] } }
```
Registration types:
- `plane`: the image lies on a plane in the model. A pixel `(u,v)` maps to `origin + u*meters_per_px*u_axis + v*meters_per_px*v_axis` (image v pointing down → `v_axis` points down in the image's frame). Used for CAD elevations, sections and details.
- `camera`: the image was taken from a known camera (camera match). Used for photos and renderings.
- `none`: unregistered, a visual hint only.

## Versioning
- Additive changes (new optional fields) need a minor bump.
- Renames, removals or changed meanings need a major bump. Both sides check `protocol_version` in `hello`.
