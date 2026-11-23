# SketchUp host adapter

A Ruby extension that does capture (pins, strokes, selection, camera, images), executes ops inside proposals, previews them, and stores tags, pins and threads in the model.

## Current layout (M1a). Status: see `docs/handover.md`
```
hosts/sketchup/
  src/model_builder.rb           # SketchupExtension registration (root of the .rbz)
  src/model_builder/
    main.rb                      # load order, commands, menu + toolbar, ModelBuilder.reload
    version.rb, log.rb           # VERSION / PROTOCOL_VERSION; file log + ModelBuilder.guard
    units.rb                     # inch <-> meter (the ONLY place)
    refs.rb                      # entity -> "su:<persistent_id>", kinds, path details
    geometry.rb                  # path transforms, world normals, world bounds
    capture.rb                   # screen/ray -> pin data (raytest + InputPoint snapping)
    pin_store.rb                 # in-memory pins for the active model
    markup_store.rb              # outlines, reference images, task message (per model)
    markup_draw.rb, overlay.rb   # drawing; Overlay keeps markup visible with any tool (SU 2023+)
    checks.rb                    # export-time checks: visibility, crossings, curved outlines, CAD registration
    mark_pick.rb                 # pick a pin/outline on screen (edit/delete one)
    agents.rb                    # agent programs + API providers (keys from user env vars), launchers
    tasks.rb                     # a Send: task folder, prompt.md, conversation (thread.jsonl), polling
    kit.rb                       # helpers for agent scripts (world bounds, around, ray, level, proposal, box…)
    prompts.rb                   # plan / build / revise instructions for agents
    tools/ai_build_tool.rb       # AI Build: click-again = pin, back-to-start = outline
    live_link.rb                 # run agent scripts in the open model (planning: read-only; build: one undo step)
    api_agent.rb                 # direct-API tool loop (OpenAI-compatible / Anthropic)
    ui/panel.rb, ui/panel.html   # the Model Builder panel (HtmlDialog)
    packet.rb, brief.rb          # context packet; Markdown brief
    raster.rb, exporter.rb       # burn markup into the screenshot; write the session folder
    tools/pin_tool.rb            # the Pin tool (with notes)
    tools/outline_tool.rb        # the Outline tool (polygon/line, plane lock)
    dev/calibration_scene.rb     # known-geometry test scene
    dev/self_test.rb             # ray-cast self-test against expected values
    dev/model_probe.rb           # grid-click probe of any model, checked via InstancePath
    dev/markup_test.rb           # notes/outlines/references/annotated image/brief test
    icons/*.svg
  dev/autorun_selftest.rb        # unattended self-test via SketchUp.exe -RubyStartup (not packaged)
  dev/autorun_probe.rb           # unattended probe of MB_PROBE_MODEL (not packaged)
```

## Planned layout (full)
```
hosts/sketchup/src/
  model_builder.rb               # extension registration (SketchupExtension)
  model_builder/
    main.rb                      # menus, toolbar, ModelBuilder.reload
    units.rb                     # inch <-> meter conversion (the ONLY place)
    refs.rb                      # entity <-> "su:<persistent_id>" + entity paths
    link.rb                      # TCP client, non-blocking, polled by UI.start_timer
    packet.rb                    # build context packets
    tools/pin_tool.rb            # click → pin (pick_helper / InputPoint)
    tools/markup_tool.rb         # strokes, ray-cast onto geometry
    ops/                         # one file per op
    proposals.rb                 # ghost preview, accept/reject, single undo step
    panel/                       # HtmlDialog (html/js/css)
```

## Notes
- Everything lives inside `module ModelBuilder`, with no globals.
- Use `persistent_id` for refs, because it stays stable across save/reopen.
- Wrap timer callbacks in `rescue => e` and log to a file, otherwise errors vanish silently.
- See `../../docs/dev-setup-windows.md` for the dev loader.
