# 0001: Host strategy: SketchUp first, Rhino/Grasshopper second

- **Status:** accepted
- **Date:** 2026-11-07

## Context
The primary user models in SketchUp on Windows every day, and Rhino is available. The value of the project is the interaction layer (pointing, references, proposals), not a new modeler.

## Decision
- Build **host adapters** for existing modelers, not a standalone app.
- **SketchUp** is the first host. It matches the daily workflow, and its Ruby API covers picking, camera, image export, attribute dictionaries and undo.
- **Rhino 8 + Grasshopper** is the second host. It offers a different interaction: the agent writes **parametric definitions** with sliders instead of fixed geometry. This suits repetitive and rule-based elements (facade panels, louvers, stairs). It also has better geometry (NURBS, reliable booleans) and clean preview conduits.
- Blender and a standalone web app were considered and set aside, because they don't match the user's workflow.

## Consequences
- The protocol must not depend on any one host (meters, Z-up, opaque refs).
- Host code can only be tested on Windows inside the apps, so it must stay thin.
- SketchUp's limits (mesh-only geometry, single-threaded Ruby, fragile booleans) shape the op library. Some ops will be Rhino-only.
