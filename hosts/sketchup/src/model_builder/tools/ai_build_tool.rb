module ModelBuilder
  # AI Build: the main entry. One tool for both kinds of marks:
  #   click a point, click it again          -> pin (confirmed)
  #   click several points, back to the 1st  -> closed outline
  #   Enter / double-click                   -> open line (2+ points)
  #   Backspace = undo last point, Esc = discard, P = lock to the first point's height
  #   right-click on an existing mark        -> edit note / delete
  # Every finished mark opens the AI Build request dialog (Panel).
  class AiBuildTool
    CLOSE_PX = 12
    VK_BACKSPACE = 8
    VK_DELETE_KEY = 46
    VK_P = 80

    @active = false
    class << self
      attr_writer :active

      def active? = @active
    end

    def activate
      @ip = Sketchup::InputPoint.new
      @points = []
      @snaps = []
      @hits = []
      @hover = nil
      @plane_lock = false
      AiBuildTool.active = true
      status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      AiBuildTool.active = false
      view.invalidate
    end

    def resume(view)
      status
      view.invalidate
    end

    def onCancel(_reason, view)
      @first_cap = nil
      @points.clear
      @snaps.clear
      @hits.clear
      status('Discarded.')
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      ModelBuilder.guard('AiBuildTool#onMouseMove') do
        @ip.pick(view, x, y)
        @mouse = [x, y]
        r = resolve(view, x, y)
        @hover = r && r[:point]
        mark = @points.empty? && MarkPick.at(view, x, y)
        view.tooltip = if near_first?(view, x, y) && @points.size == 1 then 'Click again to confirm the pin'
                       elsif near_first?(view, x, y) && @points.size >= 3 then 'Click to close the outline'
                       elsif mark then "#{mark[1].id}: right-click to edit or delete"
                       elsif @ip.valid? then @ip.tooltip
                       else ''
                       end
        view.invalidate
      end
    end

    def onLButtonDown(_flags, x, y, view)
      ModelBuilder.guard('AI Build: placing a point', notify: true) do
        if @points.size == 1 && near_first?(view, x, y)
          finish_pin(view)
          next
        end
        if @points.size >= 3 && near_first?(view, x, y)
          finish_stroke(view, 'polygon')
          next
        end
        r = resolve(view, x, y)
        unless r
          UI.beep
          status('Nothing under the cursor here. Press P to lock to the height of the first point.')
          next
        end
        next if @points.last && @points.last.distance(r[:point]) < 1e-6

        @first_cap = r[:cap] if @points.empty?
        @points << r[:point]
        @snaps << r[:snap]
        @hits << r[:hit]
        status
        view.invalidate
      end
    end

    def onLButtonDoubleClick(_flags, _x, _y, view)
      ModelBuilder.guard('AI Build: finishing the line', notify: true) { finish_stroke(view, 'line') if @points.size >= 2 }
    end

    def onReturn(view)
      ModelBuilder.guard('AI Build: finishing', notify: true) do
        if @points.size == 1 then finish_pin(view)
        elsif @points.size >= 2 then finish_stroke(view, @points.size >= 3 ? 'polygon' : 'line')
        end
      end
    end

    def onKeyDown(key, _repeat, _flags, view)
      case key
      when VK_BACKSPACE
        @points.pop
        @snaps.pop
        @hits.pop
      when VK_DELETE_KEY
        hit = @mouse && MarkPick.at(view, *@mouse)
        return false unless hit

        ModelBuilder.delete_mark(hit[1].id)
      when VK_P
        @plane_lock = !@plane_lock
      else
        return false
      end
      status
      view.invalidate
      true
    end

    def getMenu(menu, _flags, x, y, view)
      MarkPick.add_menu_items(menu, view, x, y) if @points.empty?
      menu.add_item('Open AI Build request') { Panel.show }
      menu.add_item('Clear all marks') { ModelBuilder.clear_markup }
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

      MarkupDraw.draw_stroke(view, @points, false, nil, MarkupDraw::DRAFT_COLOR, @hover) if @points.size >= 1
      if @points.size == 1
        # the first point is drawn as a pin-to-be; clicking it again confirms
        s = view.screen_coords(@points.first)
        view.drawing_color = Sketchup::Color.new(214, 40, 40)
        view.line_width = 2
        view.draw2d(GL_LINE_LOOP, MarkupDraw.circle_points(Geom::Point3d.new(s.x, s.y, 0), CLOSE_PX))
      end
    rescue StandardError => e
      Log.error('AiBuildTool#draw failed', e)
    end

    private

    def resolve(view, x, y)
      if @plane_lock && @points.any?
        plane = [Geom::Point3d.new(0, 0, @points.first.z), Geom::Vector3d.new(0, 0, 1)]
        q = Geom.intersect_line_plane(view.pickray(x, y), plane)
        return q ? { point: q, snap: 'plane', hit: nil } : nil
      end
      cap = Capture.from_screen(view, x, y, @ip)
      if cap
        return { point: cap[:point], snap: cap[:data][:snap], cap: cap,
                 hit: { path: cap[:data][:entity][:path], detail: cap[:data][:path_detail], normal: cap[:normal] } }
      end
      if @ip&.valid? && @ip.degrees_of_freedom <= 1
        return { point: @ip.position, snap: @ip.degrees_of_freedom.zero? ? 'point' : 'edge', hit: nil }
      end

      z = @points.last ? @points.last.z : 0
      q = Geom.intersect_line_plane(view.pickray(x, y), [Geom::Point3d.new(0, 0, z), Geom::Vector3d.new(0, 0, 1)])
      q ? { point: q, snap: 'plane', hit: nil } : nil
    end

    def near_first?(view, x, y)
      return false if @points.empty?

      s = view.screen_coords(@points.first)
      Math.hypot(s.x - x, s.y - y) <= CLOSE_PX
    end

    def finish_pin(view)
      unless @first_cap
        UI.beep
        status('A pin needs a surface under it. Click several points for an outline instead.')
        return
      end
      pin = PinStore.add(view.model, @first_cap)
      reset(view)
      status("#{pin.id} placed.")
      Panel.show(focus: true)
    end

    def finish_stroke(view, kind)
      s = MarkupStore.add_stroke(view.model, kind, @points.dup, @snaps.dup, @hits.dup)
      reset(view)
      status("#{s.id.upcase} placed.")
      Panel.show(focus: true)
    end

    def reset(view)
      @first_cap = nil
      @points.clear
      @snaps.clear
      @hits.clear
      view.invalidate
    end

    def status(prefix = nil)
      n = @points.size
      tip = case n
            when 0 then 'AI Build: click a point (click it again = pin), or click several points and return to the first = outline.'
            when 1 then 'Click the point again to confirm a pin, or click more points for an outline.'
            else "#{n} points. Click the first point to close, Enter = open line, Backspace = undo, Esc = discard."
            end
      tip += ' [P: height lock ON]' if @plane_lock
      Sketchup.status_text = prefix ? "#{prefix}  #{tip}" : tip
    end
  end
end
