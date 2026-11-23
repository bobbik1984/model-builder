require 'json'
require 'fileutils'

module ModelBuilder
  # Live link: lets an agent act on the model that is OPEN in SketchUp.
  # The agent drops a Ruby script into <task>/inbox (tools/mb_exec.py does
  # this); the plugin runs it and writes <task>/outbox/<name>.json.
  #
  # No dialogs (they interrupted the designer every few seconds, 2026-11-08):
  #   planning -> READ-ONLY: the script runs inside an operation that is always
  #               aborted, so nothing it does survives (queries are free)
  #   building -> the approved plan is the permission: each script is one undo step
  #   otherwise -> refused
  module LiveLink
    MAX_RESULT_CHARS = 20_000

    def self.process(task)
      return unless File.directory?(task.inbox)

      Dir.glob(File.join(task.inbox, '*.rb')).sort.each do |script|
        name = File.basename(script, '.rb')
        out = File.join(task.outbox, "#{name}.json")
        next if File.exist?(out)

        result = execute(task, File.read(script, encoding: 'UTF-8'), name)
        File.write("#{out}.tmp", JSON.pretty_generate(result), mode: 'w:UTF-8')
        File.rename("#{out}.tmp", out)
      end
    end

    # Runs agent Ruby code (must define MBScript.run(model, out_dir)).
    def self.execute(task, code, name)
      mode = case task.status
             when 'planning' then :read_only
             when 'building' then :build
             end
      unless mode
        return { ok: false, error: "Task #{task.id} is '#{task.status}': scripts are not accepted now." }
      end

      model = Sketchup.active_model
      out_dir = File.join(task.outbox, "#{name}_files")
      FileUtils.mkdir_p(out_dir)
      before = model.entities.map(&:persistent_id)
      view = model.active_view
      cam = view.camera
      saved_cam = Sketchup::Camera.new(cam.eye, cam.target, cam.up, cam.perspective?, cam.perspective? ? cam.fov : 30)
      saved_cam.height = cam.height unless cam.perspective?
      t0 = Time.now
      task.scripts += 1
      Object.send(:remove_const, :MBScript) if Object.const_defined?(:MBScript)
      model.start_operation("AI Build #{task.id}: #{name}", true)
      begin
        TOPLEVEL_BINDING.eval(code, "#{name}.rb")
        raise 'Script did not define MBScript.run(model, out_dir)' unless Object.const_defined?(:MBScript) &&
                                                                         ::MBScript.respond_to?(:run)

        result = ::MBScript.run(model, out_dir)
        if mode == :read_only
          model.abort_operation
          created = []
        else
          model.commit_operation
          created = model.entities.map(&:persistent_id) - before
          task.created.concat(created)
        end
        files = Dir.glob(File.join(out_dir, '**', '*')).select { |f| File.file?(f) }
        text = result.to_s
        Tasks.step(task, "#{mode == :read_only ? 'Looked at the model' : 'Built'}: #{text.gsub(/\s+/, ' ')[0, 120]}")
        { ok: true, mode: mode, result: text[0, MAX_RESULT_CHARS], files: files, created: created.size,
          seconds: (Time.now - t0).round(1),
          note: mode == :read_only ? 'Planning stage: the model was not changed (read-only).' : nil }.compact
      rescue Exception => e # rubocop:disable Lint/RescueException
        model.abort_operation
        Tasks.step(task, "A script failed (#{e.class}); rolled back.")
        { ok: false, error: "#{e.class}: #{e.message}", backtrace: Array(e.backtrace).first(8),
          seconds: (Time.now - t0).round(1), note: 'Rolled back; the model is unchanged.' }
      ensure
        view.camera = saved_cam
        view.invalidate
      end
    end
  end
end
