module ModelBuilder
  # Draws pins and strokes (shared by the overlay and the tools).
  # Everything is drawn in 2D screen space so markup stays on top of geometry.
  module MarkupDraw
    PIN_COLOR = Sketchup::Color.new(214, 40, 40)
    NORMAL_COLOR = Sketchup::Color.new(30, 90, 220)
    STROKE_COLOR = Sketchup::Color.new(255, 128, 0)
    DRAFT_COLOR = Sketchup::Color.new(255, 128, 0, 160)
    BUBBLE_RADIUS = 11
    BUBBLE_OFFSET = [16, -16].freeze
    NORMAL_PX = 28

    def self.draw_all(view, model = view.model)
      MarkupStore.strokes(model).each { |s| draw_stroke(view, s.points, s.kind == 'polygon', s.id.upcase, STROKE_COLOR) }
      PinStore.pins(model).each_with_index { |pin, i| draw_pin(view, pin, i + 1) }
    end

    def self.extents(model)
      bb = Geom::BoundingBox.new
      PinStore.pins(model).each { |p| bb.add(p.point) }
      MarkupStore.strokes(model).each { |s| s.points.each { |pt| bb.add(pt) } }
      bb
    end

    def self.in_front?(view, pt)
      cam = view.camera
      !cam.perspective? || (pt - cam.eye).dot(cam.direction) > 0
    end

    def self.screen(view, pt)
      sp = view.screen_coords(pt)
      Geom::Point3d.new(sp.x, sp.y, 0)
    end

    def self.draw_pin(view, pin, number)
      return unless in_front?(view, pin.point)

      if pin.normal
        len = view.pixels_to_model(NORMAL_PX, pin.point)
        tip = pin.point.offset(pin.normal, len)
        if in_front?(view, tip)
          view.line_stipple = ''
          view.line_width = 2
          view.drawing_color = NORMAL_COLOR
          view.draw2d(GL_LINES, [screen(view, pin.point), screen(view, tip)])
        end
      end

      sp = screen(view, pin.point)
      view.draw_points([pin.point], 9, 3, PIN_COLOR) # 3 = "+"
      c = Geom::Point3d.new(sp.x + BUBBLE_OFFSET[0], sp.y + BUBBLE_OFFSET[1], 0)
      view.line_width = 1
      view.drawing_color = PIN_COLOR
      view.draw2d(GL_LINES, [sp, c])
      circle = circle_points(c, BUBBLE_RADIUS)
      view.draw2d(GL_POLYGON, circle)
      view.drawing_color = 'white'
      view.draw2d(GL_LINE_LOOP, circle)
      label(view, c, number.to_s, 'white')
    end

    # points: world Point3d list. hover: optional extra world point (rubber band).
    def self.draw_stroke(view, points, closed, tag, color, hover = nil)
      pts = points.select { |p| in_front?(view, p) }.map { |p| screen(view, p) }
      pts << screen(view, hover) if hover && in_front?(view, hover)
      return if pts.empty?

      view.line_stipple = ''
      view.line_width = 3
      view.drawing_color = color
      view.draw2d(closed && pts.size > 2 ? GL_LINE_LOOP : GL_LINE_STRIP, pts) if pts.size > 1
      pts.each { |p| view.draw2d(GL_POLYGON, circle_points(p, 3.5, 10)) }
      return unless tag

      first = pts.first
      box = Geom::Point3d.new(first.x - 26, first.y - 26, 0)
      view.drawing_color = color
      view.draw2d(GL_QUADS, [box, box.offset([22, 0, 0]), box.offset([22, 16, 0]), box.offset([0, 16, 0])])
      label(view, box.offset([11, 8, 0]), tag, 'white', 9)
    end

    def self.label(view, center, text, color, size = 10)
      opts = { size: size, bold: true, color: color, align: TextAlignCenter }
      pt = center
      if defined?(TextVerticalAlignCenter)
        opts[:vertical_align] = TextVerticalAlignCenter
      else
        pt = Geom::Point3d.new(center.x, center.y - 7, 0)
      end
      view.draw_text(pt, text, opts)
    end

    def self.circle_points(center, radius, segments = 20)
      (0...segments).map do |i|
        a = 2 * Math::PI * i / segments
        Geom::Point3d.new(center.x + radius * Math.cos(a), center.y + radius * Math.sin(a), 0)
      end
    end
  end
end
