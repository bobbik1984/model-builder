require 'json'

module ModelBuilder
  module Dev
    # End-to-end test of the M1a+ markup features on the calibration scene:
    # pins with notes, a polygon outline with metrics, reference images, the
    # task message, annotated screenshot, brief. Expects the calibration scene
    # (builds it if Cube_A is missing). reference_paths: images to attach.
    # Report: %LOCALAPPDATA%\ModelBuilder\selftest\markup_result.json
    def self.run_markup_test(model = Sketchup.active_model, reference_paths: [])
      build_calibration_scene(model) unless model.entities.any? { |e| e.respond_to?(:name) && e.name == 'Cube_A' }
      PinStore.clear
      MarkupStore.clear_strokes
      MarkupStore.clear_references
      Overlays.attach(model)
      view = model.active_view
      view.zoom_extents

      down = Geom::Vector3d.new(0, 0, -1)
      ray = ->(x, y) { [Units.to_point([x, y, 5]), down] }
      problems = []

      # Pins with notes
      p1 = PinStore.add(model, Capture.from_ray(model, ray.(10.5, 10.5)))
      p1.data[:note] = 'Roof of this box is missing (test note, 中文)'
      p2 = PinStore.add(model, Capture.from_ray(model, ray.(17, 10.5)))
      p2.data[:note] = 'Match the slope here'

      # Polygon outline on Cube_A's top: 0.8 x 0.8 m square, CCW from above
      corners = [[10.1, 10.1], [10.9, 10.1], [10.9, 10.9], [10.1, 10.9]]
      caps = corners.map { |x, y| Capture.from_ray(model, ray.(x, y)) }
      hits = caps.map { |c| { path: c[:data][:entity][:path], detail: c[:data][:path_detail] } }
      s1 = MarkupStore.add_stroke(model, 'polygon', caps.map { |c| c[:point] }, caps.map { |c| c[:data][:snap] }, hits,
                                  'Outline of the missing roof (test)')
      # Open line from Cube_A top to B3 top
      lc = [Capture.from_ray(model, ray.(10.5, 10.5)), Capture.from_ray(model, ray.(13.75, 10.25))]
      MarkupStore.add_stroke(model, 'line', lc.map { |c| c[:point] }, lc.map { |c| c[:data][:snap] },
                             lc.map { |c| { path: c[:data][:entity][:path], detail: c[:data][:path_detail] } })

      # S3: a line drawn "over the void" (plane snaps) straight through Cube_A -> crossing warning
      s3pts = [[9.0, 10.5, 0.5], [12.0, 10.5, 0.5]].map { |q| Units.to_point(q) }
      MarkupStore.add_stroke(model, 'line', s3pts, %w[plane plane], [nil, nil], 'Line through Cube_A (test)')
      # S4: from Cube_A top to its -Y side: normals 90 deg apart -> curved/folded warning
      top = Capture.from_ray(model, ray.(10.5, 10.7))
      side = Capture.from_ray(model, [Units.to_point([10.5, 9.0, 0.5]), Geom::Vector3d.new(0, 1, 0)])
      s4caps = [top, side]
      MarkupStore.add_stroke(model, 'line', s4caps.map { |c| c[:point] }, s4caps.map { |c| c[:data][:snap] },
                             s4caps.map { |c| { path: c[:data][:entity][:path], detail: c[:data][:path_detail], normal: c[:normal] } })

      # Unconfirmed CAD import (a top-level component named like a DWG import)
      cad_def = model.definitions['MB Test Site.dwg'] || model.definitions.add('MB Test Site.dwg')
      cad_def.entities.add_line(Units.to_point([0, 0, 0]), Units.to_point([1, 0, 0])) if cad_def.entities.length.zero?
      cad = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.definition == cad_def } ||
            model.entities.add_instance(cad_def, Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees))
      cad.delete_attribute(Checks::REG_DICT, Checks::REG_KEY)

      # Project notes next to the saved model
      notes_dir = File.join(Log.base_dir, 'selftest', 'notes_test')
      FileUtils.mkdir_p(notes_dir)
      notes = File.join(notes_dir, 'mb_markup_test.project.md')
      File.write(notes, "# test project notes\n")
      model.save(File.join(notes_dir, 'mb_markup_test.skp'))

      reference_paths.each_with_index do |path, i|
        MarkupStore.add_reference(model, path, i.zero? ? 'render' : 'sketch', "test reference #{i + 1}")
      end
      MarkupStore.set_task(model, 'TEST: the roof outlined in S1 is missing; model it per the references.', 'detail')

      exp = Exporter.export(model)
      packet = JSON.parse(File.read(exp[:packet_path], encoding: 'UTF-8'))

      # Checks
      st = packet['strokes'] || []
      problems << "expected 4 strokes, got #{st.size}" unless st.size == 4
      warns = packet['warnings'] || []
      problems << "no crossing warning for S3: #{warns}" unless warns.any? { |w| w.start_with?('S3 segment 1-2 passes through') && w.include?('Cube_A') }
      problems << "no crossing warning expected for S1: #{warns}" if warns.any? { |w| w.start_with?('S1 segment') }
      problems << "no curved-surface warning for S4: #{warns}" unless warns.any? { |w| w.start_with?('S4 lies on a curved') }
      s4 = st.find { |x| x['id'] == 's4' }
      problems << "S4 point_normals #{s4 && s4['point_normals']}" unless s4 && s4['point_normals'] == [[0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]
      problems << "S4 normal spread #{s4 && s4['metrics']['normal_spread_deg']}" unless s4 && (s4['metrics']['normal_spread_deg'] - 45.0).abs < 0.01
      problems << "no CAD warning: #{warns}" unless warns.any? { |w| w.include?("Imported CAD 'MB Test Site.dwg'") }
      cadj = (packet['cad_imports'] || []).find { |c| c['definition'] == 'MB Test Site.dwg' }
      problems << "cad_imports #{cadj}" unless cadj && cadj['registration'] == 'unconfirmed' && (cadj['rotation_z_deg'] - 30).abs < 1e-6
      Checks.mark_registered(cad, 'test')
      problems << 'mark_registered did not stick' if Checks.cad_imports(model).find { |c| c[:definition] == 'MB Test Site.dwg' }[:registration] == 'unconfirmed'
      problems << "project_notes #{packet['project_notes']}" unless packet['project_notes'] && File.identical?(packet['project_notes'], notes)
      c1 = packet['pins'][0].dig('instance', 'contents')
      problems << "pin instance contents #{c1}" unless c1 && c1['faces'] == 6 && c1['instances'].zero?
      packet['pins'].each { |pp| problems << "#{pp['id']} visible flag missing" unless [true, false].include?(pp['visible']) }
      refs_big = (packet['references'] || []).select { |r| r['size_px'] && r['size_px'].max > Exporter::PREVIEW_IF_SIDE_OVER }
      refs_big.each do |r|
        pv = r['preview'] && File.join(exp[:session_dir], r['preview'])
        if pv && File.file?(pv)
          problems << "preview size #{png_size(pv)}" unless png_size(pv).max == Exporter::PREVIEW_MAX_SIDE
        else
          problems << "no preview for big reference #{r['id']}"
        end
      end

      # Preview orientation/colour: synthetic 3000x60 PNG, red top half, blue bottom half.
      synth = File.join(notes_dir, 'orient_test.png')
      w = 3000
      rgb = ([255, 0, 0].pack('C*') * (w * 30)) + ([0, 0, 255].pack('C*') * (w * 30))
      Raster.new(w, 60, rgb.b).write_png(synth)
      small, ow, oh = Raster.load_scaled(synth, 1600)
      problems << "load_scaled size #{small.width}x#{small.height} from #{ow}x#{oh}" unless [small.width, ow, oh] == [1600, 3000, 60]
      problems << "preview top pixel #{small.get(5, 1)} (expected red: rows flipped?)" unless small.get(5, 1) == [255, 0, 0]
      problems << "preview bottom pixel #{small.get(5, small.height - 2)} (expected blue)" unless small.get(5, small.height - 2) == [0, 0, 255]

      # Occlusion, independent of the export camera: look along +X at Cube_A.
      saved_cam = view.camera
      view.camera = Sketchup::Camera.new(Units.to_point([5, 10.5, 0.5]), Units.to_point([20, 10.5, 0.5]), Z_AXIS, true, 40)
      problems << 'front face point reported hidden' unless Checks.visible?(view, Units.to_point([10, 10.5, 0.5]))
      problems << 'back face point reported visible' if Checks.visible?(view, Units.to_point([11, 10.5, 0.5]))
      problems << 'open-air point reported hidden' unless Checks.visible?(view, Units.to_point([8, 10.5, 0.5]))
      view.camera = saved_cam
      if (s = st.find { |x| x['id'] == s1.id })
        m = s['metrics']
        problems << "area #{m['area_m2']} != 0.64" unless (m['area_m2'] - 0.64).abs < 1e-6
        problems << "perimeter #{m['length_m']} != 3.2" unless (m['length_m'] - 3.2).abs < 1e-6
        problems << "normal #{m['normal']} != [0,0,1]" unless m['normal'] == [0.0, 0.0, 1.0]
        problems << "centroid #{m['centroid']}" unless m['centroid'] == [10.5, 10.5, 1.0]
        problems << "hit_names #{s['hit_names']}" unless s['hit_names'].size == 1 && s['hit_names'][0].include?('Cube_A')
        problems << 'stroke note missing' unless s['note'].to_s.include?('missing roof')
      end
      line = st.find { |x| x['kind'] == 'line' }
      problems << "line should touch 2 instances, got #{line && line['hit_refs'].size}" unless line && line['hit_refs'].size == 2
      problems << 'pin note (unicode) lost' unless packet['pins'][0]['note'] == p1.data[:note]
      problems << 'message missing' unless packet['message'].to_s.start_with?('TEST')
      refs = packet['references'] || []
      problems << "expected #{reference_paths.size} references, got #{refs.size}" unless refs.size == reference_paths.size
      refs.each do |r|
        f = File.join(exp[:session_dir], r['file'])
        problems << "reference copy missing: #{f}" unless File.file?(f)
        problems << "reference copy size differs: #{f}" if File.file?(f) && File.size(f) != File.size(r['source'])
      end
      kinds = packet['views'].map { |v| v['kind'] }
      problems << "views #{kinds}" unless kinds == %w[viewport annotated]
      if exp[:annotated_image_path]
        same = File.binread(exp[:annotated_image_path]) == File.binread(exp[:image_path])
        problems << 'annotated image identical to clean image' if same
        problems << 'annotated image size != viewport' if png_size(exp[:annotated_image_path]) != packet['camera']['viewport_px']
      end
      problems << 'brief missing' unless File.file?(exp[:brief_path])

      report = {
        ran_at: Time.now.iso8601,
        sketchup_version: Sketchup.version.to_s,
        extension_version: VERSION,
        overlays_supported: Overlays.supported?,
        views: kinds,
        packet_path: exp[:packet_path],
        brief_path: exp[:brief_path],
        image_path: exp[:image_path],
        annotated_image_path: exp[:annotated_image_path],
        pins: packet['pins'].map { |p| { id: p['id'], screen_px: p['screen_px'] } },
        stroke_screen_px: st.map { |x| x['screen_px'] },
        warnings: warns,
        previews: (packet['references'] || []).filter_map { |r| r['preview'] },
        pass: problems.empty?,
        problems: problems
      }
      dir = File.join(Log.base_dir, 'selftest')
      FileUtils.mkdir_p(dir)
      report[:report_path] = File.join(dir, 'markup_result.json')
      File.open(report[:report_path], 'w:UTF-8') { |f| f.write(JSON.pretty_generate(report)) }
      Log.info("Markup test: #{problems.empty? ? 'PASS' : "FAIL #{problems.join('; ')}"} -> #{report[:report_path]}")
      report
    end
  end
end
