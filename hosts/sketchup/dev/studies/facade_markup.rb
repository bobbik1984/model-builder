require 'json'

# Designer marks up the facade task by "clicking" screen pixels (same code path as the tools).
module MBScript
  U = ModelBuilder::Units
  CAM = JSON.parse(File.read(File.join(__dir__, 'cam.json')))
  DIR = __dir__.tr('\\', '/')

  def self.click(view, x, y)
    ModelBuilder::Capture.from_screen(view, x, y)
  end

  def self.pin(model, view, x, y, note)
    cap = click(view, x, y) or raise "pin click at #{x},#{y} hit nothing"
    p = ModelBuilder::PinStore.add(model, cap)
    p.data[:note] = note
    p
  end

  def self.run(model, out_dir)
    ModelBuilder::PinStore.clear
    ModelBuilder::MarkupStore.clear_strokes
    ModelBuilder::MarkupStore.clear_references
    view = model.active_view
    view.camera = Sketchup::Camera.new(U.to_point(CAM['eye']), U.to_point(CAM['target']), Geom::Vector3d.new(0, 0, 1), true, CAM['fov'])

    pin(model, view, 1100, 620, 'Pebble aluminium panels on all curved white podium volumes like this one: horizontal strips, staggered panel lengths, 4-5 tones cream to gold, darker and denser towards the bottom (r1, r2).')
    pin(model, view, 1300, 960, 'Storefront glazing + dark fins at the base: keep as is, panels start above it.')
    pin(model, view, 1600, 380, 'Vertical slot between the two volumes above the entrance: perforated LED media mesh, not pebble (r1, r2).')

    # Outline: LED billboard on the right volume
    px = [[1690, 260], [1915, 240], [1915, 600], [1700, 630]]
    caps = px.map { |x, y| click(view, x, y) }
    if caps.all?
      ModelBuilder::MarkupStore.add_stroke(model, 'polygon', caps.map { |c| c[:point] }, caps.map { |c| c[:data][:snap] || 'face' },
                                           caps.map { |c| { path: c[:data][:entity][:path], detail: c[:data][:path_detail] } },
                                           'Large LED billboard set into the pebble cladding on this volume (r1 right side). Approximate extent.')
    end

    refs = [
      ["#{DIR}/ref_panel_closeup.jpg", 'render', 'GOVERNS THE PANEL LOOK. Crop of r2: strip heights, panel stagger, colour mix, feature cut-out windows, LED mesh slot.'],
      ["#{DIR}/ref_se_entrance.jpg", 'render', 'SE entrance, roughly the same view as my screenshot: which volumes get pebble, the LED slot, the billboard, glazed base.'],
      ["#{DIR}/ref_hero.jpg", 'render', 'Overall look from the park (north): pebble on lower volumes, planted terraces above. Context only for this task.']
    ]
    refs.each { |f, k, n| ModelBuilder::MarkupStore.add_reference(model, f, k, n) }

    ModelBuilder::MarkupStore.set_task(model, <<~MSG.strip, 'schematic')
      Apply the pebble aluminium facade panels to the mall podium as in the renderings (r1 governs the look). Not super detailed, but the panel pattern should read in renders.
      Scope: the external curved podium volumes (the white "pebble" masses, above the glazed storefront base, up to the terrace edges) on all sides. The model already tags facade lines by type (tags "A3-ACME-EXTERNAL FACADE LINE-ALUMINUM PEBBLE", "...GLAZING", "...PERFORATED", "...BALUSTRADE EDGE TYPE A/B/C"); use them if they help to decide where pebble goes.
      Also: LED media mesh in the slot (pin 3), LED billboard (outline S1). Keep the base glazing (pin 2) and the towers unchanged. Put new work in its own group/tag; don't modify the existing mall geometry, the park, or the DWG.
    MSG

    exp = ModelBuilder::Exporter.export(model)
    "pins=#{ModelBuilder::PinStore.pins(model).size} strokes=#{ModelBuilder::MarkupStore.strokes(model).size} packet=#{exp[:packet_path]}"
  end
end
