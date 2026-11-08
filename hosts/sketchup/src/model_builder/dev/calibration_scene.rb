module ModelBuilder
  module Dev
    # Builds a small scene with known world coordinates that exercises every
    # transformation case the pin capture must handle. All values in meters.
    # The scene sits at x>=10, y>=10, away from the template's scale figure.
    # Expected values are listed in docs/acceptance/m1a-pins-export.md.
    #
    #   Cube_A  group, 1 m cube              x 10..11   y 10..11   z 0..1
    #   B1      Block 0.5 m, rotated 90° Z   x 11.5..12 y 10..10.5 z 0..0.5
    #   Outer   group at (10,13,0) containing
    #     B2    Block scaled 2x in X         x 11..12   y 13..13.5 z 0..0.5
    #   B3      Block mirrored in X          x 13.5..14 y 10..10.5 z 0..0.5
    #   W1      Wedge 1 m scaled 2x in X     x 16..18   y 10..11   z 0..1
    #           slope z = 1 - (x - 16) / 2, true normal (1,0,2)/sqrt(5)
    def self.build_calibration_scene(model = Sketchup.active_model)
      m = ->(v) { Units.to_inches(v) }
      t = ->(x, y, z) { Geom::Transformation.translation(Geom::Vector3d.new(m.(x), m.(y), m.(z))) }

      model.start_operation('Model Builder: calibration scene', true)
      ents = model.entities

      cube = ents.add_group
      cube.name = 'Cube_A'
      add_box(cube.entities, m.(1), m.(1), m.(1))
      cube.transform!(t.(10, 10, 0))

      block = model.definitions.add('MB Block 0.5m')
      add_box(block.entities, m.(0.5), m.(0.5), m.(0.5))

      wedge = model.definitions.add('MB Wedge 1m')
      add_wedge(wedge.entities, m.(1))

      rot90 = Geom::Transformation.rotation(ORIGIN_PT, Z_AXIS, 90.degrees)
      b1 = ents.add_instance(block, t.(12, 10, 0) * rot90)
      b1.name = 'B1'

      outer = ents.add_group
      outer.name = 'Outer'
      b2 = outer.entities.add_instance(block, t.(1, 0, 0) * Geom::Transformation.scaling(2, 1, 1))
      b2.name = 'B2'
      outer.transform!(t.(10, 13, 0))

      b3 = ents.add_instance(block, t.(14, 10, 0) * Geom::Transformation.scaling(-1, 1, 1))
      b3.name = 'B3'

      w1 = ents.add_instance(wedge, t.(16, 10, 0) * Geom::Transformation.scaling(2, 1, 1))
      w1.name = 'W1'

      model.commit_operation
      model.active_view.zoom_extents
      { cube: cube, b1: b1, outer: outer, b2: b2, b3: b3, w1: w1 }
    rescue StandardError
      model.abort_operation
      raise
    end

    def self.build_calibration_scene_interactive
      ModelBuilder.guard('Building the calibration scene', notify: true) do
        model = Sketchup.active_model
        unless model.entities.length.zero?
          msg = 'The model is not empty. Add the calibration scene (at x 10..18 m, y 10..13.5 m) anyway?'
          next unless UI.messagebox(msg, MB_YESNO) == IDYES
        end
        build_calibration_scene(model)
        Sketchup.status_text = 'Model Builder: calibration scene added (see docs/acceptance for expected values)'
      end
    end

    ORIGIN_PT = Geom::Point3d.new(0, 0, 0) unless defined?(ORIGIN_PT)

    def self.add_box(ents, sx, sy, sz)
      f = ents.add_face([0, 0, 0], [sx, 0, 0], [sx, sy, 0], [0, sy, 0])
      f.pushpull(f.normal.z > 0 ? sz : -sz)
      orient_outward(ents)
    end

    # Right-angled wedge: profile (0,0)-(s,0)-(0,s) in XZ, extruded s along Y.
    def self.add_wedge(ents, s)
      f = ents.add_face([0, 0, 0], [s, 0, 0], [0, 0, s])
      f.pushpull(f.normal.y > 0 ? s : -s)
      orient_outward(ents)
    end

    # For convex solids: make every face normal point away from the centroid.
    def self.orient_outward(ents)
      faces = ents.grep(Sketchup::Face)
      pts = faces.flat_map { |f| f.vertices.map(&:position) }
      c = Geom::Point3d.new(pts.sum(&:x) / pts.size, pts.sum(&:y) / pts.size, pts.sum(&:z) / pts.size)
      faces.each { |f| f.reverse! if f.normal.dot(f.bounds.center - c) < 0 }
    end
  end
end
