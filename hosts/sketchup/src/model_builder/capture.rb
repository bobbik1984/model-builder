module ModelBuilder
  # Turns a click (or a ray) into pin data: world point, world normal,
  # hit entity, innermost instance and the full instance path.
  #
  # Returned hash (internal, SketchUp-native where noted):
  #   :point  => Geom::Point3d, world, inches   (for drawing / screen coords)
  #   :normal => Geom::Vector3d, world, or nil  (for drawing / facing test)
  #   :data   => Hash already in protocol units (meters), merged into the packet
  module Capture
    # How far (meters) a snapped point may be from the hit face/edge and still
    # count as lying on it.
    ON_ENTITY_TOLERANCE_M = 0.0005

    # Pick from screen coordinates, as the pin tool does. input_point is the
    # tool's Sketchup::InputPoint already picked at (x, y); it provides
    # inference snapping to endpoints/midpoints/edges.
    def self.from_screen(view, x, y, input_point = nil)
      model = view.model
      hit = model.raytest(view.pickray(x, y), true) # true: ignore hidden geometry
      return nil unless hit

      point, path = hit
      snap = nil

      if input_point&.valid? && input_point.degrees_of_freedom <= 1
        snapped = input_point.position
        snap_kind = input_point.degrees_of_freedom.zero? ? 'point' : 'edge'
        if on_leaf?(path, snapped)
          point = snapped
          snap = snap_kind
        else
          # The snapped point may belong to another entity than the one under
          # the cursor ray. Re-aim a ray from the camera at the snapped point.
          rehit = model.raytest(ray_toward(view.camera, snapped), true)
          if rehit && on_leaf?(rehit[1], snapped)
            point = snapped
            path = rehit[1]
            snap = snap_kind
          else
            Log.info("Snap at #{snapped} not on a hit entity; using exact ray hit instead")
          end
        end
      end

      build(point, path, snap)
    end

    # Pick along an explicit ray [Point3d, Vector3d] (inches). Used by the
    # self-test; no snapping.
    def self.from_ray(model, ray)
      hit = model.raytest(ray, true)
      return nil unless hit

      build(hit[0], hit[1], nil)
    end

    def self.build(point, path, snap)
      leaf = path.last
      parents = path[0...-1]
      tr = Geometry.path_transformation(parents)

      normal = leaf.is_a?(Sketchup::Face) ? Geometry.world_normal(leaf.normal, tr) : nil
      snap ||= leaf.is_a?(Sketchup::Face) ? 'face' : 'none'

      entity = Refs.basic(leaf).merge(path: Refs.path_refs(path))
      bb = Geometry.world_bounds(leaf, tr)
      entity[:bounds] = Units.bbox(bb) if bb

      data = { snap: snap, entity: entity }

      inst_index = parents.rindex { |e| Refs.instance?(e) }
      if inst_index
        inst = parents[inst_index]
        summary = Refs.basic(inst).merge(path: Refs.path_refs(parents[0..inst_index]))
        ibb = Geometry.world_bounds(inst, Geometry.path_transformation(parents[0...inst_index]))
        summary[:bounds] = Units.bbox(ibb) if ibb
        summary[:contents] = contents(inst)
        data[:instance] = summary
      end
      data[:path_detail] = Refs.path_detail(path)

      check_on_plane(point, leaf, tr)
      { point: point, normal: normal, data: data }
    end

    CONTENTS_SCAN_LIMIT = 20_000

    # What is directly inside an instance, so an agent can tell what kind of
    # thing an unnamed group is without querying the model:
    # {faces, edges, instances, tags: [{name, count}], materials: [{name, count}]}
    def self.contents(inst)
      faces = edges = insts = 0
      tags = Hash.new(0)
      mats = Hash.new(0)
      default_layer = inst.model.layers[0]
      inst.definition.entities.each_with_index do |e, i|
        break if i >= CONTENTS_SCAN_LIMIT

        case e
        when Sketchup::Face
          faces += 1
          m = e.material || e.back_material
          mats[m.display_name] += 1 if m
        when Sketchup::Edge then edges += 1
        when Sketchup::Group, Sketchup::ComponentInstance
          insts += 1
          mats[e.material.display_name] += 1 if e.material
        end
        tags[e.layer.name] += 1 if e.respond_to?(:layer) && e.layer != default_layer
      end
      top = ->(h) { h.sort_by { |_, c| -c }.first(5).map { |n, c| { name: n, count: c } } }
      h = { faces: faces, edges: edges, instances: insts }
      h[:tags] = top.(tags) unless tags.empty?
      h[:materials] = top.(mats) unless mats.empty?
      h
    end

    # True if world_pt lies on the leaf entity of path (within tolerance).
    def self.on_leaf?(path, world_pt)
      leaf = path.last
      tr = Geometry.path_transformation(path[0...-1])
      local = world_pt.transform(tr.inverse)
      tol = Units.to_inches(ON_ENTITY_TOLERANCE_M)
      case leaf
      when Sketchup::Face
        proj = local.project_to_plane(leaf.plane)
        return false if proj.transform(tr).distance(world_pt) > tol

        [Sketchup::Face::PointInside, Sketchup::Face::PointOnVertex,
         Sketchup::Face::PointOnEdge].include?(leaf.classify_point(proj))
      when Sketchup::Edge
        proj = local.project_to_line(leaf.line)
        proj.transform(tr).distance(world_pt) <= tol
      else
        false
      end
    end

    # A ray from the camera through a world point (works for both projections).
    def self.ray_toward(camera, world_pt)
      if camera.perspective?
        [camera.eye, world_pt - camera.eye]
      else
        dir = camera.direction
        back = (world_pt - camera.eye).dot(dir).abs + Units.to_inches(1.0)
        [world_pt.offset(dir.reverse, back), dir]
      end
    end

    # Diagnostic only: log if the hit point is not on the face plane, which
    # would indicate a transformation bug.
    def self.check_on_plane(point, leaf, tr)
      return unless leaf.is_a?(Sketchup::Face)

      local = point.transform(tr.inverse)
      residual = local.project_to_plane(leaf.plane).transform(tr).distance(point)
      return if residual <= Units.to_inches(ON_ENTITY_TOLERANCE_M)

      Log.warn("Pin point is #{Units.len(residual)} m off its face plane (#{Refs.ref(leaf)})")
    end
  end
end
