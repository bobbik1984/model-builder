# Samples

Test models, reference images and agent results used in the studies and acceptance runs. Binaries are stored with **Git LFS** (`.gitattributes`); run `git lfs install` once before cloning.

> These files come from a real project (Longhua North Station commercial project, Shenzhen) and were added by the project owner for development and testing. Check with the owner before reusing them outside this repo.

## Models (`models/`)

| File | Used in |
|---|---|
| `20261020_skylight_model.skp` | Podium roof with atrium openings. Runs A2, A4 (probe 41/41); study `docs/studies/atrium-roof-build.md` |
| `20261020_skylight_model_roof_proposal_v2.skp` | The same model with the agent-built atrium skylight roof (proposal group, tag `MB_Proposal`) |
| `20260330_Massing.skp` | Mall massing (podium + twin towers + context). Studies `park-handoff.md`, `facade-handoff.md` |
| `20260330_Massing.project.md` | Project notes for the massing model (facts, decisions, open questions) |
| `Site Plan.dwg` | North park + surface parking site plan (DWG; **not** in the mall's frame, see the project notes) |
| `siteplan_cad.jpg` | Colour-coded site plan (legend for the DWG) |
| `aerial.jpg` | As-built aerial looking north over the park |
| `20260710_Hero Shot_01.jpg` | Rendering from the park towards the mall |
| `20250403_东南入口.png` | SE entrance rendering (pebble aluminium facade; 5000 px, 26 MB) |

## References (`references/`)

| File | Used in |
|---|---|
| `skylight/20261024_Skylight_panels.png` | Atrium skylight rendering (diagrid, two-tone triangular panels) |
| `skylight/detail_sketch.png` | Skylight section sketch (30 mm fire-rated panel, aluminium ceiling, wrapped beams, sprinkler) |
| `roof_equipment/20261106_roof_equipment_ref_1.png` | The user's first real AI Build task ("在这里依照参考图添加设备的体块模型" — add massing blocks for the equipment here, per the reference image; DeepSeek, 2026-11-08) |
| `20261108_UI_Design.PNG`, `20261108_dialog.PNG` | The user's screenshots of plugin 0.3/0.4: the old toolbar, and the per-script approval dialog that interrupted the first real run (fixed in 0.5) |

## Agent results (`results/`)

| File | What |
|---|---|
| `20260330_Massing_with_siteplan.skp` | Massing model + `Site Plan.dwg` imported with its original coordinates (the designer's setup for the park task) |
| `20260330_Massing_park_proposal.skp` | Park + surface parking built by a clean-context agent (`docs/studies/park-handoff.md`) |
| `20260330_Massing_park_facade_proposal.skp` | Plus the pebble facade panels, LED mesh and billboard (`docs/studies/facade-handoff.md`) |
