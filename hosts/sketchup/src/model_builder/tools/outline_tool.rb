module ModelBuilder
  # Draw an outline (closed area) or a line on the model, then type a note.
  #   Click             : add a point (snaps to points/edges/faces like native tools)
  #   Click first point : close the outline
  #   Enter / dbl-click : finish (closed if >= 3 points, else open line)
  #   P                 : toggle "plane lock": new points are projected onto the
  #                       horizontal plane through the first point (for outlining
  #                       openings/voids at rim height)
  #   Backspace         : remove last point (or last finished outline)
  #   Esc               : discard the current outline
  class OutlineTool
    VK_BACKSPACE = 8
    VK_P = 80
    CLOSE_PX = 10

    @active = false

    class << self
      attr_writer :active

      def active?
        @active
      end
    end

    def activate
      @ip = Sketchup::InputPoint.new
      @plane_lock = false
      reset
      OutlineTool.active = true
      update_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      OutlineTool.active = false
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def reset
      @points = []
      @snaps = []
      @hits = []
      @hover = nil
    end

    def onMouseMove(_flags, x, y, view)
      ModelBuilder.guard('OutlineTool#onMouseMove') do
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip if @ip.valid?
        r = resolve(view, x, y)
        @hover = r && r[:point]
        view.invalidate
      end
    end

    def onLButtonDown(_flags, x, y, view)
      ModelBuilder.guard('Adding an outline point', notify: true) do
        if @points.size >= 3 && near_first?(view, x, y)
          finish(view, 'polygon')
          next
        end
        r = resolve(view, x, y)
        unless r
          UI.beep
          update_status('Nothing under the cursor (press P to lock to a plane).')
          next
        end
        if @points.last && @points.last.distance(r[:point]) < 1e-6
          next # double-click duplicates
        end

        @points << r[:point]
        @snaps << r[:snap]
        @hits << r[:hit]
        update_status
        view.invalidate
      end
    end

    def onLButtonDoubleClick(_flags, _x, _y, view)
      ModelBuilder.guard('Finishing the outline', notify: true) { finish(view) }
    end

    def onReturn(view)
      ModelBuilder.guard('Finishing the outline', notify: true) { finish(view) }
    end

    def onCancel(_reason, view)
      reset
      update_status('Outline discarded.')
      view.invalidate
    end

    def onKeyDown(key, _repeat, _flags, view)
      case key
      when VK_BACKSPACE
        if @points.empty?
          s = MarkupStore.remove_last_stroke
          update_status(s ? "Removed #{s.id}." : nil)
        else
          @points.pop
          @snaps.pop
          @hits.pop
          update_status
        end
      when VK_P
        @plane_lock = !@plane_lock
        update_status("Plane lock #{@plane_lock ? 'ON' : 'OFF'}.")
      else
        return false
      end
      view.invalidate
      true
    end

    def getMenu(menu, _flags, x, y, view)
      MarkPick.add_menu_items(menu, view, x, y) if @points.empty?
      last = MarkupStore.strokes.last
      menu.add_item("Edit Note of #{last.id}...") { ModelBuilder.edit_stroke_note(last) } if last
      menu.add_item('Remove Last Outline') { MarkupStore.remove_last_stroke && Sketchup.active_model.active_view.invalidate }
      menu.add_item('Clear All Markup') { ModelBuilder.clear_markup }
      menu.add_separator
      menu.add_item('Export Context Packet...') { ModelBuilder.export_context }
      true
    end

    def getExtents
      bb = MarkupDraw.extents(Sketchup.active_model)
      @points.each { |p| bb.add(p) }
      bb
    end

    def draw(view)
      @ip.draw(view) if @ip&.display?
      MarkupDraw.draw_all(view) unless Overlays.active?(view.model)
      return if @points.empty? && @hover.nil?

      MarkupDraw.draw_stroke(view, @points, false, nil, MarkupDraw::DRAFT_COLOR, @hover)
    rescue StandardError => e
      Log.error('OutlineTool#draw failed', e)
    end

    private

    # -> {point:, snap:, hit:} or nil
    def resolve(view, x, y)
      if @plane_lock && @points.any?
        plane = [Geom::Point3d.new(0, 0, @points.first.z), Geom::Vector3d.new(0, 0, 1)]
        pt = Geom.intersect_line_plane(view.pickray(x, y), plane)
        return pt ? { point: pt, snap: 'plane', hit: nil } : nil
      end

      cap = Capture.from_screen(view, x, y, @ip)
      if cap
        hit = { path: cap[:data][:entity][:path], detail: cap[:data][:path_detail], normal: cap[:normal] }
        return { point: cap[:point], snap: cap[:data][:snap], hit: hit }
      end

      # No face hit, but the cursor snaps to bare linework (e.g. an imported
      # DWG site plan, which has edges and no faces): use the snapped point.
      if @ip&.valid? && @ip.degrees_of_freedom <= 1
        return { point: @ip.position, snap: @ip.degrees_of_freedom.zero? ? 'point' : 'edge', hit: nil }
      end

      # Nothing hit: project onto the horizontal plane of the previous point (or the ground).
      z = @points.last ? @points.last.z : 0
      pt = Geom.intersect_line_plane(view.pickray(x, y), [Geom::Point3d.new(0, 0, z), Geom::Vector3d.new(0, 0, 1)])
      pt ? { point: pt, snap: 'plane', hit: nil } : nil
    end

    def near_first?(view, x, y)
      sp = view.screen_coords(@points.first)
      Math.hypot(sp.x - x, sp.y - y) <= CLOSE_PX
    end

    def finish(view, kind = nil)
      if @points.size < 2
        UI.beep
        update_status('Need at least 2 points.')
        return
      end
      kind ||= @points.size >= 3 ? 'polygon' : 'line'
      stroke = MarkupStore.add_stroke(view.model, kind, @points, @snaps, @hits)
      reset
      view.invalidate
      ModelBuilder.edit_stroke_note(stroke)
      Log.info("#{stroke.id}: #{kind} with #{stroke.points.size} points")
      update_status("#{stroke.id} added (#{kind}, #{stroke.points.size} points).")
      view.invalidate
    end

    def update_status(prefix = nil)
      lock = @plane_lock ? ' [plane lock ON]' : ''
      text = "Model Builder Outline#{lock}: #{@points.size} point(s). Click to add, click first point or " \
             'Enter to finish, P = plane lock, Backspace = undo, Esc = discard.'
      Sketchup.status_text = prefix ? "#{prefix}  #{text}" : text
    end
  end
end
