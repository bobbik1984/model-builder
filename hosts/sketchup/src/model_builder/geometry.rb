module ModelBuilder
  # Coordinate helpers. All inputs/outputs here are SketchUp-native (inches,
  # Geom objects); conversion to meters happens in Units.
  module Geometry
    # Product of the instance transformations along a path (root first).
    # Pass the path WITHOUT the leaf entity.
    #
    # Assumes SketchUp 2020+, where the API reports coordinates in each
    # entity's own local space even inside an open edit context.
    def self.path_transformation(instances)
      instances.select { |e| Refs.instance?(e) }
               .inject(Geom::Transformation.new) { |tr, e| tr * e.transformation }
    end

    def self.determinant(tr)
      x = Geom::Vector3d.new(1, 0, 0).transform(tr)
      y = Geom::Vector3d.new(0, 1, 0).transform(tr)
      z = Geom::Vector3d.new(0, 0, 1).transform(tr)
      x.dot(y.cross(z))
    end

    # Transform a face normal from local to world space. Correct under
    # rotation, non-uniform scaling and mirroring (it computes the
    # inverse-transpose via transformed tangents). Returns a unit
    # Geom::Vector3d or nil if the transformation is degenerate.
    def self.world_normal(local_normal, tr)
      t1, t2, = local_normal.axes
      # Make sure t1 x t2 points along the local normal.
      t2 = t2.reverse if t1.cross(t2).dot(local_normal) < 0
      n = t1.transform(tr).cross(t2.transform(tr))
      return nil if n.length < 1e-12

      n = n.reverse if determinant(tr) < 0
      n.normalize
    end

    # Axis-aligned world bounds of an entity, given the transformation of its
    # parent context. Returns a Geom::BoundingBox (inches) or nil.
    def self.world_bounds(entity, parent_tr)
      points =
        if Refs.instance?(entity)
          bb = entity.definition.bounds
          return nil if bb.empty?

          tr = parent_tr * entity.transformation
          (0..7).map { |i| bb.corner(i).transform(tr) }
        elsif entity.respond_to?(:vertices)
          entity.vertices.map { |v| v.position.transform(parent_tr) }
        elsif entity.respond_to?(:bounds)
          bb = entity.bounds
          return nil if bb.empty?

          (0..7).map { |i| bb.corner(i).transform(parent_tr) }
        else
          return nil
        end
      out = Geom::BoundingBox.new
      points.each { |p| out.add(p) }
      out
    end
  end
end
