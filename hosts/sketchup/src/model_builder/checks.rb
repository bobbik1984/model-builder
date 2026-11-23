module ModelBuilder
  # Export-time checks. They turn things the designer may not notice into
  # facts in the packet (and warnings in the brief), so an agent does not have
  # to rediscover them (see docs/studies/park-handoff.md, facade-handoff.md).
  module Checks
    VISIBLE_TOLERANCE_M = 0.05   # hit this close to the mark still counts as "on" it
    CROSSING_MARGIN_M = 0.10     # ignore hits this close to a segment's endpoints
    CURVED_SPREAD_DEG = 15.0     # outline point normals spread more than this -> curved
    CAD_EXTENSIONS = /\.(dwg|dxf)\z/i
    REG_DICT = 'ModelBuilder'
    REG_KEY = 'registration'

    # Is world point pt visible from the camera (not hidden behind geometry)?
    def self.visible?(view, pt)
      ray = Capture.ray_toward(view.camera, pt)
      hit = view.model.raytest(ray, true)
      return true unless hit

      tol = Units.to_inches(VISIBLE_TOLERANCE_M)
      hit[0].distance(ray[0]) >= pt.distance(ray[0]) - tol
    end

    # Segments of a stroke that pass through geometry (not just touch it at
    # their ends): [{segment: [i, j], at: [x,y,z] m, through: breadcrumb}]
    def self.crossings(model, points, closed)
      out = []
      margin = Units.to_inches(CROSSING_MARGIN_M)
      idx = (0...points.size - 1).map { |i| [i, i + 1] }
      idx << [points.size - 1, 0] if closed && points.size > 2
      idx.each do |i, j|
        a = points[i]
        b = points[j]
        v = b - a
        len = v.length
        next if len <= 2 * margin

        start = a.offset(v, margin)
        hit = model.raytest([start, v], true)
        next unless hit && hit[0].distance(start) < len - 2 * margin

        out << { segment: [i + 1, j + 1], at: Units.point(hit[0]),
                 through: Refs.breadcrumb(Refs.path_detail(hit[1])) }
      end
      out
    end

    # Largest angle (degrees) between any point normal and their mean; nil if <2 normals.
    def self.normal_spread_deg(normals)
      ns = normals.compact
      return nil if ns.size < 2

      mean = ns.inject(Geom::Vector3d.new(0, 0, 0)) { |s, n| s + n }
      return 180.0 if mean.length < 1e-9

      mean.normalize!
      ns.map { |n| n.angle_between(mean) * 180 / Math::PI }.max.round(2)
    end

    # Top-level imported CAD (DWG/DXF components) and whether its placement
    # was confirmed by the user ("Mark Selected CAD as Registered").
    def self.cad_imports(model)
      model.entities.grep(Sketchup::ComponentInstance).select { |i| i.definition.name =~ CAD_EXTENSIONS }.map do |inst|
        tr = inst.transformation
        xaxis = tr.xaxis
        h = { ref: Refs.ref(inst), name: inst.name.to_s.empty? ? inst.definition.name : inst.name,
              definition: inst.definition.name, origin: Units.point(tr.origin),
              rotation_z_deg: Units.clean((Math.atan2(xaxis.y, xaxis.x) * 180 / Math::PI).round(3)),
              registration: inst.get_attribute(REG_DICT, REG_KEY) || 'unconfirmed' }
        bb = Geometry.world_bounds(inst, Geom::Transformation.new)
        h[:bounds] = Units.bbox(bb) if bb
        h
      end
    end

    def self.mark_registered(inst, note = 'confirmed by user')
      inst.set_attribute(REG_DICT, REG_KEY, "#{note} #{Time.now.iso8601}")
    end

    # Human-readable warnings for a built packet (meters/JSON data) plus model facts.
    def self.warnings(packet, stroke_crossings)
      w = []
      packet[:pins].each do |p|
        w << "#{p[:id]} is outside the screenshot." unless p[:in_frame]
        w << "#{p[:id]} is hidden behind other geometry in the screenshot." if p[:in_frame] && p[:visible] == false
        w << "#{p[:id]} is on a face seen from behind." if p[:front_facing] == false
      end
      (packet[:strokes] || []).each do |s|
        w << "#{s[:id].upcase} is partly outside the screenshot." unless s[:in_frame]
        hidden = (s[:points_visible] || []).count(false)
        w << "#{s[:id].upcase}: #{hidden} of #{s[:world].size} points are hidden behind geometry in the screenshot." if hidden.positive?
        spread = s.dig(:metrics, :normal_spread_deg)
        if spread && spread > CURVED_SPREAD_DEG
          w << "#{s[:id].upcase} lies on a curved or folded surface (normals spread #{spread}°): " \
               'its best-fit plane normal does not describe the surface; use point_normals.'
        end
        (stroke_crossings[s[:id]] || []).each do |c|
          w << "#{s[:id].upcase} segment #{c[:segment].join('-')} passes through #{c[:through]} " \
               "at (#{c[:at].map { |v| v.round(2) }.join(', ')}). Check the outline is in the right place/frame."
        end
      end
      (packet[:cad_imports] || []).each do |c|
        next unless c[:registration] == 'unconfirmed'

        w << "Imported CAD '#{c[:name]}' (#{c[:ref]}) is not confirmed to line up with the model " \
             "(rotation #{c[:rotation_z_deg]}°). Do not assume it is registered; check before building from it."
      end
      w
    end
  end
end
