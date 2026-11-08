require 'json'

module ModelBuilder
  module Dev
    # Probes the CURRENT VIEW of ANY model: "clicks" a grid of screen positions
    # through the same code path as the Pin tool (Capture.from_screen, with and
    # without InputPoint snapping) and checks each capture against values
    # computed independently with SketchUp's InstancePath API:
    #
    #   transform  our path transformation == InstancePath#transformation
    #   on_face    the point lies on the hit face (world plane from transformed vertices)
    #   normal     unit length, perpendicular to the world face plane, and on the
    #              front side (checked by transforming point + local normal offset)
    #   screen     (no-snap) screen_coords(point) is within 1 px of the clicked pixel
    #   path       entity.path / path_detail / instance are consistent
    #
    # Adds up to max_pins captures (distinct instances first) as pins and exports
    # a packet. Report: %LOCALAPPDATA%\ModelBuilder\selftest\probe_result.json
    PROBE_POINT_TOL_M = 0.0005 unless defined?(PROBE_POINT_TOL_M)

    def self.probe_view(model = Sketchup.active_model, cols: 9, rows: 7, max_pins: 12, export: true)
      view = model.active_view
      w = view.vpwidth
      h = view.vpheight
      PinStore.clear
      probes = []

      (1..rows).each do |gy|
        (1..cols).each do |gx|
          x = (w * gx.to_f / (cols + 1)).round
          y = (h * gy.to_f / (rows + 1)).round
          plain = Capture.from_screen(view, x, y, nil)
          next probes << { px: [x, y], hit: false } unless plain

          ip = Sketchup::InputPoint.new
          ip.pick(view, x, y)
          snapped = Capture.from_screen(view, x, y, ip)

          entry = { px: [x, y], hit: true, plain: check_capture(model, view, plain, [x, y]) }
          entry[:snapped] = check_capture(model, view, snapped, nil) if snapped && snapped[:data][:snap] != plain[:data][:snap]
          entry[:capture] = plain
          probes << entry
        end
      end

      hits = probes.select { |p| p[:hit] }
      checks = hits.flat_map { |p| [p[:plain], p[:snapped]].compact }
      failed = checks.reject { |c| c[:pass] }

      # Pins: one per distinct innermost instance (or root face) first, then fill up.
      chosen = []
      seen = {}
      hits.each do |p|
        key = (p[:capture][:data][:instance] || {})[:path] || ['root']
        next if seen[key]

        seen[key] = true
        chosen << p
      end
      (hits - chosen).each { |p| chosen << p if chosen.size < max_pins }
      chosen.first(max_pins).each { |p| PinStore.add(model, p[:capture]) }

      report = {
        ran_at: Time.now.iso8601,
        model: { title: model.title, path: model.path, units: Units.display_unit(model),
                 definitions: model.definitions.count { |d| !d.image? },
                 top_level_entities: model.entities.length },
        sketchup_version: Sketchup.version.to_s,
        extension_version: VERSION,
        viewport_px: [w, h],
        grid: [cols, rows],
        hits: hits.size,
        misses: probes.size - hits.size,
        checks: checks.size,
        passed: checks.size - failed.size,
        snap_kinds: checks.map { |c| c[:snap] }.tally,
        max_path_depth: checks.map { |c| c[:depth] }.max,
        distinct_instances: seen.size,
        pins_exported: [chosen.size, max_pins].min,
        failures: failed,
        samples: checks.first(40)
      }

      if export
        exp = Exporter.export(model)
        report[:export] = { packet_path: exp[:packet_path], image_path: exp[:image_path],
                            image_px: png_size(exp[:image_path]) }
        report[:export][:image_matches_viewport] = report[:export][:image_px] == [w, h]
      end

      dir = File.join(Log.base_dir, 'selftest')
      FileUtils.mkdir_p(dir)
      report[:report_path] = File.join(dir, 'probe_result.json')
      File.open(report[:report_path], 'w:UTF-8') { |f| f.write(JSON.pretty_generate(report)) }
      Log.info("Probe #{model.title}: #{report[:passed]}/#{report[:checks]} checks passed, " \
               "#{hits.size} hits, #{seen.size} instances -> #{report[:report_path]}")
      report
    end

    def self.probe_view_interactive
      ModelBuilder.guard('Probing the current view', notify: true) do
        r = probe_view
        text = "Probe: #{r[:passed]}/#{r[:checks]} checks passed (#{r[:hits]} hits, " \
               "#{r[:distinct_instances]} instances, max depth #{r[:max_path_depth]}).\n"
        r[:failures].first(5).each { |f| text += "\n- #{f[:path_names]}: #{f[:problems].join('; ')}" }
        text += "\n\nPins added: #{r[:pins_exported]} (activate the Pin Tool to see them)."
        text += "\nPacket: #{r[:export][:packet_path]}" if r[:export]
        text += "\nReport: #{r[:report_path]}"
        UI.messagebox(text)
      end
    end

    # Independent verification of one capture. clicked_px: [x, y] for the
    # screen round-trip check (only meaningful without snapping).
    def self.check_capture(model, view, cap, clicked_px)
      data = cap[:data]
      ent = data[:entity]
      problems = []
      path = ent[:path].map { |r| find_by_ref(model, r) }
      if path.any?(&:nil?)
        return { pass: false, problems: ['could not resolve path refs'], snap: data[:snap], depth: path.size }
      end

      leaf = path.last
      ipath = Sketchup::InstancePath.new(path)
      problems << 'InstancePath invalid' unless ipath.valid?
      ref_tr = ipath.transformation
      our_tr = Geometry.path_transformation(path[0...-1])
      tr_err = ref_tr.to_a.zip(our_tr.to_a).map { |a, b| (a - b).abs }.max
      problems << "transform differs (max #{tr_err})" if tr_err > 1e-6

      point = cap[:point]
      tol = Units.to_inches(PROBE_POINT_TOL_M)
      if leaf.is_a?(Sketchup::Face)
        wv = leaf.outer_loop.vertices.map { |v| v.position.transform(ref_tr) }
        plane = Geom.fit_plane_to_points(wv)
        off = point.distance_to_plane(plane)
        problems << "point #{Units.len(off)} m off face plane" if off > tol

        if cap[:normal]
          n = cap[:normal]
          problems << 'normal not unit' if (n.length - 1).abs > 1e-6
          plane_n = Geom::Vector3d.new(plane[0], plane[1], plane[2])
          problems << 'normal not perpendicular to face' if n.cross(plane_n).length > 1e-5
          local_pt = point.transform(ref_tr.inverse)
          eps = Units.to_inches(0.01)
          front = local_pt.offset(leaf.normal, eps).transform(ref_tr) - point
          problems << 'normal points to back side' if front.dot(n) <= 0
        else
          problems << 'face hit without normal'
        end
      end

      problems << 'path_detail refs != entity.path' if data[:path_detail].map { |e| e[:ref] } != ent[:path]
      inst = path[0...-1].reverse.find { |e| Refs.instance?(e) }
      if inst
        problems << 'instance mismatch' unless data[:instance] && data[:instance][:ref] == Refs.ref(inst)
      elsif data[:instance]
        problems << 'instance reported at root'
      end

      screen_err = nil
      if clicked_px
        sc = view.screen_coords(point)
        screen_err = Math.hypot(sc.x.to_f - clicked_px[0], sc.y.to_f - clicked_px[1]).round(3)
        problems << "screen round-trip off by #{screen_err} px" if screen_err > 1.0
      end

      {
        pass: problems.empty?, problems: problems, snap: data[:snap], depth: path.size,
        point: Units.point(point), normal: cap[:normal] && Units.vector(cap[:normal]),
        path_names: data[:path_detail].map { |e| e[:name] || e[:definition] || e[:kind] }.join(' > '),
        screen_err_px: screen_err
      }
    end

    # "su:<pid>" -> entity. Entities inside a definition exist once (shared by
    # all instances), so this is unambiguous for each path element.
    def self.find_by_ref(model, ref)
      model.find_entity_by_persistent_id(ref.sub('su:', '').to_i)
    end
  end
end
