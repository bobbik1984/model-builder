require 'json'

# Study 1: find openings (inner loops of horizontal faces) and skylight faces.
module MBScript
  U = ModelBuilder::Units

  def self.newell(pts)
    nx = ny = nz = 0.0
    pts.each_with_index do |a, i|
      b = pts[(i + 1) % pts.size]
      nx += (a.y - b.y) * (a.z + b.z)
      ny += (a.z - b.z) * (a.x + b.x)
      nz += (a.x - b.x) * (a.y + b.y)
    end
    [nx / 2, ny / 2, nz / 2]
  end

  def self.loop_info(lp, tr)
    pts = lp.vertices.map { |v| v.position.transform(tr) }
    n = newell(pts)
    area_in2 = Math.sqrt(n.map { |c| c * c }.sum)
    c = pts.inject([0.0, 0.0, 0.0]) { |s, p| [s[0] + p.x, s[1] + p.y, s[2] + p.z] }.map { |v| v / pts.size }
    bb = Geom::BoundingBox.new
    pts.each { |p| bb.add(p) }
    { area_m2: (area_in2 * 0.0254 * 0.0254).round(2), centroid: U.point(Geom::Point3d.new(*c)).map { |v| v.round(2) },
      bounds: U.bbox(bb), nverts: pts.size, pts: pts }
  end

  def self.label(e)
    nm = e.name.to_s
    nm = e.definition.name if nm.empty? && e.respond_to?(:definition)
    "#{nm}[#{e.layer.name}]"
  end

  def self.walk(ents, tr, path, out, depth = 0)
    ents.each do |e|
      if e.is_a?(Sketchup::Face)
        mat = (e.material || e.back_material)&.display_name
        outer = loop_info(e.outer_loop, tr)
        nz = newell(outer[:pts])
        len = Math.sqrt(nz.map { |c| c * c }.sum)
        next if len.zero?

        horiz = (nz[2] / len).abs > 0.999
        if mat.to_s =~ /skylight|glass/i && outer[:area_m2] > 5
          out[:glass] << { mat: mat, path: path.map { |p| label(p) }, area_m2: outer[:area_m2], centroid: outer[:centroid],
                           bounds: outer[:bounds], horizontal: horiz, holes: e.loops.size - 1 }
        end
        next unless horiz

        out[:hfaces] += 1
        if outer[:area_m2] > 200
          out[:big] << { path: path.map { |p| label(p) }, mat: mat, area_m2: outer[:area_m2], z: outer[:centroid][2],
                         bounds: outer[:bounds], holes: e.loops.size - 1, up: nz[2] > 0 }
        end
        e.loops.reject(&:outer?).each do |lp|
          info = loop_info(lp, tr)
          next if info[:area_m2] < 10

          out[:holes] << info.merge(path: path.map { |p| label(p) }, face_mat: mat, face_area_m2: outer[:area_m2],
                                    up: nz[2] > 0, face_pid: e.persistent_id)
        end
      elsif e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
        next if depth > 12 || e.hidden? || !e.layer.visible?

        walk(e.definition.entities, tr * e.transformation, path + [e], out, depth + 1)
      end
    end
  end

  def self.snap(view, file, labels)
    bmp = file.sub(/\.png$/, '.bmp')
    view.write_image(filename: bmp, width: view.vpwidth, height: view.vpheight, antialias: true, transparent: false)
    img = ModelBuilder::Raster.from_bmp(bmp)
    labels.each do |txt, pt|
      s = view.screen_coords(pt)
      w, h = ModelBuilder::Raster.text_size(txt, 3)
      img.rect(s.x.round - w / 2 - 4, s.y.round - h / 2 - 4, w + 8, h + 8, [200, 0, 0])
      img.text(s.x - w / 2, s.y - h / 2, txt, [255, 255, 255], 3)
    end
    img.write_png(file)
    File.delete(bmp)
  end

  def self.run(model, out_dir)
    out = { hfaces: 0, holes: [], glass: [], big: [] }
    walk(model.entities, Geom::Transformation.new, [], out)
    out[:holes].sort_by! { |h| -h[:area_m2] }
    # dedupe holes that appear on both top and bottom faces of a slab
    labels = []
    out[:holes].each_with_index do |h, i|
      h[:id] = i + 1
      labels << [(i + 1).to_s, ModelBuilder::Units.to_point(h[:centroid])]
    end
    view = model.active_view
    snap(view, File.join(out_dir, 'holes_saved_view.png'), labels)
    bb = model.bounds
    c = bb.center
    view.camera = Sketchup::Camera.new(Geom::Point3d.new(c.x, c.y, c.z + 10_000), c, Geom::Vector3d.new(0, 1, 0), false)
    view.zoom_extents
    snap(view, File.join(out_dir, 'holes_top.png'), labels)
    res = out.merge(holes: out[:holes].map { |h| h.reject { |k, _| k == :pts } }, vp: [view.vpwidth, view.vpheight])
    File.write(File.join(out_dir, 'openings.json'), JSON.pretty_generate(res))
    "hfaces=#{out[:hfaces]} holes=#{out[:holes].size} glass=#{out[:glass].size} big=#{out[:big].size}"
  end
end
