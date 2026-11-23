require 'json'

module ModelBuilder
  module Dev
    S5 = 1 / Math.sqrt(5) unless defined?(S5)

    # Rays (meters) cast at the calibration scene, with hand-computed expected
    # results. names = instance names along the path, root first.
    SELF_TEST_CASES = [
      { name: 'Cube_A top (group at root)', from: [10.5, 10.5, 5], dir: [0, 0, -1],
        point: [10.5, 10.5, 1], normal: [0, 0, 1], names: ['Cube_A'] },
      { name: 'Cube_A side -Y', from: [10.25, 5, 0.75], dir: [0, 1, 0],
        point: [10.25, 10, 0.75], normal: [0, -1, 0], names: ['Cube_A'] },
      { name: 'B1 top (rotated 90 deg)', from: [11.75, 10.25, 5], dir: [0, 0, -1],
        point: [11.75, 10.25, 0.5], normal: [0, 0, 1], names: ['B1'] },
      { name: 'B1 side -Y (rotated 90 deg)', from: [11.6, 5, 0.25], dir: [0, 1, 0],
        point: [11.6, 10, 0.25], normal: [0, -1, 0], names: ['B1'] },
      { name: 'B2 top (nested, scaled)', from: [11.5, 13.25, 5], dir: [0, 0, -1],
        point: [11.5, 13.25, 0.5], normal: [0, 0, 1], names: %w[Outer B2] },
      { name: 'B2 side +X (nested, scaled)', from: [20, 13.25, 0.25], dir: [-1, 0, 0],
        point: [12, 13.25, 0.25], normal: [1, 0, 0], names: %w[Outer B2] },
      { name: 'B3 top (mirrored)', from: [13.75, 10.25, 5], dir: [0, 0, -1],
        point: [13.75, 10.25, 0.5], normal: [0, 0, 1], names: ['B3'] },
      { name: 'B3 side +X (mirrored)', from: [15, 10.25, 0.25], dir: [-1, 0, 0],
        point: [14, 10.25, 0.25], normal: [1, 0, 0], names: ['B3'] },
      { name: 'W1 slope (non-uniform scale)', from: [17, 10.5, 5], dir: [0, 0, -1],
        point: [17, 10.5, 0.5], normal: [S5, 0, 2 * S5], names: ['W1'] },
      { name: 'W1 back face -X', from: [15, 10.75, 0.5], dir: [1, 0, 0],
        point: [16, 10.75, 0.5], normal: [-1, 0, 0], names: ['W1'] }
    ].freeze unless defined?(SELF_TEST_CASES)

    POINT_TOL_M = 1e-5 unless defined?(POINT_TOL_M)
    NORMAL_TOL = 1e-5 unless defined?(NORMAL_TOL)

    # Builds the calibration scene, casts the rays, compares with the expected
    # values, adds each hit as a pin, exports a packet, and writes a report to
    # %LOCALAPPDATA%\ModelBuilder\selftest\last_result.json
    def self.run_self_test(model = Sketchup.active_model, export: true)
      build_calibration_scene(model)
      PinStore.clear
      view = model.active_view
      view.zoom_extents

      results = SELF_TEST_CASES.map { |c| run_case(model, c) }
      report = {
        ran_at: Time.now.iso8601,
        sketchup_version: Sketchup.version.to_s,
        extension_version: VERSION,
        protocol_version: PROTOCOL_VERSION,
        ui_scale_factor: (UI.respond_to?(:scale_factor) ? UI.scale_factor : nil),
        viewport_px: [view.vpwidth, view.vpheight],
        passed: results.count { |r| r[:pass] },
        total: results.size,
        cases: results
      }

      if export
        exp = Exporter.export(model)
        report[:export] = {
          packet_path: exp[:packet_path],
          image_path: exp[:image_path],
          image_px: png_size(exp[:image_path]),
          json_roundtrip_ok: JSON.parse(File.read(exp[:packet_path], encoding: 'UTF-8'))['pins'].size == results.count { |r| r[:hit] }
        }
        report[:export][:image_matches_viewport] = report[:export][:image_px] == report[:viewport_px]
      end

      dir = File.join(Log.base_dir, 'selftest')
      FileUtils.mkdir_p(dir)
      report[:report_path] = File.join(dir, 'last_result.json')
      File.open(report[:report_path], 'w:UTF-8') { |f| f.write(JSON.pretty_generate(report)) }

      Log.info("Self-test: #{report[:passed]}/#{report[:total]} passed -> #{report[:report_path]}")
      puts "[ModelBuilder] self-test #{report[:passed]}/#{report[:total]} passed"
      results.each { |r| puts "  #{r[:pass] ? 'PASS' : 'FAIL'}  #{r[:name]}#{r[:pass] ? '' : "  #{r[:problems].join('; ')}"}" }
      report
    end

    def self.run_self_test_interactive
      ModelBuilder.guard('Running the self-test', notify: true) do
        model = Sketchup.active_model
        unless model.entities.length.zero?
          msg = "The self-test adds the calibration scene to this model.\n" \
                'It is meant for an empty model (File > New). Continue?'
          next unless UI.messagebox(msg, MB_YESNO) == IDYES
        end
        r = run_self_test(model)
        failed = r[:cases].reject { |c| c[:pass] }.map { |c| "- #{c[:name]}: #{c[:problems].join('; ')}" }
        text = "Self-test: #{r[:passed]}/#{r[:total]} passed.\n"
        text += "\n#{failed.join("\n")}\n" unless failed.empty?
        if r[:export]
          text += "\nScreenshot size matches viewport: #{r[:export][:image_matches_viewport]}"
          text += "\nPacket: #{r[:export][:packet_path]}"
        end
        text += "\nReport: #{r[:report_path]}"
        UI.messagebox(text)
      end
    end

    def self.run_case(model, c)
      ray = [Units.to_point(c[:from]), Geom::Vector3d.new(*c[:dir])]
      cap = Capture.from_ray(model, ray)
      out = { name: c[:name], expected: { point: c[:point], normal: c[:normal], names: c[:names] } }
      unless cap
        return out.merge(hit: false, pass: false, problems: ['ray hit nothing'])
      end

      pin = PinStore.add(model, cap)
      got_point = Units.point(cap[:point])
      got_normal = cap[:normal] ? Units.vector(cap[:normal]) : nil
      got_names = cap[:data][:path_detail].select { |e| %w[group component].include?(e[:kind]) }.map { |e| e[:name] }
      leaf_kind = cap[:data][:entity][:kind]

      problems = []
      dp = dist(got_point, c[:point])
      problems << "point off by #{format('%.6f', dp)} m" if dp > POINT_TOL_M
      if got_normal.nil?
        problems << 'no normal'
      elsif dist(got_normal, c[:normal]) > NORMAL_TOL
        problems << "normal #{got_normal.inspect} != #{c[:normal].map { |v| v.round(6) }.inspect}"
      end
      problems << "path #{got_names.inspect} != #{c[:names].inspect}" if got_names != c[:names]
      problems << "hit #{leaf_kind}, expected face" if leaf_kind != 'face'

      out.merge(hit: true, pin_id: pin.id, pass: problems.empty?, problems: problems,
                got: { point: got_point, normal: got_normal, names: got_names,
                       entity_ref: cap[:data][:entity][:ref], path: cap[:data][:entity][:path] })
    end

    def self.dist(a, b)
      Math.sqrt(a.zip(b).sum { |x, y| (x - y)**2 })
    end

    # [width, height] from a PNG header, or nil.
    def self.png_size(path)
      header = File.binread(path, 24)
      return nil unless header && header[1, 3] == 'PNG'

      header[16, 8].unpack('NN')
    rescue StandardError
      nil
    end
  end
end
