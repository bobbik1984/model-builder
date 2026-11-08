module ModelBuilder
  # Screen-space picking of existing marks (pins, outlines) so single marks
  # can be edited or deleted with the mouse.
  module MarkPick
    PIN_PX = 16     # click within this many px of a pin (or its bubble)
    STROKE_PX = 8   # ... or of an outline segment

    # -> [:pin, Pin] / [:stroke, Stroke] / nil, nearest within tolerance.
    def self.at(view, x, y, model = view.model)
      best = nil
      PinStore.pins(model).each do |p|
        next unless MarkupDraw.in_front?(view, p.point)

        s = view.screen_coords(p.point)
        # the numbered bubble sits up-right of the point; accept both
        d = [Math.hypot(s.x - x, s.y - y), Math.hypot(s.x + 18 - x, s.y - 18 - y)].min
        best = [d, :pin, p] if d <= PIN_PX && (best.nil? || d < best[0])
      end
      MarkupStore.strokes(model).each do |st|
        pts = st.points.select { |pt| MarkupDraw.in_front?(view, pt) }.map { |pt| view.screen_coords(pt) }
        next if pts.size < 2

        segs = pts.each_cons(2).to_a
        segs << [pts.last, pts.first] if st.kind == 'polygon'
        d = segs.map { |a, b| seg_dist(x, y, a, b) }.min
        best = [d, :stroke, st] if d <= STROKE_PX && (best.nil? || d < best[0])
      end
      best && best[1..]
    end

    def self.seg_dist(x, y, a, b)
      dx = b.x - a.x
      dy = b.y - a.y
      len2 = dx * dx + dy * dy
      t = len2.zero? ? 0 : [[((x - a.x) * dx + (y - a.y) * dy) / len2, 0].max, 1].min
      Math.hypot(a.x + t * dx - x, a.y + t * dy - y)
    end

    # Adds "Edit note / Delete" items for the mark under (x, y). True if one was found.
    def self.add_menu_items(menu, view, x, y)
      hit = at(view, x, y)
      return false unless hit

      kind, mark = hit
      if kind == :pin
        menu.add_item("Edit Note of #{mark.id}...") { ModelBuilder.edit_pin_note(mark) }
        menu.add_item("Delete #{mark.id}") { ModelBuilder.delete_mark(mark.id) }
      else
        menu.add_item("Edit Note of #{mark.id.upcase}...") { ModelBuilder.edit_stroke_note(mark) }
        menu.add_item("Delete #{mark.id.upcase}") { ModelBuilder.delete_mark(mark.id) }
      end
      menu.add_separator
      true
    end
  end
end
