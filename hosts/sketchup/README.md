# SketchUp host adapter

A Ruby extension that does capture (pins, strokes, selection, camera, images), executes ops inside proposals, previews them, and stores tags, pins and threads in the model.

## Planned layout
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
