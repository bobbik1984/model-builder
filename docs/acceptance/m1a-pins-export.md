# Acceptance: M1a, pins + export

Records are appended, never rewritten. Each run states **who/what ran it**, **how** (automated vs. manual UI), the SketchUp build, and the result.

## Criteria

| ID | Criterion | How verified |
|---|---|---|
| C1 | Extension loads from the repo via the dev loader; menu + toolbar appear | Manual (UI); auto run checks loading only |
| C2 | Clicking a face drops a numbered marker at the clicked spot; Backspace removes the last; Clear Pins removes all | Manual |
| C3 | Pin world point is correct to ≤ 0.01 mm on the calibration scene (rotated, nested, scaled, mirrored instances) | Auto (self-test) + manual spot check |
| C4 | Pin normal is the correct world-space unit normal, including mirrored and non-uniformly scaled instances | Auto + manual |
| C5 | Each pin carries the hit entity ref, the innermost instance (name/definition) and the full instance path root→face | Auto + manual |
| C6 | Export writes a schema-valid packet and a PNG whose size equals `camera.viewport_px`; `screen_px` lands on the pin in that PNG | Auto + `check_packet.py` |
| C7 | Export is one click (toolbar/menu), and the result dialog shows the paths | Manual |

## Calibration scene (expected values, meters)

Built by **Dev → Build Calibration Scene** or by the self-test (`hosts/sketchup/src/model_builder/dev/`). Use an empty model (File → New).

| Object | Path | Transform | World extent |
|---|---|---|---|
| Cube_A | group | translate (10,10,0) | x 10–11, y 10–11, z 0–1 |
| B1 | component "MB Block 0.5m" | translate (12,10,0) · rotate Z 90° | x 11.5–12, y 10–10.5, z 0–0.5 |
| Outer › B2 | group › component | Outer (10,13,0); B2 (1,0,0) · scale X 2 | x 11–12, y 13–13.5, z 0–0.5 |
| B3 | component | translate (14,10,0) · scale X −1 (mirror) | x 13.5–14, y 10–10.5, z 0–0.5 |
| W1 | component "MB Wedge 1m" | translate (16,10,0) · scale X 2 | x 16–18, y 10–11, z 0–1; slope z = 1 − (x−16)/2, normal (0.4472, 0, 0.8944) |

Handy manual checks: Cube_A top corner (11,11,1) with endpoint snap; W1 slope normal ≈ (0.447, 0, 0.894) (a naive transform would give (0.894, 0, 0.447)); the B3 +X face normal must be (1,0,0), not (−1,0,0).

---

## Run A1: automated, 2026-11-08: PASS (C3, C4, C5, C6; C1 load only)

- **Ran by:** Claude Code (development agent), unattended: `SketchUp.exe -RubyStartup hosts/sketchup/dev/autorun_selftest.rb`
- **Build:** SketchUp 24.0.553, extension 0.1.0, protocol 0.2, UI scale 1.5, viewport 2136×1652
- **Not exercised:** mouse clicks, InputPoint snapping, marker drawing, toolbar/menu visibility, dialogs (C2, C7)

| Case | Got point | Got normal | Path | Result |
|---|---|---|---|---|
| Cube_A top | (10.5, 10.5, 1) | (0,0,1) | Cube_A | PASS |
| Cube_A side −Y | (10.25, 10, 0.75) | (0,−1,0) | Cube_A | PASS |
| B1 top (rot 90°) | (11.75, 10.25, 0.5) | (0,0,1) | B1 | PASS |
| B1 side −Y (rot 90°) | (11.6, 10, 0.25) | (0,−1,0) | B1 | PASS |
| B2 top (nested, scaled) | (11.5, 13.25, 0.5) | (0,0,1) | Outer › B2 | PASS |
| B2 side +X (nested, scaled) | (12, 13.25, 0.25) | (1,0,0) | Outer › B2 | PASS |
| B3 top (mirrored) | (13.75, 10.25, 0.5) | (0,0,1) | B3 | PASS |
| B3 side +X (mirrored) | (14, 10.25, 0.25) | (1,0,0) | B3 | PASS |
| W1 slope (non-uniform) | (17, 10.5, 0.5) | (0.447214, 0, 0.894427) | W1 | PASS |
| W1 back face −X | (16, 10.75, 0.5) | (−1,0,0) | W1 | PASS |

Export: `check_packet.py` → schema OK, PNG 2136×1652 = viewport_px, no problems. The pins' `screen_px` were drawn onto the PNG and each landed on its face (p10 on the hidden back face, correctly `front_facing: false`). B1/B2/B3 report the same face ref `su:34000` (shared definition), and only the path tells them apart, as designed.

---

## Run A2: automated probe of a real model, 2026-11-08: PASS (C3, C4, C5, C6 on real data)

- **Ran by:** Claude Code, unattended: `MB_PROBE_MODEL=<copy of samples/models/20261020_skylight_model.skp>` + `SketchUp.exe -RubyStartup hosts/sketchup/dev/autorun_probe.rb`. A copy was used, and the original was never opened.
- **Model:** skylight model, units mm, 78 definitions, nesting up to 8 levels (`group > group > component:Curtain Wall_Half > component:sliding_door.dwg > group > face`). Saved camera, viewport 1920×1520.
- **Method:** 9×7 grid of screen "clicks" through `Capture.from_screen` (the Pin tool's code path), each with and without InputPoint snapping. Every capture was checked against independent values: `Sketchup::InstancePath#transformation`, the world face plane from transformed vertices, front side via transformed point+normal offset, and the screen round-trip.
- **Result:** 31 hits / 32 misses (sky). **41/41 checks passed** (31 face, 8 point-snap, 2 edge-snap). Screen round-trip error 0 px. 9 distinct instances. 12 pins exported. `check_packet.py`: schema OK, PNG = viewport, no problems. Pins overlaid on the PNG land on their surfaces.
- **Observations for agents:**
  - Most groups in this model are **unnamed**, so `path_detail` gives correct identity but little meaning (`group:su:1842024 > group:su:1838808 > face`). Candidate improvement: add the SketchUp tag (layer) and material to `path_detail`/`instance`.
  - Pins p2/p3 on the curved brown walls are `front_facing: false`: those faces show their back side to the camera (typical of DWG imports). This is reported correctly.
- **Still not exercised:** real mouse clicks, marker drawing, toolbar/menu visibility, dialogs (C1 UI, C2, C7).

---

## Run A3: automated, markup + handoff, 2026-11-08: PASS

- **Ran by:** Claude Code, unattended `autorun_selftest.rb` with `MB_TEST_REFS` = the two real skylight images (paths with Chinese characters). Extension 0.2.0, protocol 0.3, SketchUp 24.0.553.
- **Self-test:** 10/10 again (no regression).
- **Markup test (`dev/markup_test.rb`):** 2 pins with notes (one in Chinese, preserved), polygon outline on Cube_A top → area 0.64 m², perimeter 3.2 m, centroid (10.5, 10.5, 1.0), normal (0,0,1), touches `group:Cube_A`; a line touching Cube_A and B3; 2 references copied (sizes match the originals); task message; `brief.md` written; `check_packet.py` → no problems.
- **Finding:** the first attempt exported the "annotated" image via `write_image` with the overlay enabled. Pixel diff against the clean image was **empty**, so write_image ignores overlays. Fixed by drawing markup into the image ourselves (`raster.rb`). After the fix, the diff is confined to the drawn marks, which sit on the right faces when inspected.
- **Not exercised:** the Outline/Pin tools by mouse, note/reference/export dialogs, the overlay being visible on screen.

---

## Run A4: automated, export checks (plugin 0.3.0, protocol 0.4), 2026-11-08: PASS

- **Ran by:** Claude Code, unattended `autorun_selftest.rb`, `MB_TEST_REFS` = skylight panels PNG (1376 px) + hero render JPG (5000 px). Then `autorun_probe.rb` on a copy of the skylight model.
- **Self-test:** 10/10. **Real model probe (A2 rerun):** 41/41, no regression. Warnings on the real model: p2/p3 on faces seen from behind, which is correct.
- **Markup test, new checks:**
  - **Crossings:** S3 (a plane line drawn through Cube_A) gets a "passes through group:Cube_A" warning, and S1 (on the top face) gets none. S2 (Cube_A top → B3 top) is also flagged; it really does cut through Cube_A's corner.
  - **Curved surfaces:** S4 (top → side) has `point_normals` [(0,0,1), (0,−1,0)], spread 45°, and a curved warning.
  - **CAD:** an unconfirmed CAD import (30° rotated) is warned about, and `mark_registered` sticks.
  - **Notes and contents:** the project notes are found next to the saved model. Pin `instance.contents` = 6 faces for Cube_A.
  - **Occlusion:** with an independent camera along +X, a front-face point is visible, a back-face point is hidden, and an open-air point is visible.
  - **Previews:** a synthetic 3000 px image comes back the right way up (red top, blue bottom) at 1600 px. The real 5000×3330 render gets a 1600×1066 preview, inspected visually.
- **Finding:** the first preview was upside down. `Sketchup::ImageRep` rows are top-down, not bottom-up like BMP. Fixed, and the synthetic test now guards it.
- **Not exercised:** the Confirm CAD Placement dialog, and the Outline tool snapping to DWG lines by mouse (F17).

---

## Run A5: automated, panel back end + real agents (plugin 0.4.0), 2026-11-08: PASS

- **Ran by:** Claude Code, `hosts/sketchup/dev/autorun_agent_test.rb` in a **separate** SketchUp instance; the user's own SketchUp stayed open and untouched.
- **Marks:** after deleting p1 and s1, the remaining ids are p2, s2 and new marks become p3, s3 (no reuse). Screen picking (`MarkPick`) finds p2 and the s2/s3 segment.
- **References:** a DWG file and an in-model reference (`cad_in_model`, `model_ref`) export correctly. `Panel.state` builds and is valid JSON.
- **Detection on this machine:** Claude Code ✓, Antigravity IDE ✓ (`antigravity-ide.cmd chat -m agent`), DeepSeek key ✓ (`DEEPSEEK_API_KEY`); Codex, Gemini CLI, Anthropic and OpenAI keys: not present.
- **Live link ("Any agent" task):**
  - Two scripts were sent through `tools/mb_exec.py` at the same moment.
  - The good one built a box, wrote a render and reported `created: 1`.
  - The failing one (`raise 'boom'`) was **rolled back**, leaving no empty group.
  - Reject removed the box. The conversation recorded user, script, script and reply events.
- **DeepSeek API (`deepseek-chat`):** a "1 m cube at (0,0,20)" task finished in 21 s and 8k tokens. The cube was exactly right, in a proposal group on `MB_Proposal`; plan and report were written. It wrote the plan after building, so the system prompt now requires the plan first.
- **Claude Code headless:** a "2 m cube at (30,0,0)" task finished in 40 s for $0.22 (155k tokens, mostly cache).
  - It wrote the plan, ran its script through the live link, checked the bounds, then wrote the report. The cube was exactly right.
  - The first attempt was denied: Windows Claude Code runs commands through its **PowerShell** tool, and only `Bash` was allowed. The agent reported this honestly instead of working around it. Fixed (`--allowedTools Bash,PowerShell,…`).
- **Bugs found and fixed:**
  - Mixed `\`/`/` paths made `Dir.glob` miss the inbox. Task paths are normalised now.
  - Two `mb_exec` calls could get the same number. Names are now time + pid.
  - Launching can pump the message loop, so Send was re-entrant. Now guarded.
  - The export pointer assumed every reference is a file.
- **Not exercised:** the panel's HTML UI by a human, approval dialogs (tests used auto-approve), the Antigravity/Codex/Gemini launchers, the Anthropic/OpenAI API paths, and right-click delete by mouse.

---

## Run A6: automated, AI Build flow with the plan gate (plugin 0.5.0), 2026-11-08: PASS

- **Why:** in the user's first real use of 0.4 (DeepSeek, "在这里依照参考图添加设备的体块模型" — add massing blocks for the equipment here, per the reference image), the agent ran 39 scripts in 14 minutes and **every script raised an approval dialog**. It could not see the reference image (DeepSeek is text-only), read nested-group bounds without transforms (wrong world positions), hit 40 steps and used **695k tokens** without a plan.
- **What changed:**
  - The AI Build tool and dialog.
  - Planning is read-only: scripts are always rolled back, with no prompts.
  - Plan → Approve/Revise → build without interruption, with a single status line.
  - `ModelBuilder::Kit` helpers, and the **surroundings** of each mark in the brief.
  - A warning when the chosen model cannot see the attached images.
  - Step and token limits per stage (plan 15, build 30, 400k tokens).
- **Ran by:** Claude Code, `hosts/sketchup/dev/autorun_agent_test.rb` in a separate SketchUp instance.
- **Back end:**
  - Mark ids stay p2, p3, s2, s3 after deletes, and the dialog state lists them.
  - `Kit.world_bounds` of the nested, scaled B2 is x 11–12, y 13–13.5 (world, correct).
  - `Kit.around` puts Cube_A first, as containing the point. `Kit.level_at` gives floor 1.0 and an open sky above.
  - Pins carry `surroundings`.
- **Manual flow:**
  - A planning-stage script that tried to build was rolled back: `mode: read_only`, 0 created, model unchanged.
  - plan.md → `plan_ready` → Approve → `building`.
  - The build script created the box; a failing script rolled back.
  - reply.md → `done`; Reject removed the box. A script after the end is refused.
- **DeepSeek (`deepseek-chat`, text only):** plan in 7.6k tokens (nothing built while planning). After Approve: 2 scripts, exact cube (0,0,20)→(1,1,21), report. **16k tokens in total**, against 695k before.
- **Claude Code:**
  - The plan checked the surroundings (clear within 6 m) and built nothing.
  - After Approve, the **resumed session** (`--resume`) built the exact cube (30,0,0)→(32,2,2) in 3 scripts, with a report.
  - 65 s, 259k tokens (mostly cache), $0.48.
- **Not exercised by a human:** the AI Build tool with the mouse (click again for a pin, back to the start for an outline), the dialog HTML, ＋ Add API, Revise, Antigravity.

---

## Manual test M2 (handoff): to be done by a human in SketchUp

On the skylight model (or a copy):

```
Date / tester / build:
H1  Toolbar shows 5 buttons (pin, outline, reference, clear, export):   PASS / FAIL
H2  Outline Tool: click around the atrium rim (snap to rim edges; press P if you must click over the void),
    click the first point to close -> note prompt -> orange outline S1 stays visible after switching tools:  PASS / FAIL
H3  Pin Tool: pin on the atrium rim/edge -> note "atrium roof missing" -> red bubble 1:   PASS / FAIL
H4  Attach Reference Image twice: 20261024_Skylight_panels.png (render), detail_sketch.png (sketch), with notes:  PASS / FAIL
H5  Export: type the task, choose LOD -> dialog lists brief/packet paths:   PASS / FAIL
H6  Annotated PNG shows S1 and pin 1 in the right place; brief.md reads correctly:   PASS / FAIL
H7  python tools\check_packet.py -> "No problems found"; outline area/extent plausible for the atrium:   PASS / FAIL
Notes:
```

---

## Manual test M1: to be done by a human in SketchUp

Copy this block, fill it in, and append it as "Run M1".

```
Date / tester / SketchUp build:
C1  Toolbar "Model Builder" visible with 3 buttons; Extensions > Model Builder menu present:   PASS / FAIL  notes:
    (File > New, then Extensions > Model Builder > Dev > Build Calibration Scene)
C2  Pin Tool: click Cube_A top, B1 side, W1 slope -> red numbered bubbles 1,2,3 + blue normal ticks:   PASS / FAIL
    Backspace removes #3; Clear Pins removes all; orbiting (middle mouse) keeps markers attached:  PASS / FAIL
C3  Snap to Cube_A top corner (endpoint inference shown) -> status bar shows (11.000, 11.000, 1.000):  PASS / FAIL
C4  Export; check_packet.py shows W1 slope normal (0.4472, 0, 0.8944) and B3 +X normal (1,0,0):  PASS / FAIL
C5  check_packet.py path lines: "group:Outer > component:B2 > face:..." for a pin on B2:  PASS / FAIL
C6  check_packet.py: "No problems found":  PASS / FAIL
C7  Export was one click; dialog showed paths; "Open folder" worked:  PASS / FAIL
Are the red pin markers visible in the exported PNG?  YES / NO   (records whether write_image includes tool drawing)
Real model: 3 pins on different elements of one of your own models, export, check_packet.py. Do points/paths look right?  notes:
Anything odd (log: %LOCALAPPDATA%\ModelBuilder\logs\model_builder.log):
```
