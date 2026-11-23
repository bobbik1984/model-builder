require 'json'

# Build a proposed skylight roof over the unglazed atrium opening (face 1656115's
# inner loop) following the reference render (ridge + chevron "diagonal secondary
# beams", zigzag triangular panels in two tones) and the detail sketch
# (30 mm fire-rated solid roof panel, aluminium ceiling panels below, aluminium-
# wrapped beams, sprinklers). All inputs in meters; everything goes into ONE new
# top-level group on its own tag so the proposal can be hidden/deleted in one go.
module MBScript
  U = ModelBuilder::Units
  P = {
    face_pid: 1_656_115,  # ring face whose inner loop is the opening edge
    curb_h: 0.30,         # eave (top of curb) above the ledge
    slope_deg: 6.0,       # roof pitch along the shorter beam at each station
    spacing: 1.8,         # ridge spacing of the chevron beams (m)
    sweep_deg: 22.0,      # chevron sweep: beams lean back from the ridge normal
    panel_t: 0.030,       # fire-rated solid roof panel (detail sketch: 30)
    alu_gap: 0.060,       # vertical gap from panel underside to aluminium ceiling
    beam_w: 0.150,        # wrapped beam (100x200 RHS + aluminium wrap)
    beam_d: 0.260,
    ridge_w: 0.180,
    ridge_d: 0.300,
    sprinkler_step: 2.5,
    max_sag: 0.25
  }.merge(JSON.parse(File.read(File.join(__dir__, 'params.json')), symbolize_names: true))

  def self.v2(a, b) = [b[0] - a[0], b[1] - a[1]]
  def self.dot(a, b) = a[0] * b[0] + a[1] * b[1]
  def self.cross(a, b) = a[0] * b[1] - a[1] * b[0]
  def self.lerp(a, b, t) = a.each_index.map { |i| a[i] + (b[i] - a[i]) * t }

  # -- input geometry ------------------------------------------------------
  def self.find_face(ents, tr, pid)
    ents.each do |e|
      return [e, tr] if e.is_a?(Sketchup::Face) && e.persistent_id == pid
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)

      r = find_face(e.definition.entities, tr * e.transformation, pid)
      return r if r
    end
    nil
  end

  # ray (origin o, dir d) vs closed polygon; returns [point, seg_index, seg_t] nearest
  def self.ray_hit(poly, o, d)
    best = nil
    poly.each_index do |i|
      a = poly[i]
      b = poly[(i + 1) % poly.size]
      e = v2(a, b)
      den = cross(d, e)
      next if den.abs < 1e-12

      ao = v2(o, a)
      t = cross(ao, e) / den
      s = cross(ao, d) / den
      next unless t > 1e-6 && s >= -1e-9 && s <= 1 + 1e-9

      best = [t, i, s] if best.nil? || t < best[0]
    end
    best && [[o[0] + d[0] * best[0], o[1] + d[1] * best[0]], best[1], best[2]]
  end

  def self.run(model, out_dir)
    p = P
    face, tr = find_face(model.entities, Geom::Transformation.new, p[:face_pid])
    raise "face #{p[:face_pid]} not found" unless face

    inner = face.loops.reject(&:outer?).max_by { |l| l.vertices.size }
    pts3 = inner.vertices.map { |v| U.point(v.position.transform(tr)) }
    z_ledge = pts3.map { |q| q[2] }.sum / pts3.size
    poly = pts3.map { |q| q[0, 2] }
    # drop near-duplicate points
    poly = poly.each_with_object([]) { |q, acc| acc << q if acc.empty? || Math.hypot(*v2(acc[-1], q)) > 0.02 }

    # principal axis (PCA) -> local frame u (ridge) / v
    n = poly.size.to_f
    cx = poly.sum { |q| q[0] } / n
    cy = poly.sum { |q| q[1] } / n
    sxx = poly.sum { |q| (q[0] - cx)**2 }
    syy = poly.sum { |q| (q[1] - cy)**2 }
    sxy = poly.sum { |q| (q[0] - cx) * (q[1] - cy) }
    ang = 0.5 * Math.atan2(2 * sxy, sxx - syy)
    ux = [Math.cos(ang), Math.sin(ang)]
    vx = [-ux[1], ux[0]]
    to_w = ->(u, v) { [cx + ux[0] * u + vx[0] * v, cy + ux[1] * u + vx[1] * v] }

    # ridge ends on the outline
    s_hit = ray_hit(poly, [cx, cy], [-ux[0], -ux[1]])
    t_hit = ray_hit(poly, [cx, cy], ux)
    u_min = -Math.hypot(*v2([cx, cy], s_hit[0]))
    u_max = Math.hypot(*v2([cx, cy], t_hit[0]))
    z_e = z_ledge + p[:curb_h]
    tanp = Math.tan(p[:slope_deg] * Math::PI / 180)
    sw = Math.tan(p[:sweep_deg] * Math::PI / 180)

    # stations along the ridge, centred
    count = ((u_max - u_min) / p[:spacing]).floor
    start = (u_min + u_max) / 2 - (count - 1) * p[:spacing] / 2.0
    us = (0...count).map { |k| start + k * p[:spacing] }.select { |u| u > u_min + 0.4 && u < u_max - 0.4 }

    # per side: beam hits on the outline
    sides = { 1 => [], -1 => [] }
    us.each do |u|
      o = to_w.(u, 0)
      sides.each_key do |sgn|
        dl = [-sw, sgn * 1.0]
        d = [ux[0] * dl[0] + vx[0] * dl[1], ux[1] * dl[0] + vx[1] * dl[1]]
        h = ray_hit(poly, o, d)
        sides[sgn] << { u: u, p: o, e: h && h[0], seg: h && h[1], s: h && h[2] }
      end
    end
    stations = us.each_index.map do |k|
      lens = sides.values.map { |list| list[k][:e] ? Math.hypot(*v2(list[k][:p], list[k][:e])) : 0 }
      { u: us[k], p: to_w.(us[k], 0), h: lens.min * tanp }
    end
    s_pt = s_hit[0]
    t_pt = t_hit[0]

    # outline arc param: position along polygon perimeter
    cum = [0.0]
    poly.each_index { |i| cum << cum[-1] + Math.hypot(*v2(poly[i], poly[(i + 1) % poly.size])) }
    perim = cum[-1]
    pos = ->(seg, s) { cum[seg] + s * (cum[seg + 1] - cum[seg]) }
    s_pos = pos.(s_hit[1], s_hit[2])
    t_pos = pos.(t_hit[1], t_hit[2])
    # points of the outline strictly between positions a -> b going forward (wrapping)
    chain = lambda do |a, b|
      out = []
      len = (b - a) % perim
      poly.each_index do |i|
        d = (cum[i] - a) % perim
        out << [d, poly[i]] if d > 1e-6 && d < len - 1e-6
      end
      out.sort_by(&:first).map(&:last)
    end

    # height field: ridge z, eave z
    zr = ->(h) { z_e + h }
    tris = [] # [[x,y,z]x3, tone]
    beams = [] # [[a3, b3], w, d]
    gutters = [] # flat polylines at eave level (chord + arc)
    ridge_pts = [[s_pt + [z_e]]] + stations.map { |st| [st[:p] + [zr.(st[:h])]] } + [[t_pt + [z_e]]]
    ridge_pts = ridge_pts.map(&:first)

    sides.each do |sgn, list|
      # which way along the outline is this side? test with the first hit position
      ok = list.select { |b| b[:e] }
      next if ok.empty?

      fwd = ((pos.(ok[0][:seg], ok[0][:s]) - s_pos) % perim) < ((t_pos - s_pos) % perim)
      # nodes from S to T on this side: P (ridge), E (edge), M (mid)
      nodes = [{ p: s_pt + [z_e], e: s_pt + [z_e], epos: s_pos }]
      list.each_with_index do |b, k|
        next unless b[:e]

        epos = pos.(b[:seg], b[:s])
        nodes << { p: stations[k][:p] + [zr.(stations[k][:h])], e: b[:e] + [z_e], epos: epos }
      end
      nodes << { p: t_pt + [z_e], e: t_pt + [z_e], epos: t_pos }
      # keep monotone along the arc
      key = ->(nd) { fwd ? (nd[:epos] - s_pos) % perim : (s_pos - nd[:epos]) % perim }
      mono = [nodes[0]]
      nodes[1..-2].each { |nd| mono << nd if key.(nd) > key.(mono[-1]) + 0.05 }
      mono << nodes[-1]
      mono.each { |nd| nd[:m] = lerp(nd[:p], nd[:e], 0.5) }

      mono.each_cons(2).with_index do |(a, b), k|
        tone = k.even? ? 0 : 1
        tris << [[a[:p], b[:p], b[:m]], tone]
        tris << [[a[:p], b[:m], a[:m]], 1 - tone]
        tris << [[a[:m], b[:m], a[:e]], tone]
        arc = fwd ? chain.(a[:epos], b[:epos]) : chain.(b[:epos], a[:epos]).reverse
        ring = [b[:e]] + arc.reverse.map { |q| q + [z_e] } + [a[:e]]
        # keep only the arc points needed so each chord sags <= max_sag; the
        # slivers between chords and the true (curved) edge become flat gutter pieces
        keep = [0]
        while keep[-1] < ring.size - 1
          j = ring.size - 1
          j -= 1 while j > keep[-1] + 1 && sag(ring, keep[-1], j) > p[:max_sag]
          keep << j
        end
        keep.each_cons(2) do |i0, i1|
          tris << [[b[:m], ring[i0], ring[i1]], 1 - tone]
          gutters << ring[i0..i1] if i1 - i0 > 1
        end
      end
      mono[1..-2].each { |nd| beams << [[nd[:p], nd[:e]], p[:beam_w], p[:beam_d]] }
    end
    ridge_pts.each_cons(2) { |a, b| beams << [[a, b], p[:ridge_w], p[:ridge_d]] }

    tris.reject! { |(a, b, c), _| (Geom::Vector3d.new(*v2(a, b), b[2] - a[2]) * Geom::Vector3d.new(*v2(a, c), c[2] - a[2])).length < 1e-6 }

    report = build_geometry(model, tris, beams, gutters, poly, z_e, z_ledge, ridge_pts, p)
    report.merge!(outline_pts: poly.size, outline_area_m2: area2(poly).abs.round(2), z_ledge: z_ledge.round(3),
                  eave_z: z_e.round(3), ridge_max_z: ridge_pts.map { |q| q[2] }.max.round(3),
                  ridge_len_m: (u_max - u_min).round(2), ridge_dir: ux.map { |c| c.round(4) },
                  centroid: [cx.round(2), cy.round(2)], stations: stations.size, panels: tris.size, beams: beams.size,
                  params: p)
    File.write(File.join(out_dir, 'build_report.json'), JSON.pretty_generate(report))
    render(model, out_dir, [cx, cy, z_e], ux, (u_max - u_min))
    "panels=#{tris.size} beams=#{beams.size} ridge_max=#{report[:ridge_max_z]}"
  end

  # max distance of ring[i0+1..i1-1] from chord ring[i0]-ring[i1] (plan)
  def self.sag(ring, i0, i1)
    a = ring[i0]
    b = ring[i1]
    e = v2(a, b)
    l = Math.hypot(*e)
    return 0 if l < 1e-9

    ring[(i0 + 1)...i1].map { |q| cross(e, v2(a, q)).abs / l }.max || 0
  end

  def self.area2(poly)
    poly.each_index.sum { |i| cross(poly[i], poly[(i + 1) % poly.size]) } / 2.0
  end

  def self.mat(model, name, rgb, alpha = 1.0)
    m = model.materials[name] || model.materials.add(name)
    m.color = Sketchup::Color.new(*rgb)
    m.alpha = alpha
    m
  end

  def self.box(ents, a, b, w, d, top_drop, material)
    va = Geom::Vector3d.new(b[0] - a[0], b[1] - a[1], b[2] - a[2])
    return if va.length < 0.01

    side = Geom::Vector3d.new(-(b[1] - a[1]), b[0] - a[0], 0)
    side.normalize!
    hw = w / 2.0
    c = lambda do |pt, s, dz|
      U.to_point([pt[0] + side.x * s, pt[1] + side.y * s, pt[2] - top_drop - dz])
    end
    a1 = c.(a, -hw, 0); a2 = c.(a, hw, 0); a3 = c.(a, hw, d); a4 = c.(a, -hw, d)
    b1 = c.(b, -hw, 0); b2 = c.(b, hw, 0); b3 = c.(b, hw, d); b4 = c.(b, -hw, d)
    g = ents.add_group
    ge = g.entities
    [[a1, a2, a3, a4], [b4, b3, b2, b1], [a1, b1, b2, a2], [a2, b2, b3, a3], [a3, b3, b4, a4], [a4, b4, b1, a1]].each do |q|
      ge.add_face(q)
    rescue ArgumentError
      nil
    end
    g.material = material
    g
  end

  def self.build_geometry(model, tris, beams, gutters, poly, z_e, z_ledge, ridge_pts, p)
    model.start_operation('MB proposal: atrium skylight roof', true)
    tag = model.layers['MB_Proposal'] || model.layers.add('MB_Proposal')
    m_fire = mat(model, 'MB Fire-rated roof panel', [120, 124, 128])
    m_alu1 = mat(model, 'MB Alu ceiling panel light', [214, 216, 218])
    m_alu2 = mat(model, 'MB Alu ceiling panel dark', [150, 156, 162])
    m_wrap = mat(model, 'MB Alu beam wrap (champagne)', [222, 196, 150])
    m_curb = mat(model, 'MB Curb', [235, 230, 222])
    m_spr = mat(model, 'MB Sprinkler', [200, 30, 30])

    root = model.active_entities.add_group
    root.name = 'MB Atrium Skylight Roof (proposal)'
    root.layer = tag
    re = root.entities

    # 1. fire-rated solid roof panels: each triangle a 30 mm solid
    fire = re.add_group
    fire.name = 'Fire-rated solid roof panels 30mm'
    tris.each do |(a, b, c), _|
      g = fire.entities.add_group
      top = [a, b, c].map { |q| U.to_point(q) }
      bot = [a, b, c].map { |q| U.to_point([q[0], q[1], q[2] - p[:panel_t]]) }
      ge = g.entities
      begin
        ge.add_face(top)
        ge.add_face(bot)
        3.times { |i| ge.add_face(top[i], top[(i + 1) % 3], bot[(i + 1) % 3], bot[i]) }
      rescue ArgumentError
        nil
      end
    end
    fire.material = m_fire

    # 2. aluminium ceiling panels (same triangles, two tones) below the fire panel
    alu = re.add_group
    alu.name = 'Aluminium ceiling panels (2 tones)'
    drop = p[:panel_t] + p[:alu_gap]
    tris.each do |(a, b, c), tone|
      pts = [a, b, c].map { |q| U.to_point([q[0], q[1], q[2] - drop]) }
      begin
        f = alu.entities.add_face(pts)
      rescue ArgumentError
        next
      end
      f.reverse! if f.normal.z.positive?
      f.material = tone.zero? ? m_alu1 : m_alu2
      f.back_material = f.material
    end

    # 3. beams: ridge (primary) + chevron secondary beams, aluminium wrapped
    bg = re.add_group
    bg.name = 'Beams (100x200 RHS, aluminium wrapped)'
    beams.each { |(a, b), w, d| box(bg.entities, a, b, w, d, p[:panel_t], m_wrap) }

    # 4. curb along the opening edge (ledge -> eave)
    cg = re.add_group
    cg.name = 'Edge curb'
    poly.each_index do |i|
      a = poly[i]
      b = poly[(i + 1) % poly.size]
      q = [U.to_point(a + [z_ledge]), U.to_point(b + [z_ledge]), U.to_point(b + [z_e]), U.to_point(a + [z_e])]
      begin
        cg.entities.add_face(q)
      rescue ArgumentError
        nil
      end
    end
    cg.material = m_curb

    # 4b. flat gutter / flashing pieces between panel chords and the curved edge
    gg = re.add_group
    gg.name = 'Perimeter gutter / flashing'
    gutters.each do |ptsg|
      pts = ptsg.map { |q| U.to_point(q) }
      begin
        f = gg.entities.add_face(pts)
        f.reverse! if f && f.normal.z.negative?
      rescue ArgumentError
        nil
      end
    end
    gg.material = m_curb

    # 5. sprinkler heads under the beams
    sg = re.add_group
    sg.name = 'Sprinkler heads'
    heads = 0
    beams.each do |(a, b), _w, d|
      len = Math.sqrt((0..2).sum { |i| (b[i] - a[i])**2 })
      k = (len / p[:sprinkler_step]).floor
      (1..k).each do |j|
        q = lerp(a, b, j.to_f / (k + 1))
        ctr = U.to_point([q[0], q[1], q[2] - p[:panel_t] - d - 0.01])
        circ = sg.entities.add_circle(ctr, Geom::Vector3d.new(0, 0, 1), U.to_inches(0.04), 8)
        f = sg.entities.add_face(circ)
        f&.pushpull(U.to_inches(f.normal.z.negative? ? 0.06 : -0.06))
        heads += 1
      end
    end
    sg.material = m_spr
    model.commit_operation
    { root_pid: root.persistent_id, sprinklers: heads }
  end

  def self.render(model, out_dir, c, ux, len)
    view = model.active_view
    # hide the towers so aerial views see the roof
    model.definitions.each { |d| d.instances.each { |i| i.hidden = true } if d.name == '组#5' }
    vx = [-ux[1], ux[0]]
    shots = [
      ['roof_aerial', [c[0] - ux[0] * 18 - vx[0] * 18, c[1] - ux[1] * 18 - vx[1] * 18, c[2] + 14], c, [0, 0, 1], 50],
      ['roof_aerial2', [c[0] + ux[0] * 16 + vx[0] * 20, c[1] + ux[1] * 16 + vx[1] * 20, c[2] + 10], c, [0, 0, 1], 50],
      ['roof_top', [c[0], c[1], c[2] + 45], c, ux + [0], 45],
      ['roof_from_below', [c[0] - ux[0] * (len * 0.3), c[1] - ux[1] * (len * 0.3), c[2] - 2.3],
       [c[0] + ux[0] * 3, c[1] + ux[1] * 3, c[2] + 1.0], [0, 0, 1], 90]
    ]
    shots.each do |name, eye, tgt, up, fov|
      view.camera = Sketchup::Camera.new(U.to_point(eye), U.to_point(tgt), Geom::Vector3d.new(*up), true, fov)
      if name == 'roof_from_below'
        # what is around the camera? record the first hit straight down and up
        dn = model.raytest([U.to_point(eye), Geom::Vector3d.new(0, 0, -1)])
        upr = model.raytest([U.to_point(eye), Geom::Vector3d.new(0, 0, 1)])
        File.write(File.join(out_dir, 'below_cam.txt'), "eye #{eye.map { |q| q.round(2) }} down #{dn && U.point(dn[0])} up #{upr && U.point(upr[0])}
")
      end
      view.write_image(filename: File.join(out_dir, "#{name}.png"), width: 1600, height: 1000, antialias: true,
                       transparent: false)
    end
    model.definitions.each { |d| d.instances.each { |i| i.hidden = false } if d.name == '组#5' }
  end
end
