require 'json'
require 'fileutils'

module ModelBuilder
  # A task = one AI Build request. Stages:
  #   planning   -> the agent inspects the model (read-only: every script is
  #                 rolled back) and writes plan.md. No prompts to the designer.
  #   plan_ready -> waits for the designer: Approve & build / Revise / Cancel.
  #   building   -> the agent builds without interruption (approval was the plan).
  #   done       -> report in reply.md; designer Accepts or Rejects.
  #
  #   <session>/tasks/<task_id>/
  #     prompt.md, prompt_build.md   instructions for the two stages
  #     plan.md, reply.md            written by the agent
  #     thread.jsonl                 conversation + events
  #     inbox/ outbox/               live link (tools/mb_exec.py)
  #     agent_plan.log, agent_build.log, exit_*.txt   agent program output
  module Tasks
    Task = Struct.new(:id, :dir, :session_dir, :agent, :status, :model_dir, :brief_path, :packet_path,
                      :created, :log_pos, :seen_files, :started_at, :tokens, :cost_usd, :title,
                      :run, :session_ref, :scripts, :last_step, keyword_init: true) do
      def prompt_path = File.join(dir, 'prompt.md')
      def build_prompt_path = File.join(dir, 'prompt_build.md')
      def log_path = File.join(dir, "agent_#{run}.log")
      def exit_path = File.join(dir, "exit_#{run}.txt")
      def thread_path = File.join(dir, 'thread.jsonl')
      def plan_path = File.join(dir, 'plan.md')
      def reply_path = File.join(dir, 'reply.md')
      def inbox = File.join(dir, 'inbox')
      def outbox = File.join(dir, 'outbox')
      def running? = %w[planning building].include?(status)
      def api? = agent.to_s.start_with?('api:')
      def cli? = !api? && !%w[manual antigravity].include?(agent)
    end

    @tasks ||= {}
    @current ||= nil
    @timer ||= nil
    @listeners ||= []

    class << self
      attr_reader :current

      def all = @tasks.values

      def on_change(&block)
        @listeners << block
      end

      def notify
        @listeners.each do |l|
          l.call
        rescue StandardError => e
          Log.error('Task listener failed', e)
        end
      end
    end

    def self.mb_exec_path
      File.join(Agents.repo_root, 'tools', 'mb_exec.py')
    end

    # ---- start ---------------------------------------------------------------

    def self.send_task(model, agent, **_ignored)
      raise 'A task is still running. Cancel it or wait.' if @current&.running? || @sending

      @sending = true # export/launch can pump the message loop: guard double sends
      begin
        start(model, agent)
      ensure
        @sending = false
      end
    end

    def self.start(model, agent)
      exp = Exporter.export(model)
      tid = "t_#{Time.now.strftime('%H%M%S')}"
      dir = File.expand_path(File.join(Exporter.session_dir, 'tasks', tid)) # forward slashes: Dir.glob-safe
      FileUtils.mkdir_p(File.join(dir, 'inbox'))
      FileUtils.mkdir_p(File.join(dir, 'outbox'))
      msg = exp[:packet][:message].to_s
      t = Task.new(id: tid, dir: dir, session_dir: File.expand_path(Exporter.session_dir), agent: agent, status: 'planning',
                   model_dir: model.path.to_s.empty? ? File.expand_path(Exporter.session_dir) : File.dirname(model.path),
                   brief_path: exp[:brief_path], packet_path: exp[:packet_path], created: [], log_pos: 0,
                   seen_files: {}, started_at: Time.now, tokens: 0, cost_usd: nil, title: msg.empty? ? 'task' : msg[0, 60],
                   run: 'plan', session_ref: nil, scripts: 0, last_step: nil)
      @tasks[tid] = t
      @current = t
      File.write(t.prompt_path, Prompts.plan(t, exp), mode: 'w:UTF-8')
      marks = exp[:packet][:pins].map { |p| p[:id] } + (exp[:packet][:strokes] || []).map { |s| s[:id].upcase } +
              (exp[:packet][:references] || []).map { |r| r[:id] }
      event(t, 'user', msg.empty? ? '(no description)' : msg, marks: marks, agent: agent)
      (exp[:warnings] || []).each { |w| event(t, 'warning', w) }
      launch(t, 'plan')
      ensure_timer
      notify
      t
    end

    def self.launch(t, run, extra = nil)
      t.run = run
      t.log_pos = 0
      if t.agent == 'manual'
        file = run == 'plan' ? t.prompt_path : t.build_prompt_path
        Sketchup.set_clipboard_text(File.read(file, encoding: 'UTF-8')) if Sketchup.respond_to?(:set_clipboard_text)
        step(t, run == 'plan' ? 'Waiting for your agent: give it prompt.md.' : 'Give your agent prompt_build.md.')
        event(t, 'system', "Prompt for your agent: #{file}", files: [file])
      elsif t.api?
        run == 'plan' ? ApiAgent.start(t) : ApiAgent.resume(t, extra)
      else
        resume = run == 'plan' ? nil : t.session_ref
        Agents.launch(t.agent, t, stdin: run == 'plan' ? t.prompt_path : t.build_prompt_path, resume: resume)
        label = Agents::CLI.dig(t.agent, :label) || t.agent
        step(t, t.agent == 'antigravity' ? "Opened in #{label}." : "#{label} is #{run == 'plan' ? 'planning' : 'building'}…")
      end
    rescue StandardError => e
      t.status = 'failed'
      event(t, 'error', "Could not start the agent: #{e.message}")
      Log.error('Agent start failed', e)
    end

    # ---- designer decisions ------------------------------------------------------

    def self.approve(t = @current, comment = nil)
      return unless t && t.status == 'plan_ready'

      event(t, 'user', comment.to_s.strip.empty? ? 'Plan approved. Build it.' : "Plan approved: #{comment}")
      t.status = 'building'
      File.write(t.build_prompt_path, Prompts.build(t, comment), mode: 'w:UTF-8')
      launch(t, 'build', comment)
      notify
    end

    def self.revise(t = @current, comment = '')
      return unless t && t.status == 'plan_ready'

      event(t, 'user', "Revise the plan: #{comment}")
      t.status = 'planning'
      File.delete(t.plan_path) if File.exist?(t.plan_path)
      t.seen_files.delete('plan.md')
      if t.api?
        ApiAgent.revise(t, comment)
      else
        rev = File.join(t.dir, 'prompt_revise.md')
        File.write(rev, Prompts.revise(t, comment, resumed: !t.session_ref.nil?), mode: 'w:UTF-8')
        t.run = 'plan'
        t.log_pos = 0
        if t.agent == 'manual'
          event(t, 'system', "Give your agent: #{rev}", files: [rev])
        else
          Agents.launch(t.agent, t, stdin: rev, resume: t.session_ref)
          step(t, 'Revising the plan…')
        end
      end
      notify
    end

    def self.cancel(t = @current)
      return unless t && (t.running? || t.status == 'plan_ready')

      t.status = 'cancelled'
      ApiAgent.cancel(t) if t.api?
      event(t, 'system', 'Cancelled. Scripts sent after this are refused.')
    end

    # Reject = delete the top-level objects the build created.
    def self.reject(t = @current)
      return unless t

      model = Sketchup.active_model
      ents = t.created.filter_map { |pid| model.find_entity_by_persistent_id(pid) }.select(&:valid?)
      model.start_operation("AI Build: reject #{t.id}", true)
      ents.each(&:erase!)
      model.commit_operation
      t.status = 'rejected'
      event(t, 'system', "Rejected: removed #{ents.size} object(s).")
    end

    def self.accept(t = @current)
      return unless t

      t.status = 'accepted'
      event(t, 'system', "Accepted: kept #{t.created.size} object(s).")
    end

    # ---- events ----------------------------------------------------------------

    def self.event(t, role, text, data = {})
      ev = { t: Time.now.strftime('%H:%M:%S'), role: role, text: text.to_s }.merge(data)
      File.open(t.thread_path, 'a:UTF-8') { |f| f.puts(JSON.generate(ev)) }
      notify
      ev
    end

    # A quiet progress line (shown as one status line, not as a conversation entry).
    def self.step(t, text)
      t.last_step = text.to_s.strip[0, 200]
      notify
    end

    def self.events(t)
      return [] unless t && File.file?(t.thread_path)

      File.readlines(t.thread_path, encoding: 'UTF-8').filter_map do |l|
        JSON.parse(l)
      rescue JSON::ParserError
        nil
      end
    end

    # ---- polling ---------------------------------------------------------------

    def self.ensure_timer
      return if @timer

      @timer = UI.start_timer(0.5, true) { poll }
    end

    def self.poll
      return if @polling

      @polling = true
      @tasks.each_value do |t|
        LiveLink.process(t)
        read_log(t) if t.cli?
        watch_files(t)
        next unless t.cli? && t.running? && File.file?(t.exit_path)

        read_log(t)
        File.delete(t.exit_path)
        program_ended(t)
      end
    rescue StandardError => e
      Log.error('Task poll failed', e)
    ensure
      @polling = false
    end

    def self.program_ended(t)
      if t.status == 'planning'
        if File.file?(t.plan_path)
          plan_ready(t)
        else
          t.status = 'failed'
          event(t, 'error', 'The agent stopped without writing a plan.')
        end
      elsif t.status == 'building'
        finish(t)
      end
    end

    def self.plan_ready(t)
      watch_files(t)
      t.status = 'plan_ready'
      step(t, 'Plan ready. Approve to build, or revise.')
    end

    def self.finish(t)
      watch_files(t)
      t.status = 'done'
      step(t, File.file?(t.reply_path) ? 'Done. Review the result, then Accept or Reject.' : 'Agent ended (no report).')
    end

    # plan.md / reply.md -> conversation. For agents we cannot watch (IDE,
    # manual), the files themselves move the task forward.
    def self.watch_files(t)
      { 'plan.md' => 'plan', 'reply.md' => 'reply' }.each do |f, role|
        path = File.join(t.dir, f)
        next unless File.file?(path)

        mtime = File.mtime(path).to_f
        next if t.seen_files[f] == mtime

        t.seen_files[f] = mtime
        event(t, role, File.read(path, encoding: 'UTF-8'))
        next if t.cli? || t.api?

        plan_ready(t) if role == 'plan' && t.status == 'planning'
        finish(t) if role == 'reply' && t.status == 'building'
      end
    end

    # Claude Code stream-json (one JSON object per line); other programs: raw text.
    def self.read_log(t)
      return unless File.file?(t.log_path)

      data = File.binread(t.log_path)
      return if data.bytesize <= t.log_pos

      chunk = data.byteslice(t.log_pos, data.bytesize - t.log_pos)
      last_nl = chunk.rindex("\n") or return
      t.log_pos += last_nl + 1
      chunk[0..last_nl].force_encoding('UTF-8').scrub.each_line do |line|
        line = line.strip
        handle_line(t, line) unless line.empty?
      end
    end

    def self.handle_line(t, line)
      j = line.start_with?('{') ? (JSON.parse(line) rescue nil) : nil
      unless j
        step(t, line)
        return
      end
      t.session_ref ||= j['session_id']
      case j['type']
      when 'assistant'
        (j.dig('message', 'content') || []).each do |c|
          case c['type']
          when 'text' then step(t, c['text'].to_s.strip.lines.first.to_s) unless c['text'].to_s.strip.empty?
          when 'tool_use' then step(t, tool_summary(c['name'], c['input']))
          end
        end
      when 'result'
        t.cost_usd = (t.cost_usd || 0) + j['total_cost_usd'].to_f
        u = j['usage'] || {}
        t.tokens += u.values_at('input_tokens', 'output_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens').compact.sum
      end
    end

    def self.tool_summary(name, input)
      input ||= {}
      detail = input['description'] || input['command'] || input['file_path'] || input['pattern'] || ''
      "#{name}: #{detail.to_s.gsub(/\s+/, ' ')[0, 140]}"
    end
  end
end
