# Rhino / Grasshopper host adapter (M5)

Not started. It speaks the same protocol as the SketchUp adapter.

- `plugin/`: Rhino 8 Python 3 (RhinoCommon). It holds the pin and markup tools, `DisplayConduit` for proposal previews, user text for tags, and the socket client.
- `grasshopper/`: components and templates for the parametric mode. The agent writes a GH Python definition with exposed inputs (sliders), and the user tunes them without re-prompting. The result is baked into the scoped layer on accept.

Refs use the form `rh:<object guid>`. Rhino model units must be converted to meters at the boundary.
