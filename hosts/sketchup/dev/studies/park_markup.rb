require 'json'

# The "designer" marks up the task with the plugin's own stores (what the Pin /
# Outline / Attach Reference / Export UI would produce), then exports.
module MBScript
  U = ModelBuilder::Units
  SRC = 'D:/OneDrive/Learning/Code/Gemini/model-builder/samples/models/'

  def self.edges_on(ents, tr, layer, out, depth = 0)
    ents.each do |e|
      if e.is_a?(Sketchup::Edge) && e.layer.name == layer
        out << [e.start.position.transform(tr), e.end.position.transform(tr)]
      elsif e.respond_to?(:definition) && depth < 6
        edges_on(e.definition.entities, tr * e.transformation, layer, out, depth + 1)
      end
    end
  end

  # chain segments into the longest closed/open polyline
  def self.chain(segs)
    key = ->(p) { [p.x, p.y].map { |v| (v * 25.4).round } } # mm grid
    adj = Hash.new { |h, k| h[k] = [] }
    segs.each_with_index { |(a, b), i| adj[key.(a)] << [i, b]; adj[key.(b)] << [i, a] }
    used = {}
    best = []
    segs.each_index do |i0|
      next if used[i0]

      a, b = segs[i0]
      used[i0] = true
      line = [a, b]
      loop do
        nxt = adj[key.(line[-1])].find { |i, _| !used[i] }
        break unless nxt

        used[nxt[0]] = true
        line << nxt[1]
      end
      best = line if line.size > best.size
    end
    best
  end

  def self.dp(pts, tol)
    return pts if pts.size < 3

    a = pts.first
    b = pts.last
    return [a, b] if a.distance(b) < 1e-6

    d = pts[1..-2].map { |p| p.distance_to_line([a, b - a]) }
    i = d.each_with_index.max[1] + 1
    return [a, b] if d.max < tol

    dp(pts[0..i], tol)[0..-2] + dp(pts[i..], tol)
  end

  def self.plane_hits(n) = Array.new(n)

  def self.run(model, out_dir)
    ModelBuilder::PinStore.clear
    ModelBuilder::MarkupStore.clear_strokes
    ModelBuilder::MarkupStore.clear_references
    dwg = model.entities.find { |e| e.respond_to?(:definition) && e.name.start_with?('Site Plan') }
    raise 'DWG instance not found' unless dwg

    view = model.active_view
    # Camera: from above the park looking south at the mall (like the hero shot r3)
    view.camera = Sketchup::Camera.new(U.to_point([250, 560, 210]), U.to_point([170, 250, 0]), Geom::Vector3d.new(0, 0, 1), true, 55)

    # S1: site red line, clicked at its corners (snap to DWG linework)
    segs = []
    edges_on(dwg.definition.entities, dwg.transformation, '00_SITE_BOUNDARY', segs)
    ring = chain(segs)
    ring.pop if ring.size > 2 && ring.first.distance(ring.last) < 0.01
    corners = dp(ring, U.to_inches(3.0))
    s1 = ModelBuilder::MarkupStore.add_stroke(model, 'polygon', corners, Array.new(corners.size, 'point'), plane_hits(corners.size),
                                              'Site red line: north park + surface car park. Build everything inside per the Site Plan DWG (already imported, registered) and the colour legend of r1.')
    # S2: the road between mall and park (clicked along the road centre)
    road = [[45, 203, 0], [200, 203, 0], [392, 203, 0]].map { |p| U.to_point(p) }
    ModelBuilder::MarkupStore.add_stroke(model, 'line', road, %w[plane plane plane], plane_hits(3),
                                         'Road between the mall and the park: carriageway + pavements at grade, per DWG road edges.')
    # S3: the pedestrian bridge deck from the west (station side) into the park
    bridge = [[-8, 300, 0], [30, 300, 0], [66, 300, 0]].map { |p| U.to_point(p) }
    ModelBuilder::MarkupStore.add_stroke(model, 'line', bridge, %w[plane plane plane], plane_hits(3),
                                         'Pedestrian bridge over the west road into the park (DWG layer 40_BRIDGE_DECK, stairs 41_RAMP_STAIRS). Deck about level with the mall bridge (+5..6 m).')

    # Pins on real geometry (ray down onto the mall podium)
    down = Geom::Vector3d.new(0, 0, -1)
    p1cap = ModelBuilder::Capture.from_ray(model, [U.to_point([95, 190, 300]), down])
    if p1cap
      p1 = ModelBuilder::PinStore.add(model, p1cap)
      p1.data[:note] = 'Existing mall (towers + podium): context only, do not modify. The park faces this north side.'
    end
    p2cap = ModelBuilder::Capture.from_ray(model, [U.to_point([-10, 180, 300]), down])
    if p2cap
      p2 = ModelBuilder::PinStore.add(model, p2cap)
      p2.data[:note] = 'Mall bridge level here (+5..6 m): the new west bridge deck should connect at a similar level.'
    end

    refs = [
      ['siteplan_cad.jpg', 'cad', 'Colour-coded site plan (north up). Legend: dark green = planting/roof greening, light green = grass parking bays, beige = paths/paving, grey = carriageway, blue = sports courts. Same linework as the imported DWG.'],
      ['aerial.jpg', 'photo', 'As-built photo from the mall tower looking north over the park: tree density, parking rows, amphitheatre lawn, pavilions.'],
      ['20260710_Hero Shot_01.jpg', 'render', 'Target view from the park towards the mall: park in the foreground must read like this (green, paths, glass pavilions).'],
      ['20250403_东南入口.png', 'render', 'Mall SE entrance facade, context only (not part of this task).']
    ]
    refs.each { |f, k, n| ModelBuilder::MarkupStore.add_reference(model, SRC + f, k, n) }

    ModelBuilder::MarkupStore.set_task(model, <<~MSG.strip, 'massing')
      Build the north park and its surface car park next to the existing mall, so the mall and the park can be viewed together (like r3/r2). Massing level, not detailed.
      Use the Site Plan DWG that is already imported and registered in the model (component "Site Plan (DWG, registered)"; layers 00_SITE_BOUNDARY, 10_ROAD_EDGE, 11_PARKING_BAYS, 12_TRAFFIC_ARROWS, 30_GREEN_EDGE, 32_CURB_EDGE, 40_BRIDGE_DECK, 41_RAMP_STAIRS, 42_AMPHITHEATRE, 43_PAVILION, REV_COURT_*, P34_*).
      Components: ground surfaces inside S1 coloured per r1 legend (planting, grass parking bays, paving/paths, driving aisles, sports courts); the road S2; the west bridge S3 with stairs; amphitheatre steps; small pavilions; simple trees in the planted areas. Put the new work in its own group/tag. Do not modify the mall (pins 1-2).
    MSG

    exp = ModelBuilder::Exporter.export(model)
    File.write(File.join(out_dir, 'export.json'), JSON.pretty_generate(exp))
    "s1=#{corners.size}pts area=? pins=#{ModelBuilder::PinStore.pins(model).size} packet=#{exp[:packet_path]}"
  end
end
