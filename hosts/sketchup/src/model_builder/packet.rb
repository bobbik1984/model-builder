require 'time'

module ModelBuilder
  # Builds a context packet (protocol/schemas/context_packet.schema.json).
  # Everything returned here is plain JSON data in meters.
  module Packet
    MAX_SELECTION = 200

    # view_paths: [{kind:, path:}] ; references: [{id:, kind:, file:, source:, note:, preview:}]
    def self.build(model, view, packet_id:, session_id:, view_paths:, references: [], extra_warnings: [])
      crossings = {}
      strokes = MarkupStore.strokes(model).map do |s|
        crossings[s.id] = Checks.crossings(model, s.points, s.kind == 'polygon')
        stroke_json(s, view)
      end
      packet = {
        protocol_version: PROTOCOL_VERSION,
        packet_id: packet_id,
        session_id: session_id,
        created_at: Time.now.iso8601,
        host: {
          app: 'sketchup',
          version: Sketchup.version.to_s,
          model_units: Units.display_unit(model)
        },
        model: model_info(model),
        project_notes: project_notes(model),
        message: MarkupStore.message(model),
        lod: MarkupStore.lod(model),
        camera: camera(view),
        views: view_paths,
        # Scope is not implemented until M2; the selection is reported as-is.
        scope: { mode: 'none' },
        selection: selection(model),
        pins: PinStore.pins(model).map { |pin| pin_json(pin, view) },
        strokes: strokes,
        references: references.map do |r|
          { id: r[:id], kind: r[:kind], file: r[:file], source: r[:source], model_ref: r[:model_ref], name: r[:name],
            preview: r[:preview], size_px: r[:size_px], registration: { type: 'none' }, note: r[:note] }.compact
        end,
        cad_imports: Checks.cad_imports(model)
      }
      packet[:warnings] = Checks.warnings(packet, crossings) + extra_warnings
      packet.delete(:message) if packet[:message].to_s.empty?
      packet.delete(:project_notes) unless packet[:project_notes]
      %i[selection strokes references cad_imports warnings].each { |k| packet.delete(k) if packet[k].empty? }
      packet
    end

    def self.screen_px(view, pt)
      sc = view.screen_coords(pt)
      [sc.x.to_f.round(1), sc.y.to_f.round(1)]
    end

    def self.in_frame?(view, pt)
      cam = view.camera
      in_front = !cam.perspective? || (pt - cam.eye).dot(cam.direction) > 0
      x, y = screen_px(view, pt)
      in_front && x.between?(0, view.vpwidth) && y.between?(0, view.vpheight)
    end

    def self.stroke_json(stroke, view)
      world = stroke.points.map { |p| Units.point(p) }
      hits = stroke.hits.compact
      # One entry per distinct innermost instance (or root face).
      by_owner = {}
      hits.each do |hit|
        idx = hit[:detail].rindex { |e| %w[group component].include?(e[:kind]) }
        key = idx ? hit[:path][0..idx] : hit[:path]
        detail = idx ? hit[:detail][0..idx] : hit[:detail]
        by_owner[key] ||= detail
      end
      h = {
        id: stroke.id,
        kind: stroke.kind,
        screen_px: stroke.points.map { |p| screen_px(view, p) },
        world: world,
        point_snaps: stroke.snaps,
        point_normals: stroke.hits.map { |hit| hit && hit[:normal] ? Units.vector(hit[:normal]) : nil },
        in_frame: stroke.points.all? { |p| in_frame?(view, p) },
        points_visible: stroke.points.map { |p| Checks.visible?(view, p) },
        hit_refs: by_owner.keys.map(&:last),
        hit_paths: by_owner.keys,
        hit_names: by_owner.values.map { |d| Refs.breadcrumb(d) },
        metrics: metrics(world, stroke.kind == 'polygon')
      }
      h.delete(:point_normals) if h[:point_normals].none?
      c = Geom::Point3d.new(*%i[x y z].map { |a| stroke.points.sum(&a) / stroke.points.size })
      h[:surroundings] = surroundings(c)
      spread = Checks.normal_spread_deg(stroke.hits.map { |hit| hit && hit[:normal] })
      h[:metrics][:normal_spread_deg] = spread if spread
      h[:note] = stroke.note unless stroke.note.to_s.empty?
      h
    end

    # Plain math on meter arrays.
    def self.metrics(pts, closed)
      segs = pts.each_cons(2).to_a
      segs << [pts.last, pts.first] if closed && pts.size > 2
      length = segs.sum { |a, b| Math.sqrt(a.zip(b).sum { |u, v| (u - v)**2 }) }
      n = pts.size.to_f
      m = { length_m: length.round(4),
            centroid: (0..2).map { |i| (pts.sum { |p| p[i] } / n).round(4) },
            bounds: { min: (0..2).map { |i| pts.map { |p| p[i] }.min }, max: (0..2).map { |i| pts.map { |p| p[i] }.max } } }
      return m unless closed && pts.size > 2

      # Newell's method: polygon normal and area (works for non-planar outlines).
      nx = ny = nz = 0.0
      pts.each_with_index do |a, i|
        b = pts[(i + 1) % pts.size]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
      end
      len = Math.sqrt(nx * nx + ny * ny + nz * nz)
      m[:area_m2] = (len / 2).round(4)
      m[:normal] = [nx, ny, nz].map { |c| Units.clean((c / len).round(6)) } if len > 0
      m
    end

    # "<model name>.project.md" next to the .skp: shared project notes that
    # every agent reads first and updates (see docs/agent-guide.md).
    def self.project_notes(model)
      return nil if model.path.to_s.empty?

      path = File.join(File.dirname(model.path), "#{File.basename(model.path, '.*')}.project.md")
      path = path.tr('/', File::ALT_SEPARATOR) if File::ALT_SEPARATOR
      File.file?(path) ? path : nil
    end

    def self.model_info(model)
      h = { name: model.title.to_s }
      h[:path] = model.path unless model.path.to_s.empty?
      h[:bounds] = Units.bbox(model.bounds) unless model.bounds.empty?
      h
    end

    def self.camera(view)
      cam = view.camera
      h = {
        eye: Units.point(cam.eye),
        target: Units.point(cam.target),
        up: Units.vector(cam.up),
        perspective: cam.perspective?
      }
      if cam.perspective?
        h[:fov_deg] = cam.fov.to_f.round(4)
        h[:fov_axis] = cam.fov_is_height? ? 'vertical' : 'horizontal' if cam.respond_to?(:fov_is_height?)
      else
        h[:ortho_height_m] = Units.len(cam.height)
      end
      h[:viewport_px] = [view.vpwidth, view.vpheight]
      h
    end

    def self.pin_json(pin, view)
      cam = view.camera
      h = { id: pin.id, point: Units.point(pin.point) }
      if pin.normal
        h[:normal] = Units.vector(pin.normal)
        to_cam = cam.perspective? ? cam.eye - pin.point : cam.direction.reverse
        h[:front_facing] = pin.normal.dot(to_cam) > 0
      end
      h[:snap] = pin.data[:snap]

      sc = view.screen_coords(pin.point)
      x = sc.x.to_f
      y = sc.y.to_f
      in_front = !cam.perspective? || (pin.point - cam.eye).dot(cam.direction) > 0
      h[:screen_px] = [x.round(1), y.round(1)]
      h[:in_frame] = in_front && x.between?(0, view.vpwidth) && y.between?(0, view.vpheight)
      h[:visible] = in_front && Checks.visible?(view, pin.point)

      h[:entity] = pin.data[:entity]
      h[:instance] = pin.data[:instance] if pin.data[:instance]
      h[:path_detail] = pin.data[:path_detail]
      h[:note] = pin.data[:note] unless pin.data[:note].to_s.empty?
      h[:surroundings] = surroundings(pin.point)
      h
    end

    # What is at and around a mark (world meters), so agents need not survey
    # the model: floor/ceiling above and below, nearby groups with world bounds.
    def self.surroundings(point)
      p = Units.point(point)
      lv = Kit.level_at(p[0], p[1], p[2])
      { level: lv.compact, nearby: Kit.around(p, 15.0, 8) }
    rescue StandardError => e
      Log.error('surroundings failed', e)
      nil
    end

    def self.selection(model)
      active = model.active_path || []
      base = Refs.path_refs(active)
      tr = model.edit_transform
      model.selection.to_a.first(MAX_SELECTION).filter_map do |e|
        next unless e.respond_to?(:persistent_id) && e.persistent_id.to_i > 0

        h = Refs.basic(e).merge(path: base + [Refs.ref(e)])
        bb = Geometry.world_bounds(e, tr)
        h[:bounds] = Units.bbox(bb) if bb
        h
      end
    end
  end
end
