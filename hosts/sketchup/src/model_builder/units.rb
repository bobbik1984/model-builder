module ModelBuilder
  # The ONLY place where SketchUp's internal inches meet protocol meters.
  # Everything that leaves this module toward a packet is in meters.
  module Units
    METERS_PER_INCH = 0.0254
    DECIMALS = 6 # micrometers; far below SketchUp's own tolerance

    # SketchUp Length / Numeric (inches) -> Float meters
    def self.len(inches)
      clean((inches.to_f * METERS_PER_INCH).round(DECIMALS))
    end

    # Meters -> inches (Float), for building geometry from metric values.
    def self.to_inches(meters)
      meters.to_f / METERS_PER_INCH
    end

    # Geom::Point3d (inches) -> [x, y, z] meters
    def self.point(pt)
      [len(pt.x), len(pt.y), len(pt.z)]
    end

    # [x, y, z] meters -> Geom::Point3d (inches)
    def self.to_point(arr)
      Geom::Point3d.new(*arr.map { |m| to_inches(m) })
    end

    # Direction vectors are unitless: normalized, not scaled.
    def self.vector(vec)
      v = vec.clone
      v.normalize! if v.length > 0
      [v.x, v.y, v.z].map { |c| clean(c.to_f.round(DECIMALS)) }
    end

    def self.bbox(bb)
      { min: point(bb.min), max: point(bb.max) }
    end

    LENGTH_UNIT_NAMES = { 0 => 'in', 1 => 'ft', 2 => 'mm', 3 => 'cm', 4 => 'm', 5 => 'yd' }.freeze

    # The unit the user sees in the model (display only).
    def self.display_unit(model)
      LENGTH_UNIT_NAMES.fetch(model.options['UnitsOptions']['LengthUnit'], 'unknown')
    rescue StandardError
      'unknown'
    end

    def self.clean(f)
      f.zero? ? 0.0 : f # avoid -0.0 in JSON
    end
  end
end
