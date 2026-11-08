module ModelBuilder
  # Helpers for agent scripts (run through the live link). All inputs and
  # outputs in METERS, world coordinates, Z up. They exist because agents
  # otherwise spend most of their tokens re-deriving transforms and bounds
  # (DeepSeek run 2026-11-08: 39 scripts, 695k tokens, wrong world coordinates).
  #
  #   ModelBuilder::Kit.mark('p1')              -> {point:} or {points:, kind:} of a mark in the current task
  #   ModelBuilder::Kit.around([x,y,z], 15)     -> groups/components near a point, with world bounds
  #   ModelBuilder::Kit.world_bounds('su:123')  -> {min:, max:} in world meters (all parent transforms applied)
  #   ModelBuilder::Kit.ray([x,y,z], [0,0,-1])  -> {point:, path:, normal:} first hit
  #   ModelBuilder::Kit.level_at(x, y)          -> {floor:, ceiling:} heights under/over a point
  #   ModelBuilder::Kit.proposal('Roof plant')  -> the (new or existing) proposal group to build into
  #   ModelBuilder::Kit.box(ents, [x0,y0,z0], [x1,y1,z1], material: 'Grey') -> a closed box group
  #   ModelBuilder::Kit.extrude(ents, [[x,y],...], z0, height)            -> prism group from a plan polygon
  #   ModelBuilder::Kit.render(out_dir, 'name', eye: [..], target: [..])  -> PNG path (camera restored after the script)
  module Kit
    U = Units

    def self.model = Sketchup.active_model

    def self.pt(a) = U.to_point(a)

    # ---- the task's marks ----------------------------------------------------

    def self.mark(id)
      id = id.to_s.downcase
      if (p = PinStore.find(id))
        return { id: p.id, kind: 'pin', point: U.point(p.point), normal: p.normal && U.vector(p.normal), note: p.data[:note] }
      end
      s = MarkupStore.find_stroke(id) or return nil
      { id: s.id, kind: s.kind, points: s.points.map { |q| U.point(q) }, note: s.note }
    end

    # ---- finding things --------------------------------------------------------

    # All occurrences of instances (groups/components) as [entity, world transformation, path].
    def self.each_instance(ents = model.entities, tr = Geom::Transformation.new, path = [], depth = 0, &block)
      ents.each do |e|
        next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if e.hidden? || !e.layer.visible?

        wtr = tr * e.transformation
        yield e, wtr, path + [e], depth
        each_instance(e.definition.entities, wtr, path + [e], depth + 1, &block) if depth < 8
      end
    end

    def self.bbox_of(e, wtr)
      bb = Geom::BoundingBox.new
      db = e.definition.bounds
      8.times { |i| bb.add(db.corner(i).transform(wtr)) }
      bb
    end

    def self.describe(e, wtr, path)
      c = Capture.contents(e)
      { ref: Refs.ref(e), name: e.name.to_s, definition: e.definition.name, tag: e.layer.name,
        path: Refs.breadcrumb(Refs.path_detail(path)), bounds: U.bbox(bbox_of(e, wtr)),
        faces: c[:faces], children: c[:instances], tags: (c[:tags] || []).map { |t| t[:name] }.first(3) }
    end

    # Groups/components whose world bounds come within radius (m) of the point,
    # innermost-useful first (skips huge containers that contain everything).
    def self.around(point_m, radius = 15.0, limit = 15)
      p0 = pt(point_m)
      r = U.to_inches(radius)
      probe = Geom::BoundingBox.new
      probe.add(p0.offset(Geom::Vector3d.new(-r, -r, -r)))
      probe.add(p0.offset(Geom::Vector3d.new(r, r, r)))
      found = []
      each_instance do |e, wtr, path, _d|
        bb = bbox_of(e, wtr)
        next unless bb.intersect(probe).valid?

        found << [bb.diagonal, describe(e, wtr, path), bb.contains?(p0)]
      end
      found.sort_by { |d, _, inside| [inside ? 0 : 1, d] }.first(limit).map { |_, h, inside| h.merge(contains_point: inside) }
    end

    def self.find(ref)
      model.find_entity_by_persistent_id(ref.to_s.sub('su:', '').to_i)
    end

    # World bounds of an instance, all parent transforms applied (first occurrence).
    def self.world_bounds(ref_or_entity)
      target = ref_or_entity.is_a?(String) ? find(ref_or_entity) : ref_or_entity
      return nil unless target

      each_instance do |e, wtr, _path, _d|
        return U.bbox(bbox_of(e, wtr)) if e == target
      end
      U.bbox(target.bounds) # top-level loose entity
    end

    def self.ray(origin_m, dir, skip_proposals: true)
      hit = model.raytest([pt(origin_m), Geom::Vector3d.new(*dir)], true)
      return nil unless hit

      if skip_proposals && hit[1].any? { |e| e.respond_to?(:name) && e.name.to_s.start_with?('MB Proposal') }
        return ray(U.point(hit[0].offset(Geom::Vector3d.new(*dir), U.to_inches(0.01))), dir, skip_proposals: true)
      end
      leaf = hit[1].last
      tr = Geometry.path_transformation(hit[1][0...-1])
      { point: U.point(hit[0]), path: Refs.breadcrumb(Refs.path_detail(hit[1])),
        normal: leaf.is_a?(Sketchup::Face) ? U.vector(Geometry.world_normal(leaf.normal, tr)) : nil }
    end

    # Floor below and ceiling above (x, y) near height z (default: from high above).
    def self.level_at(x, y, z = nil)
      if z
        down = ray([x, y, z + 0.05], [0, 0, -1])
        up = ray([x, y, z + 0.05], [0, 0, 1])
        { floor: down && down[:point][2], floor_on: down && down[:path], ceiling: up && up[:point][2], ceiling_on: up && up[:path] }
      else
        top = ray([x, y, 2000], [0, 0, -1])
        { top: top && top[:point][2], top_on: top && top[:path] }
      end
    end

    # ---- building --------------------------------------------------------------

    def self.proposal(title)
      tag = model.layers['MB_Proposal'] || model.layers.add('MB_Proposal')
      name = "MB Proposal - #{title}"
      g = model.entities.grep(Sketchup::Group).find { |x| x.name == name }
      unless g
        g = model.entities.add_group
        g.name = name
        g.layer = tag
      end
      g
    end

    def self.material(name, rgb = nil)
      return nil unless name

      m = model.materials[name] || model.materials.add(name)
      m.color = Sketchup::Color.new(*rgb) if rgb
      m
    end

    def self.box(ents, min_m, max_m, material: nil, name: nil)
      x0, y0, z0 = min_m
      x1, y1, z1 = max_m
      extrude(ents, [[x0, y0], [x1, y0], [x1, y1], [x0, y1]], z0, z1 - z0, material: material, name: name)
    end

    def self.extrude(ents, poly_xy, z0, height, material: nil, name: nil)
      g = ents.add_group
      g.name = name if name
      f = g.entities.add_face(poly_xy.map { |x, y| pt([x, y, z0]) })
      f.reverse! if f.normal.z.negative?
      f.pushpull(U.to_inches(height))
      g.material = material.is_a?(String) ? material(material) : material if material
      g
    end

    def self.render(out_dir, name, eye:, target:, fov: 50, width: 1400, height: 900)
      view = model.active_view
      view.camera = Sketchup::Camera.new(pt(eye), pt(target), Geom::Vector3d.new(0, 0, 1), true, fov)
      path = File.join(out_dir, "#{name}.png")
      view.write_image(filename: path, width: width, height: height, antialias: true, transparent: false)
      path
    end
  end
end
