require 'json'
require 'base64'
require 'fileutils'

module ModelBuilder
  # Direct-API agent: the plugin runs the tool loop against a provider
  # (OpenAI-compatible, e.g. DeepSeek, or Anthropic), in two stages:
  #   plan  : run_ruby (read-only, rolled back) + submit_plan  -> pauses for the designer
  #   build : run_ruby (takes effect)          + finish        -> report
  # Requests are asynchronous (Sketchup::Http), so SketchUp stays responsive.
  module ApiAgent
    LIMITS = { 'plan' => 15, 'build' => 30 }.freeze
    TOKEN_BUDGET = 400_000
    MAX_TOOL_RESULT = 6000
    MAX_TOKENS = 4096

    @runs ||= {}

    def self.system_prompt(vision, has_images)
      <<~TXT
        You are the operational agent for Model Builder, a SketchUp plugin. A designer marked a place in their OPEN
        SketchUp model and asked for something to be built there. You act on the model only through run_ruby.
        run_ruby code must define:
          module MBScript
            def self.run(model, out_dir)
              ...           # SketchUp Ruby API (internal unit: inches)
              "short text"  # what you get back; keep it short (JSON is fine)
            end
          end
        #{Prompts.kit_help}
        The brief lists each mark with the geometry AROUND it: start from that instead of surveying the model.
        Work in two stages:
        STAGE 1 (now): plan. run_ruby is READ-ONLY here (everything is rolled back): use a few targeted queries only.
          Then call submit_plan with: the task in 1-2 sentences, where (coordinates, level, host element), what you
          will build (elements, sizes, materials, which reference), assumptions, questions. Then wait.
        STAGE 2 (after the designer approves): build with run_ruby into ONE group from ModelBuilder::Kit.proposal(title),
          do not change existing geometry unless the plan says so, check once at the end, then call finish with a
          short report. The designer does not answer questions during the build.
        Call one tool at a time.
        #{!vision && has_images ? 'You CANNOT see images. The references include images: say in your plan what you assume they show and ask the designer to confirm.' : ''}
      TXT
    end

    TOOLS = [
      { name: 'run_ruby', description: 'Run SketchUp Ruby in the open model. STAGE 1: read-only (rolled back). STAGE 2: takes effect.',
        params: { code: 'Ruby source defining MBScript.run(model, out_dir)', purpose: 'one line: what this script does' }, required: %w[code] },
      { name: 'submit_plan', description: 'Stage 1 only: show the designer your plan and wait for approval.',
        params: { plan: 'Markdown plan' }, required: %w[plan] },
      { name: 'finish', description: 'Stage 2 only: end the task with a short report for the designer.',
        params: { report: 'Markdown: what you built, deviations, open questions' }, required: %w[report] }
    ].freeze

    def self.start(task)
      pid = task.agent.sub('api:', '')
      cfg = Agents.provider_config(pid) or raise "Unknown provider #{pid}"
      key = Agents.api_key(pid) or raise "#{cfg[:env]} is not set. Add the key with + in the AI Build dialog."
      raise "No model name set for #{cfg[:label]}" if cfg[:model].to_s.empty?

      packet = JSON.parse(File.read(task.packet_path, encoding: 'UTF-8'))
      images = cfg[:vision] ? images_for(task, packet) : []
      has_images = (packet['references'] || []).any? { |r| r['file'].to_s =~ /\.(png|jpe?g|bmp|gif|webp|tiff?)\z/i }
      brief = File.read(task.brief_path, encoding: 'UTF-8')
      run = { task: task, cfg: cfg, key: key, steps: 0, stage: 'plan', cancelled: false, pending: nil }
      sys = system_prompt(cfg[:vision], has_images)
      content = [{ type: 'text', text: "Brief:\n\n#{brief}" }]
      if cfg[:style] == 'anthropic'
        images.each { |label, data| content += [{ type: 'text', text: label }, { type: 'image', source: { type: 'base64', media_type: 'image/png', data: data } }] }
        run[:system] = sys
        run[:messages] = [{ role: 'user', content: content }]
      else
        images.each { |label, data| content += [{ type: 'text', text: label }, { type: 'image_url', image_url: { url: "data:image/png;base64,#{data}" } }] }
        run[:messages] = [{ role: 'system', content: sys }, { role: 'user', content: images.empty? ? content.first[:text] : content }]
      end
      @runs[task.id] = run
      Tasks.step(task, "#{cfg[:label]} · #{cfg[:model]} is planning#{images.empty? ? '' : " (sees #{images.size} image(s))"}…")
      request(run)
    end

    # PNG images for vision models: the annotated view + reference previews (max 3).
    def self.images_for(task, packet)
      out = []
      v = packet['views'].find { |x| x['kind'] == 'annotated' } || packet['views'].first
      out << ["The designer's view with the marks:", File.join(task.session_dir, v['path'])] if v
      (packet['references'] || []).each do |r|
        f = r['preview'] || r['file']
        next unless f.to_s =~ /\.png\z/i

        out << ["Reference #{r['id']} (#{r['kind']}): #{r['note']}", File.join(task.session_dir, f)]
      end
      out.first(3).select { |_, p| File.file?(p) && File.size(p) < 4_500_000 }.map { |l, p| [l, Base64.strict_encode64(File.binread(p))] }
    end

    def self.resume(task, comment)
      run = @runs[task.id] or raise 'The planning conversation was lost (SketchUp restarted?). Send the task again.'
      run[:stage] = 'build'
      run[:steps] = 0
      reply_to_pending(run, "The designer APPROVED the plan.#{comment.to_s.strip.empty? ? '' : " Comment: #{comment}"} " \
                            'STAGE 2: build it now (run_ruby takes effect), then call finish.')
      Tasks.step(task, "#{run[:cfg][:label]} is building…")
      request(run)
    end

    def self.revise(task, comment)
      run = @runs[task.id] or raise 'The planning conversation was lost. Send the task again.'
      run[:steps] = 0
      reply_to_pending(run, "The designer wants changes before approving: #{comment}\nStill STAGE 1: revise and call submit_plan again.")
      Tasks.step(task, 'Revising the plan…')
      request(run)
    end

    def self.cancel(task)
      run = @runs[task.id]
      run[:cancelled] = true if run
    end

    def self.reply_to_pending(run, text)
      c = run[:pending]
      if c.nil?
        run[:messages] << { role: 'user', content: text }
      elsif run[:cfg][:style] == 'anthropic'
        run[:messages] << { role: 'user', content: [{ type: 'tool_result', tool_use_id: c[:id], content: text }] }
      else
        run[:messages] << { role: 'tool', tool_call_id: c[:id], content: text }
      end
      run[:pending] = nil
    end

    # ---- the loop -------------------------------------------------------------

    def self.request(run)
      task = run[:task]
      return if run[:cancelled] || !task.running?

      if run[:steps] >= LIMITS[run[:stage]] || task.tokens > TOKEN_BUDGET
        why = task.tokens > TOKEN_BUDGET ? "the token budget (#{TOKEN_BUDGET})" : "#{LIMITS[run[:stage]]} steps"
        stop(run, "Stopped: reached #{why} in the #{run[:stage]} stage.")
        return
      end
      run[:steps] += 1
      url, headers, body = request_parts(run)
      req = Sketchup::Http::Request.new(url, Sketchup::Http::POST)
      req.headers = headers
      req.body = JSON.generate(body)
      run[:request] = req # keep a reference while in flight
      req.start do |_request, response|
        handle_response(run, response)
      rescue StandardError => e
        Log.error('API agent step failed', e)
        stop(run, "API step failed: #{e.message}")
      end
    end

    def self.stop(run, msg)
      task = run[:task]
      Tasks.event(task, 'error', msg)
      if run[:stage] == 'plan'
        task.status = 'failed'
        Tasks.step(task, msg)
      else
        File.write(task.reply_path, "#{msg}\n", mode: 'w:UTF-8') unless File.file?(task.reply_path)
        Tasks.finish(task)
      end
    end

    def self.tools_for(run)
      names = run[:stage] == 'plan' ? %w[run_ruby submit_plan] : %w[run_ruby finish]
      TOOLS.select { |t| names.include?(t[:name]) }
    end

    def self.request_parts(run)
      cfg = run[:cfg]
      schema = lambda do |t|
        { type: 'object', properties: t[:params].transform_values { |d| { type: 'string', description: d } }, required: t[:required] }
      end
      if cfg[:style] == 'anthropic'
        ["#{cfg[:base].chomp('/')}/v1/messages",
         { 'x-api-key' => run[:key], 'anthropic-version' => '2023-06-01', 'content-type' => 'application/json' },
         { model: cfg[:model], max_tokens: MAX_TOKENS, system: run[:system],
           tools: tools_for(run).map { |t| { name: t[:name], description: t[:description], input_schema: schema.(t) } },
           messages: run[:messages] }]
      else
        ["#{cfg[:base].chomp('/')}/chat/completions",
         { 'Authorization' => "Bearer #{run[:key]}", 'Content-Type' => 'application/json' },
         { model: cfg[:model], max_tokens: MAX_TOKENS,
           tools: tools_for(run).map { |t| { type: 'function', function: { name: t[:name], description: t[:description], parameters: schema.(t) } } },
           messages: run[:messages] }]
      end
    end

    def self.handle_response(run, response)
      task = run[:task]
      return if run[:cancelled] || !task.running?

      unless response.status_code == 200
        body = response.body.to_s[0, 800]
        if body =~ /image|vision|multimodal|unsupported/i && !run[:text_only]
          run[:text_only] = true
          strip_images(run)
          run[:steps] -= 1
          Tasks.step(task, 'The model refused images; continuing text only.')
          request(run)
          return
        end
        raise "HTTP #{response.status_code}: #{body}"
      end
      j = JSON.parse(response.body)
      calls = run[:cfg][:style] == 'anthropic' ? anthropic_turn(run, j) : openai_turn(run, j)
      if calls.empty?
        # Plain text without a tool call: take it as the plan (stage 1) or the report (stage 2).
        text = run[:last_text].to_s.strip
        text = '(no answer)' if text.empty?
        if run[:stage] == 'plan'
          File.write(task.plan_path, text, mode: 'w:UTF-8')
          Tasks.plan_ready(task)
        else
          File.write(task.reply_path, text, mode: 'w:UTF-8')
          Tasks.finish(task)
        end
        return
      end
      results = []
      calls.each do |c|
        case c[:name]
        when 'submit_plan'
          File.write(task.plan_path, c[:args]['plan'].to_s, mode: 'w:UTF-8')
          append_results(run, results)
          run[:pending] = c
          Tasks.plan_ready(task)
          return
        when 'finish'
          File.write(task.reply_path, c[:args]['report'].to_s, mode: 'w:UTF-8')
          Tasks.finish(task)
          return
        else
          results << [c, run_tool(run, c)]
        end
      end
      append_results(run, results)
      request(run)
    end

    def self.run_tool(run, call)
      task = run[:task]
      return "Unknown tool #{call[:name]}" unless call[:name] == 'run_ruby'

      dir = File.join(task.dir, 'api_scripts') # outside inbox/: the live-link timer never re-runs it
      FileUtils.mkdir_p(dir)
      name = format('%03d_%s', Dir.glob(File.join(dir, '*.rb')).size + 1, run[:stage])
      File.write(File.join(dir, "#{name}.rb"), call[:args]['code'].to_s, mode: 'w:UTF-8')
      Tasks.step(task, call[:args]['purpose'] || name)
      res = LiveLink.execute(task, call[:args]['code'].to_s, name)
      File.write(File.join(dir, "#{name}.json"), JSON.pretty_generate(res), mode: 'w:UTF-8')
      JSON.generate(res)[0, MAX_TOOL_RESULT]
    end

    def self.strip_images(run)
      run[:messages].each do |m|
        next unless m[:content].is_a?(Array)

        m[:content] = m[:content].reject { |c| %w[image image_url].include?(c[:type]) }
        m[:content] = m[:content].map { |c| c[:text] }.join("\n") if run[:cfg][:style] != 'anthropic' && m[:role] == 'user'
      end
    end

    def self.anthropic_turn(run, j)
      task = run[:task]
      task.tokens += j.dig('usage', 'input_tokens').to_i + j.dig('usage', 'output_tokens').to_i
      content = j['content'] || []
      run[:messages] << { role: 'assistant', content: content }
      run[:last_text] = content.select { |c| c['type'] == 'text' }.map { |c| c['text'] }.join("\n").strip
      Tasks.step(task, run[:last_text].lines.first.to_s) unless run[:last_text].empty?
      content.select { |c| c['type'] == 'tool_use' }.map { |c| { id: c['id'], name: c['name'], args: c['input'] || {} } }
    end

    def self.openai_turn(run, j)
      task = run[:task]
      task.tokens += j.dig('usage', 'prompt_tokens').to_i + j.dig('usage', 'completion_tokens').to_i
      msg = j.dig('choices', 0, 'message') || {}
      run[:messages] << msg.slice('role', 'content', 'tool_calls').merge('role' => 'assistant')
      run[:last_text] = msg['content'].to_s.strip
      Tasks.step(task, run[:last_text].lines.first.to_s) unless run[:last_text].empty?
      (msg['tool_calls'] || []).map do |c|
        args = begin
          JSON.parse(c.dig('function', 'arguments').to_s)
        rescue JSON::ParserError
          {}
        end
        { id: c['id'], name: c.dig('function', 'name'), args: args }
      end
    end

    def self.append_results(run, results)
      return if results.empty?

      if run[:cfg][:style] == 'anthropic'
        run[:messages] << { role: 'user', content: results.map { |c, r| { type: 'tool_result', tool_use_id: c[:id], content: r } } }
      else
        results.each { |c, r| run[:messages] << { role: 'tool', tool_call_id: c[:id], content: r } }
      end
    end
  end
end
