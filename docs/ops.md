# Op library (draft)

These are the operations the agent can call through MCP tools. The bridge validates each one (schema + scope) and the host executes it.

Rules:
- All edit ops run **inside an open proposal** and are previewed until the user accepts.
- An edit op that targets a ref outside `scope` is **rejected**, and the bridge returns an error the agent can read.
- Every op returns `{ok, created_refs[], modified_refs[], deleted_refs[], warnings[]}`.
- Units are meters, as in `protocol.md`.

## Query (read-only)
| Op | Params | Phase |
|---|---|---|
| `get_context` | `packet_id?`, latest if omitted | M1 |
| `get_entity` | `ref`, `include: [geometry, tags, children]` | M1 |
| `find_entities` | `tags?`, `kind?`, `within_bbox?`, `similar_to?` | M3 |
| `measure` | `from: point\|ref`, `to: point\|ref` | M2 |
| `render_view` | `camera? \| preset (front, top, iso…)`, `style (shaded, hidden_line, xray)`, `section_plane?`, `show_proposal: bool` | M2 |

## Learned from the atrium-roof study (2026-11-08)

`docs/studies/atrium-roof-build.md` built a curved, triangulated roof end to end. What it needed, in addition to the ops below:

| Op | Params | Why |
|---|---|---|
| `get_geometry` | `ref`, `path` → loops (outer + holes) in world meters, plane, area | The boundary to build on (90 points) is a face loop, not the user's ~10 clicks |
| `raycast` | `origin`, `direction`, `ignore_refs[]` → point, path | Clearance and clash checks; camera placement; "what is above/below" |
| `add_mesh` | `triangles [[p,p,p]…]`, `material`, `parent?`, `name?` | Panels, ceilings, flashing. Planar by construction |
| `extrude_faces` | `refs[]`, `thickness`, `direction?` | 30 mm panels from the triangles |
| `sweep_box` | `segments [[a,b]…]`, `width`, `depth`, `top_offset` | Beams along arbitrary 3D lines |
| `render_view` + `hide_refs[]`, `isolate_refs[]` | | Towers hid the roof; two cameras landed inside solids |
| `check_proposal` | clearance rays, planarity, solid check | Verification beyond pictures |

Prefer **generators with named parameters** (re-run in seconds) over one-shot geometry: the references give intent, not numbers.

## Proposal control
| Op | Params | Phase |
|---|---|---|
| `open_proposal` | `title`, `pin_ids[]` (threads to log into) | M2 |
| `close_proposal` | `proposal_id`. Finishes building and hands it to the user for accept/reject | M2 |
| `discard_proposal` | `proposal_id` | M2 |

## Edit
| Op | Params | Phase |
|---|---|---|
| `create_box` | `origin`, `size [x,y,z]`, `parent_ref?`, `name?` | M2 |
| `push_pull` | `face_ref`, `distance` | M2 |
| `move` | `refs[]`, `vector` | M2 |
| `set_tags` | `refs[]`, `tags {role, lod, family…}` | M2 |
| `extrude_profile` | `profile: [[u,v],…]` in a plane frame, `frame {origin,u_axis,v_axis}`, `path: ref \| points[]` | M3 |
| `offset_face` | `face_ref`, `distance` | M3 |
| `array_linear` | `refs[]`, `vector`, `count` | M3 |
| `array_along` | `refs[]`, `path_ref`, `spacing \| count` | M3 |
| `mirror` | `refs[]`, `plane {origin, normal}` | M3 |
| `boolean` | `op: union\|subtract\|intersect`, `a_refs`, `b_refs` | M3 (fragile in SketchUp; solids only) |
| `apply_material` | `refs[]`, `material {name, color?, texture_path?, size_m?}`, `projection?` | M3 |
| `material_from_reference` | `reference_id`, `crop_px [x,y,w,h]`, `size_m [w,h]` | M4 |

## Parametric (Rhino/Grasshopper only)
| Op | Params | Phase |
|---|---|---|
| `create_gh_definition` | `script` (GH Python), `inputs [{name, type, default, min, max}]`, `bake_scope` | M5 |
| `set_gh_inputs` | `definition_id`, `values {}` | M5 |

## Escape hatch
| Op | Params | Notes |
|---|---|---|
| `run_host_script` | `language`, `code` | Off by default. When enabled, every call needs explicit user approval in the panel and still runs inside a proposal. Used to discover which ops are missing; promote frequent patterns into real ops. |
