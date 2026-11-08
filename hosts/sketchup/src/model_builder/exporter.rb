require 'json'
require 'fileutils'

module ModelBuilder
  # Writes a context packet, screenshots, reference copies and a readable
  # brief into the session folder:
  #
  #   %LOCALAPPDATA%\ModelBuilder\sessions\
  #     latest.json                       pointer to the newest export (absolute paths)
  #     s_YYYYMMDD_HHMMSS\                one folder per SketchUp run (= session_id)
  #       latest.json                     copy of the newest packet
  #       latest_brief.md                 copy of the newest brief
  #       packets\pk_..._NNN.json
  #       briefs\pk_..._NNN.md            human/agent-readable task summary
  #       views\pk_..._NNN_viewport.png   clean screenshot
  #       views\pk_..._NNN_annotated.png  same view with pins/outlines burned in (if supported)
  #       refs\pk_..._NNN_r1.png          copies of attached reference images
  #
  # Paths inside a packet are relative to its session folder.
  module Exporter
    @seq ||= 0

    def self.sessions_root
      File.join(Log.base_dir, 'sessions')
    end

    def self.session_id
      @session_id ||= "s_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    end

    def self.session_dir
      File.join(sessions_root, session_id)
    end

    # Non-interactive export. Returns a hash describing what was written.
    def self.export(model = Sketchup.active_model)
      view = model.active_view
      @seq += 1
      packet_id = "pk_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{format('%03d', @seq)}"
      dir = session_dir
      %w[views packets briefs refs].each { |d| FileUtils.mkdir_p(File.join(dir, d)) }

      views, bmp = write_views(model, view, dir, packet_id)
      refs, warnings = copy_references(model, dir, packet_id)

      packet = Packet.build(model, view, packet_id: packet_id, session_id: session_id,
                                         view_paths: views, references: refs, extra_warnings: warnings.dup)
      if bmp
        begin
          if packet[:pins].any? || (packet[:strokes] || []).any?
            rel = "views/#{packet_id}_annotated.png"
            annotate(bmp, packet, File.join(dir, rel))
            packet[:views] << { kind: 'annotated', path: rel }
          end
        rescue StandardError => e
          warnings << "Annotated image failed: #{e.message}"
          Log.error('Annotated image failed', e)
        ensure
          File.delete(bmp) if File.exist?(bmp)
        end
      end
      json = JSON.pretty_generate(packet)
      packet_abs = File.join(dir, 'packets', "#{packet_id}.json")
      write_utf8(packet_abs, json)
      write_utf8(File.join(dir, 'latest.json'), json)

      brief = Brief.render(packet, dir)
      brief_abs = File.join(dir, 'briefs', "#{packet_id}.md")
      write_utf8(brief_abs, brief)
      write_utf8(File.join(dir, 'latest_brief.md'), brief)

      image_abs = File.join(dir, packet[:views].first[:path])
      annotated = packet[:views].find { |v| v[:kind] == 'annotated' }
      pointer = {
        packet_id: packet_id,
        session_id: session_id,
        session_dir: dir,
        packet_path: packet_abs,
        brief_path: brief_abs,
        image_path: image_abs,
        annotated_image_path: annotated && File.join(dir, annotated[:path]),
        reference_paths: refs.filter_map { |r| r[:file] && File.join(dir, r[:file]) },
        reference_preview_paths: refs.filter_map { |r| r[:preview] && File.join(dir, r[:preview]) },
        project_notes: packet[:project_notes],
        warnings: packet[:warnings],
        created_at: packet[:created_at]
      }.compact
      pointer.delete(:reference_preview_paths) if pointer[:reference_preview_paths].empty?
      write_utf8(File.join(sessions_root, 'latest.json'), JSON.pretty_generate(pointer))

      Log.info("Exported #{packet_id}: #{packet[:pins].size} pin(s), #{(packet[:strokes] || []).size} outline(s), " \
               "#{refs.size} reference(s) -> #{packet_abs}")
      (packet[:warnings] || []).each { |w| Log.warn(w) }
      pointer.merge(pin_count: packet[:pins].size, stroke_count: (packet[:strokes] || []).size,
                    warnings: packet[:warnings] || [], packet: packet)
    end

    # Clean viewport PNG (exactly the viewport's pixel size) plus a temporary
    # BMP of the same view for burning in markup. write_image does not include
    # overlay or tool drawing, so the annotation is drawn by Raster.
    def self.write_views(model, view, dir, packet_id)
      opts = { width: view.vpwidth, height: view.vpheight, antialias: true, transparent: false }
      rel = "views/#{packet_id}_viewport.png"
      raise "view.write_image failed for #{rel}" unless view.write_image(opts.merge(filename: File.join(dir, rel)))

      bmp = nil
      if PinStore.pins(model).any? || MarkupStore.strokes(model).any?
        bmp = File.join(dir, 'views', "#{packet_id}_tmp.bmp")
        bmp = nil unless view.write_image(opts.merge(filename: bmp))
      end
      [[{ kind: 'viewport', path: rel }], bmp]
    end

    PIN_RGB = [214, 40, 40].freeze
    STROKE_RGB = [255, 128, 0].freeze
    WHITE = [255, 255, 255].freeze

    # Burn pins (numbered bubbles) and outlines (orange, labelled S1..) into
    # the screenshot, at the packet's own screen_px coordinates.
    def self.annotate(bmp_path, packet, out_path)
      img = Raster.from_bmp(bmp_path)
      (packet[:strokes] || []).each do |s|
        pts = s[:screen_px]
        vis = s[:points_visible] || Array.new(pts.size, true)
        idx = (0...pts.size - 1).map { |i| [i, i + 1] }
        idx << [pts.size - 1, 0] if s[:kind] == 'polygon' && pts.size > 2
        idx.each do |i, j|
          a = pts[i]
          b = pts[j]
          # Marks hidden behind geometry are dashed so the image does not mislead.
          if vis[i] && vis[j]
            img.line(a[0], a[1], b[0], b[1], 3, STROKE_RGB)
          else
            img.dashed_line(a[0], a[1], b[0], b[1], 3, STROKE_RGB)
          end
        end
        pts.each_with_index { |(x, y), i| vis[i] ? img.disc(x, y, 4, STROKE_RGB) : img.ring(x, y, 5, 2, STROKE_RGB) }
        label = s[:id].upcase
        tw, th = Raster.text_size(label)
        # Label at the first point inside the image (an off-screen label was lost once).
        anchor = pts.find { |x, y| x.between?(tw + 16, img.width - 1) && y.between?(th + 16, img.height - 1) } || pts.first
        bx = anchor[0] - tw - 12
        by = anchor[1] - th - 12
        img.rect(bx.round, by.round, tw + 8, th + 8, STROKE_RGB)
        img.text(bx + 4, by + 4, label, WHITE)
      end
      packet[:pins].each_with_index do |p, i|
        x, y = p[:screen_px]
        cx = x + 18
        cy = y - 18
        img.line(x - 7, y, x + 7, y, 2, PIN_RGB)
        img.line(x, y - 7, x, y + 7, 2, PIN_RGB)
        label = (i + 1).to_s
        tw, th = Raster.text_size(label)
        if p[:visible] == false
          # Hidden behind geometry: hollow bubble, dashed leader.
          img.dashed_line(x, y, cx, cy, 2, PIN_RGB, 4)
          img.disc(cx, cy, 13, WHITE)
          img.ring(cx, cy, 13, 3, PIN_RGB)
          img.text(cx - tw / 2.0, cy - th / 2.0, label, PIN_RGB)
        else
          img.line(x, y, cx, cy, 2, PIN_RGB)
          img.disc(cx, cy, 13, PIN_RGB)
          img.ring(cx, cy, 13, 2, WHITE)
          img.text(cx - tw / 2.0, cy - th / 2.0, label, WHITE)
        end
      end
      img.write_png(out_path)
    end

    def self.copy_references(model, dir, packet_id)
      warnings = []
      refs = MarkupStore.references(model).filter_map do |r|
        if r.model_ref
          # Reference to something already in the model (e.g. an imported DWG).
          ent = model.find_entity_by_persistent_id(r.model_ref.sub('su:', '').to_i)
          unless ent
            warnings << "Reference #{r.id}: #{r.model_ref} is no longer in the model"
            next
          end
          next({ id: r.id, kind: r.kind, model_ref: r.model_ref,
                 name: ent.respond_to?(:definition) ? ent.definition.name : ent.typename, note: r.note })
        end
        unless File.file?(r.source.to_s)
          warnings << "Reference #{r.id} not found: #{r.source}"
          next
        end
        rel = "refs/#{packet_id}_#{r.id}#{File.extname(r.source).downcase}"
        FileUtils.cp(r.source, File.join(dir, rel))
        h = { id: r.id, kind: r.kind, file: rel, source: r.source, note: r.note }
        add_preview(h, File.join(dir, rel), dir, packet_id, warnings)
        h
      end
      [refs, warnings]
    end

    PREVIEW_MAX_SIDE = 1600
    PREVIEW_IF_SIDE_OVER = 2400
    PREVIEW_IF_BYTES_OVER = 4 * 1024 * 1024

    # Large images (5000 px, 27 MB renders) are hard for agents to view: write a
    # downscaled PNG next to the copy and point to it from the packet.
    def self.add_preview(ref, abs, dir, packet_id, warnings)
      return unless File.extname(abs) =~ /\.(png|jpe?g|bmp|tiff?)\z/i

      rep = Sketchup::ImageRep.new
      rep.load_file(abs)
      ref[:size_px] = [rep.width, rep.height]
      big = [rep.width, rep.height].max > PREVIEW_IF_SIDE_OVER || File.size(abs) > PREVIEW_IF_BYTES_OVER
      return unless big

      img, = Raster.load_scaled(abs, PREVIEW_MAX_SIDE)
      rel = "refs/#{packet_id}_#{ref[:id]}_preview.png"
      img.write_png(File.join(dir, rel))
      ref[:preview] = rel
    rescue StandardError => e
      warnings << "Preview for #{ref[:id]} failed: #{e.message}"
      Log.error("Preview for #{ref[:id]} failed", e)
    end

    # Menu/toolbar entry point: ask for the task, then export.
    def self.export_interactive(model = Sketchup.active_model)
      prompts = ['Task / message for the agent:', 'Level of detail:']
      defaults = [MarkupStore.message(model), MarkupStore.lod(model)]
      lists = ['', MarkupStore::LODS.join('|')]
      input = UI.inputbox(prompts, defaults, lists, 'Model Builder: Export Context Packet')
      return nil unless input

      MarkupStore.set_task(model, input[0].to_s.strip, input[1])

      result = export(model)
      Sketchup.status_text = "Model Builder: exported #{result[:packet_id]}"
      msg = "Exported #{result[:pin_count]} pin(s), #{result[:stroke_count]} outline(s), " \
            "#{(result[:reference_paths] || []).size} reference(s).\n\n" \
            "Brief:\n#{result[:brief_path]}\n\nPacket:\n#{result[:packet_path]}\n"
      msg += "\nWarnings:\n#{result[:warnings].join("\n")}\n" unless result[:warnings].empty?
      msg += "\nOpen the session folder?"
      open_folder(result[:session_dir]) if UI.messagebox(msg, MB_YESNO) == IDYES
      result
    end

    def self.open_folder(path)
      FileUtils.mkdir_p(path)
      UI.openURL("file:///#{path.tr('\\', '/')}")
    end

    def self.write_utf8(path, text)
      File.open(path, 'w:UTF-8') { |f| f.write(text) }
    end
  end
end
