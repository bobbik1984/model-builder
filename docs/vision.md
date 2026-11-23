# Vision

## Problem
An AI agent can produce detailed geometry from a single image. Directing it at a **specific area** for delicate work is where it breaks down, and architectural detailing is the clearest case (cornices, mullions, stair nosings, joints). The current workflow:

1. Rotate to a view and take a screenshot
2. Mark it up in another tool
3. Write a careful description ("the second window from the left, the upper sill, make the drip 20 mm deeper")
4. Paste it into a chat and hope the agent maps pixels back to the right geometry

Every step loses information the modeler already has.

## Goal
Make **communication with the agent** cheap and precise. The modeler is where you point. The agent receives structured, unambiguous context.

## Principles
1. **Point, don't describe.** A click on geometry beats a sentence, and a registered drawing beats a screenshot.
2. **Context is structured, not just visual.** Every packet carries the camera, entity references, world coordinates and units, plus an image for visual grounding.
3. **Scope is explicit and enforced.** The agent can only edit what you scoped.
4. **The agent proposes and the human disposes.** Changes arrive as previews and are accepted one at a time, each as one undo step.
5. **The agent checks its own work.** It can render views and sections and compare them against the references before showing you a result.
6. **Knowledge stays in the model.** Semantic tags, pins and threads are saved inside the .skp/.3dm file.
7. **Mechanisms over polish.** First get grounding right, then UI.

## Core features (target)
| Area | Feature |
|---|---|
| Pointing | 3D pins (point, normal, entity), markup strokes projected onto geometry, selection as scope, "like *that*" pointing by example |
| References | CAD/elevation registered to a face by 2 points, photo/render camera match, profile sketch on a section plane, crop-to-material |
| Output | Ghost proposals, accept/reject, per-pin threads and change log |
| Semantics | Tags (`role`, `lod`, `family`), high-level op library, LOD knob |
| Parametric (Rhino) | Agent writes Grasshopper definitions with sliders, and the user tunes them without re-prompting |

## Non-goals (for now)
- Building our own modeling kernel or viewport
- Rendering or visualization beyond what the agent needs for verification
- Cloud collaboration or multi-user editing
- BIM or IFC semantics (maybe later through tags)

## Primary user
An architect or designer who models in SketchUp daily on Windows, at first the project author.
