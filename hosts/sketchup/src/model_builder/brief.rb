module ModelBuilder
  # Renders a packet as a short Markdown brief: the task in plain language,
  # with absolute paths, so any agent (or person) can pick it up without
  # knowing the schema. The JSON packet stays the source of truth.
  module Brief
    def self.around_lines(sur, f3)
      return [] unless sur

      out = []
      lv = sur[:level] || {}
      if lv[:floor] || lv[:ceiling]
        out << "- level here: floor z #{lv[:floor] ? lv[:floor].round(3) : '—'}#{lv[:floor_on] ? " (#{lv[:floor_on]})" : ''}, " \
               "ceiling z #{lv[:ceiling] ? lv[:ceiling].round(3) : 'open sky'}#{lv[:ceiling_on] ? " (#{lv[:ceiling_on]})" : ''}"
      end
      (sur[:nearby] || []).each do |n|
        nm = n[:name].to_s.empty? ? n[:definition] : n[:name]
        out << "- around: #{n[:contains_point] ? '**contains the mark** ' : ''}#{nm} [tag #{n[:tag]}] `#{n[:ref]}` " \
               "#{f3.(n[:bounds][:min])}..#{f3.(n[:bounds][:max])}, #{n[:faces]} faces, #{n[:children]} sub-groups"
      end
      out
    end

    def self.render(packet, session_dir)
      abs = ->(rel) { File.join(session_dir, rel).tr('/', '\\') }
      f3 = ->(v) { "(#{v.map { |c| format('%.3f', c) }.join(', ')})" }
      out = []
      out << "# Model Builder task #{packet[:packet_id]}"
      out << ''
      out << "- Model: #{packet[:model][:name].to_s.empty? ? '(untitled)' : packet[:model][:name]}" \
             "#{packet[:model][:path] ? " (`#{packet[:model][:path]}`)" : ''}"
      out << "- Host: SketchUp #{packet[:host][:version]}, user sees #{packet[:host][:model_units]}; " \
             '**all values below are meters, Z up, world coordinates**'
      out << "- Level of detail: #{packet[:lod]}"
      out << "- Packet (source of truth): `#{abs.("packets/#{packet[:packet_id]}.json")}`"
      out << "- **Project notes (read first, update when done):** `#{packet[:project_notes]}`" if packet[:project_notes]
      out << ''
      unless (packet[:warnings] || []).empty?
        out << '## Warnings (checked by the plugin at export)'
        out << ''
        packet[:warnings].each { |w| out << "- #{w}" }
        out << ''
      end
      unless (packet[:cad_imports] || []).empty?
        out << '## Imported CAD in the model'
        out << ''
        packet[:cad_imports].each do |c|
          out << "- #{c[:name]} (`#{c[:ref]}`): origin #{f3.(c[:origin])}, rotation #{c[:rotation_z_deg]}°, " \
                 "registration: **#{c[:registration]}**"
        end
        out << ''
      end
      out << '## Task'
      out << ''
      out << (packet[:message].to_s.empty? ? '_(no message given)_' : packet[:message])
      out << ''

      out << '## Images'
      out << ''
      packet[:views].each do |v|
        what = v[:kind] == 'annotated' ? 'current view with the pins/outlines drawn in' : 'current view, clean'
        out << "- #{v[:kind]}: `#{abs.(v[:path])}` (#{what})"
      end
      (packet[:references] || []).each do |r|
        if r[:model_ref]
          out << "- reference #{r[:id]} (#{r[:kind]}): **in the model**, `#{r[:model_ref]}` #{r[:name]}" \
                 "#{r[:note] ? " - #{r[:note]}" : ''}"
          next
        end
        size = r[:size_px] ? " #{r[:size_px].join('x')} px" : ''
        out << "- reference #{r[:id]} (#{r[:kind]}#{size}): `#{abs.(r[:file])}`#{r[:note] ? " - #{r[:note]}" : ''}" \
               " (from `#{r[:source]}`)"
        out << "  - preview (downscaled, view this first): `#{abs.(r[:preview])}`" if r[:preview]
      end
      out << ''

      unless (packet[:strokes] || []).empty?
        out << '## Outlines'
        out << ''
        packet[:strokes].each do |s|
          m = s[:metrics] || {}
          size = m[:area_m2] ? "area #{m[:area_m2]} m², perimeter #{m[:length_m]} m" : "length #{m[:length_m]} m"
          out << "### #{s[:id].upcase}: #{s[:kind]}#{s[:note] ? " - #{s[:note]}" : ''}"
          out << ''
          out << "- #{s[:world].size} points, #{size}, centroid #{f3.(m[:centroid])}"
          out << "- extent x #{m[:bounds][:min][0].round(3)}..#{m[:bounds][:max][0].round(3)}, " \
                 "y #{m[:bounds][:min][1].round(3)}..#{m[:bounds][:max][1].round(3)}, " \
                 "z #{m[:bounds][:min][2].round(3)}..#{m[:bounds][:max][2].round(3)}" if m[:bounds]
          out << "- plane normal #{f3.(m[:normal])}" if m[:normal]
          out << "- surface normals at the points spread #{m[:normal_spread_deg]}°" if m[:normal_spread_deg]
          hidden = (s[:points_visible] || []).each_index.reject { |i| s[:points_visible][i] }.map { |i| i + 1 }
          out << "- points hidden behind geometry in the screenshot: #{hidden.join(', ')}" unless hidden.empty?
          out << "- points (snap): #{s[:world].each_with_index.map { |p, i| "#{f3.(p)} #{s[:point_snaps][i]}" }.join('; ')}"
          s[:hit_names].each_with_index { |n, i| out << "- touches: #{n} (`#{s[:hit_paths][i].join(' > ')}`)" }
          out.concat(around_lines(s[:surroundings], f3))
          out << ''
        end
      end

      unless packet[:pins].empty?
        out << '## Pins'
        out << ''
        packet[:pins].each do |p|
          out << "### #{p[:id].upcase}#{p[:note] ? " - #{p[:note]}" : ''}"
          out << ''
          out << "- point #{f3.(p[:point])}#{p[:normal] ? ", normal #{f3.(p[:normal])}" : ''}, snap #{p[:snap]}" \
                 "#{p[:front_facing] == false ? ', **face seen from behind**' : ''}"
          out << "- on: #{Refs.breadcrumb(p[:path_detail])}"
          out << "- path: `#{p[:entity][:path].join(' > ')}`"
          if p[:instance] && p[:instance][:bounds]
            b = p[:instance][:bounds]
            out << "- containing #{p[:instance][:kind]} bounds #{f3.(b[:min])} .. #{f3.(b[:max])}"
          end
          if (c = p.dig(:instance, :contents))
            parts = ["#{c[:faces]} faces", "#{c[:instances]} groups/components"]
            parts << "tags #{c[:tags].map { |t| "#{t[:name]} ×#{t[:count]}" }.join(', ')}" if c[:tags]
            parts << "materials #{c[:materials].map { |t| "#{t[:name]} ×#{t[:count]}" }.join(', ')}" if c[:materials]
            out << "- it contains: #{parts.join('; ')}"
          end
          out.concat(around_lines(p[:surroundings], f3))
          state = if !p[:in_frame] then ' (outside the frame)'
                  elsif p[:visible] == false then ' (hidden behind geometry)'
                  else ''
                  end
          out << "- image pixel #{p[:screen_px].inspect}#{state}"
          out << ''
        end
      end

      cam = packet[:camera]
      out << '## Camera'
      out << ''
      out << "eye #{f3.(cam[:eye])}, target #{f3.(cam[:target])}, " \
             "#{cam[:perspective] ? "perspective #{cam[:fov_deg]}° (#{cam[:fov_axis]})" : "parallel, height #{cam[:ortho_height_m]} m"}, " \
             "image #{cam[:viewport_px].join('x')} px"
      out << ''
      out.join("\n")
    end
  end
end
