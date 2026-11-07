# Protocol (v0.1, draft)

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
| `protocol_version` | `"0.1"` |
| `packet_id`, `created_at` | Identity and time (ISO 8601) |
| `host` | `{app, version, model_units}`, where `model_units` is what the user sees, for display only |
| `model` | `{name, path, bounds}` |
| `message` | The user's text instruction |
| `lod` | `massing \| schematic \| detail`, the requested level of detail |
| `camera` | `{eye, target, up, fov_deg, perspective, viewport_px:[w,h]}` |
| `views` | Images: `{kind: viewport \| annotated \| section, path, camera?}`. `annotated` has pins and strokes burned in |
| `scope` | `{mode: selection \| bbox \| none, refs[], bbox?}`. The editable region |
| `selection` | An entity summary for each selected item (ref, path, kind, name, tags, bounds) |
| `pins` | The pins, see below |
| `strokes` | Markup strokes projected onto the model |
| `references` | Registered reference images and drawings |

### Pin
```json
{ "id": "p1", "label": "sill", "point": [12.4, 3.1, 0.9], "normal": [1,0,0],
  "screen_px": [812, 455], "entity": { "ref": "su:48213", "path": ["su:1002","su:48213"],
  "kind": "face", "tags": {"role":"sill"} }, "note": "drip edge here" }
```

### Stroke
A polyline drawn in the viewport, ray-cast onto the geometry under it.
`{id, kind: circle | arrow | line | freehand, screen_px: [[x,y],...], world: [[x,y,z]|null,...], hit_refs: [...] }`.
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
