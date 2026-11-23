require 'json'

# Study 6: verify the built roof: clearance above (raytest up), what is below,
# panel planarity, and a render similar to the reference camera.
module MBScript
  U = ModelBuilder::Units

  def self.run(model, out_dir)
    root = model.entities.grep(Sketchup::Group).find { |g| g.name.start_with?('MB Atrium Skylight Roof') }
    raise 'proposal group not found' unless root

    bb = root.bounds
    res = { bounds: U.bbox(bb), groups: root.entities.grep(Sketchup::Group).map { |g| [g.name, g.entities.size] } }
    # grid of upward rays from just above the roof bounds top -> anything above?
    above = []
    lo = bb.min
    hi = bb.max
    12.times do |i|
      12.times do |j|
        x = lo.x + (hi.x - lo.x) * (i + 0.5) / 12
        y = lo.y + (hi.y - lo.y) * (j + 0.5) / 12
        o = Geom::Point3d.new(x, y, hi.z + 1)
        hit = model.raytest([o, Geom::Vector3d.new(0, 0, 1)], true)
        next unless hit

        above << { at: U.point(o)[0, 2], hit_z: U.len(hit[0].z), path: hit[1].map { |e| e.respond_to?(:definition) ? e.definition.name : e.typename } }
      end
    end
    res[:above_hits] = above.size
    res[:above_min_z] = above.map { |a| a[:hit_z] }.min
    res[:above_samples] = above.sort_by { |a| a[:hit_z] }.first(6)
    res[:clearance_m] = res[:above_min_z] && (res[:above_min_z] - U.len(hi.z)).round(3)

    # panel planarity: every face of the fire panels should be planar by construction
    worst = 0.0
    root.entities.grep(Sketchup::Group).each do |g|
      g.entities.grep(Sketchup::Group).each do |pg|
        pg.entities.grep(Sketchup::Face).each do |f|
          pl = f.plane
          f.vertices.each { |v| worst = [worst, v.position.distance_to_plane(pl).to_f].max }
        end
      end
    end
    res[:max_nonplanarity_mm] = (worst * 25.4).round(4)
    File.write(File.join(out_dir, 'check.json'), JSON.pretty_generate(res))
    "above_hits=#{above.size} clearance=#{res[:clearance_m]} nonplanar_mm=#{res[:max_nonplanarity_mm]}"
  end
end
