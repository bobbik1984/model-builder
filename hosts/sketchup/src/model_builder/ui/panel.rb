require 'json'

module ModelBuilder
  # The AI Build request dialog (HtmlDialog).
  #   compose : marks (from the AI Build tool), description, attachments,
  #             "Send to" (agents on this computer / API models, + to add one)
  #   follow  : one status line; the plan with Approve & build / Revise;
  #             the report with Accept / Reject. Details are collapsed.
  # No modal pop-ups during a task.
  module Panel
    REF_FILTER = 'Attachments (images, DWG/DXF, PDF)|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif;*.webp;*.dwg;*.dxf;*.pdf||'.freeze
    FINISHED = %w[accepted rejected cancelled failed].freeze

    @dialog ||= nil
    @shown_task ||= nil

    def self.show(focus: false)
      if @dialog&.visible?
        @dialog.bring_to_front if focus
        push
        return
      end
      @dialog = UI::HtmlDialog.new(dialog_title: 'AI Build', preferences_key: 'ModelBuilder.AIBuild',
                                   width: 400, height: 640, min_width: 340, min_height: 360,
                                   style: UI::HtmlDialog::STYLE_DIALOG, scrollable: true, resizable: true)
      @dialog.set_file(File.join(__dir__, 'panel.html'))
      @dialog.add_action_callback('mb') do |_ctx, action, payload|
        ModelBuilder.guard("AI Build: #{action}", notify: true) do
          handle(action.to_s, payload.to_s.empty? ? {} : JSON.parse(payload.to_s))
        end
      end
      @dialog.set_on_closed { @dialog = nil }
      @dialog.show
      Tasks.on_change { push } unless @listening
      @listening = true
      start_refresh
    end

    def self.visible? = @dialog&.visible?

    def self.start_refresh
      return if @timer

      @timer = UI.start_timer(1.0, true) do
        next unless visible?

        sig = signature
        push if sig != @last_sig
      end
    end

    def self.signature
      m = Sketchup.active_model
      t = shown
      [PinStore.pins(m).map { |p| [p.id, p.data[:note]] }, MarkupStore.strokes(m).map { |s| [s.id, s.note] },
       MarkupStore.references(m).map(&:id), m.title, t&.status, t&.last_step, t&.tokens].hash
    end

    def self.push
      return unless visible?

      @last_sig = signature
      @dialog.execute_script("MB.render(#{JSON.generate(state)})")
    rescue StandardError => e
      Log.error('AI Build dialog update failed', e)
    end

    def self.shown
      t = @shown_task || Tasks.current
      t && @hide_finished && FINISHED.include?(t.status) ? nil : t
    end

    def self.state
      m = Sketchup.active_model
      t = shown
      ev = Tasks.events(t)
      {
        model: m.title.to_s.empty? ? '(untitled)' : m.title,
        version: VERSION,
        marks: PinStore.pins(m).map { |p| { id: p.id, kind: 'pin', note: p.data[:note].to_s } } +
               MarkupStore.strokes(m).map { |s| { id: s.id, kind: s.kind, note: s.note.to_s, n: s.points.size } },
        refs: MarkupStore.references(m).map do |r|
          { id: r.id, kind: r.kind, name: r.model_ref ? "#{r.model_ref} (in model)" : File.basename(r.source.to_s),
            image: r.source.to_s =~ /\.(png|jpe?g|bmp|gif|webp|tiff?)\z/i ? true : false }
        end,
        message: MarkupStore.message(m), lod: MarkupStore.lod(m), lods: MarkupStore::LODS,
        agents: Agents.list, agent: Agents.default_agent,
        task: t && { id: t.id, status: t.status, agent: t.agent, step: t.last_step, tokens: t.tokens, cost: t.cost_usd,
                     created: t.created.size, scripts: t.scripts, title: t.title,
                     seconds: (Time.now - t.started_at).round },
        plan: ev.reverse.find { |e| e['role'] == 'plan' }&.dig('text'),
        report: ev.reverse.find { |e| e['role'] == 'reply' }&.dig('text'),
        log: ev.last(200)
      }
    end

    # ---- actions ---------------------------------------------------------------

    def self.handle(action, p)
      m = Sketchup.active_model
      t = shown
      case action
      when 'ready' then nil
      when 'mark' then Sketchup.active_model.select_tool(AiBuildTool.new)
      when 'note' then edit_note(p['id'])
      when 'delete' then ModelBuilder.delete_mark(p['id'])
      when 'clear_marks' then ModelBuilder.clear_markup
      when 'attach' then attach_file(m)
      when 'attach_selection' then attach_selection(m)
      when 'unattach' then MarkupStore.remove_reference(p['id'], m)
      when 'set' then apply_fields(m, p)
      when 'send'
        apply_fields(m, p)
        @shown_task = nil
        @hide_finished = false
        Tasks.send_task(m, p['agent'].to_s)
      when 'approve' then Tasks.approve(t, p['comment'])
      when 'revise' then Tasks.revise(t, p['comment'].to_s)
      when 'cancel' then Tasks.cancel(t)
      when 'accept' then Tasks.accept(t)
      when 'reject' then Tasks.reject(t)
      when 'new'
        @hide_finished = true
        @shown_task = nil
      when 'add_api' then add_api(p)
      when 'save_key'
        spec = Agents.providers[p['provider']]
        Agents.save_env(spec[:env], p['key']) if spec && !p['key'].to_s.strip.empty?
      when 'set_model' then Agents.set_setting("model_#{p['provider']}", p['model'])
      when 'test_key' then test_key(p['provider'])
      when 'open_folder' then Exporter.open_folder(t ? t.dir : Exporter.sessions_root)
      when 'open_file' then UI.openURL("file:///#{p['path'].to_s.tr('\\', '/')}") if File.exist?(p['path'].to_s)
      end
      push
    end

    def self.apply_fields(m, p)
      MarkupStore.set_task(m, p['message'].to_s, p['lod'].to_s) if p.key?('message')
      Agents.set_setting('agent', p['agent']) if p['agent']
    end

    def self.edit_note(id)
      if (pin = PinStore.find(id)) then ModelBuilder.edit_pin_note(pin)
      elsif (s = MarkupStore.find_stroke(id)) then ModelBuilder.edit_stroke_note(s)
      end
    end

    def self.kind_for(path)
      case File.extname(path).downcase
      when '.dwg', '.dxf' then 'cad'
      when '.pdf' then 'pdf'
      else File.basename(path).downcase =~ /sketch|detail|草图|大样|节点|section|剖/ ? 'sketch' : 'render'
      end
    end

    def self.attach_file(m)
      path = UI.openpanel('Attach (image, DWG/DXF, PDF)', @last_dir, REF_FILTER)
      return unless path

      @last_dir = File.dirname(path)
      MarkupStore.add_reference(m, path, kind_for(path))
    end

    def self.attach_selection(m)
      sel = m.selection.select { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
      return UI.messagebox('Select the imported DWG (or a group/component) in the model first.') if sel.empty?

      sel.each { |e| MarkupStore.add_reference(m, nil, 'cad_in_model', nil, model_ref: Refs.ref(e)) }
    end

    def self.add_api(p)
      raise 'Name, base URL and model are required.' if %w[label base model].any? { |k| p[k].to_s.strip.empty? }

      id = Agents.add_provider(label: p['label'].strip, style: p['style'] == 'anthropic' ? 'anthropic' : 'openai',
                               base: p['base'].strip, model: p['model'].strip, env: p['env'].to_s,
                               vision: p['vision'] == true, key: p['key'])
      Agents.set_setting('agent', "api:#{id}")
    end

    def self.test_key(provider)
      cfg = Agents.provider_config(provider) or return
      key = Agents.api_key(provider)
      return Agents.set_setting("keystatus_#{provider}", 'no key') unless key

      if cfg[:style] == 'anthropic'
        url = "#{cfg[:base].chomp('/')}/v1/messages"
        headers = { 'x-api-key' => key, 'anthropic-version' => '2023-06-01', 'content-type' => 'application/json' }
      else
        url = "#{cfg[:base].chomp('/')}/chat/completions"
        headers = { 'Authorization' => "Bearer #{key}", 'Content-Type' => 'application/json' }
      end
      Agents.set_setting("keystatus_#{provider}", 'testing…')
      @test_req = Sketchup::Http::Request.new(url, Sketchup::Http::POST)
      @test_req.headers = headers
      @test_req.body = JSON.generate(model: cfg[:model], max_tokens: 5, messages: [{ role: 'user', content: 'ping' }])
      @test_req.start do |_r, res|
        Agents.set_setting("keystatus_#{provider}", res.status_code == 200 ? 'valid' : "invalid (HTTP #{res.status_code})")
        push
      end
    end
  end
end
