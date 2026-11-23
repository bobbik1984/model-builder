# Unattended end-to-end test of the panel back end (dev only):
#   marks delete/ids, panel state, agent detection, live link round trip via
#   tools/mb_exec.py, reject, and (optional) real agent runs:
#     MB_TEST_API=deepseek    -> direct API loop
#     MB_TEST_CLAUDE=1        -> Claude Code headless
#   "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_agent_test.rb"
# Report: %LOCALAPPDATA%\ModelBuilder\selftest\agent_test.json (+ agent_test_status.txt)
require 'json'
require 'fileutils'

mb_dir = File.join(ENV['LOCALAPPDATA'] || Dir.home, 'ModelBuilder', 'selftest')
FileUtils.mkdir_p(mb_dir)
$mb_status = File.join(mb_dir, 'agent_test_status.txt')
File.write($mb_status, "started #{Time.now}\n")
def mb_log(s) = File.write($mb_status, "#{Time.now.strftime('%H:%M:%S')} #{s}\n", mode: 'a')

begin
  require File.expand_path('../src/model_builder', __dir__) unless defined?(ModelBuilder::Dev)
rescue Exception => e # rubocop:disable Lint/RescueException
  mb_log("load error #{e.class}: #{e.message}")
end

module MBAgentTest
  include ModelBuilder
  R = { problems: [], steps: {} }
  U = ModelBuilder::Units

  def self.check(cond, msg)
    R[:problems] << msg unless cond
    cond
  end

  def self.quit
    File.write(File.join(File.dirname($mb_status), 'agent_test.json'), JSON.pretty_generate(R))
    mb_log("done problems=#{R[:problems].size} #{R[:problems].join(' | ')}")
    return unless ENV['MB_AUTORUN_KEEP_OPEN'].to_s.empty?

    Sketchup.active_model.close(true) rescue nil
    Sketchup.quit
  end

  # Run blocks one after another; each returns true when finished (polled every 1 s).
  def self.sequence(steps)
    @steps = steps
    @t0 = Time.now
    @timer = UI.start_timer(1.0, true) do
      next if @busy # export/launch can pump messages and re-enter this timer

      @busy = true
      begin
        name, limit, blk = @steps.first
        if name.nil?
          UI.stop_timer(@timer)
          quit
          next
        end
        @started ||= Time.now
        finished = blk.call
        if finished || Time.now - @started > limit
          R[:problems] << "#{name}: timeout after #{limit}s" unless finished
          R[:steps][name] = { seconds: (Time.now - @started).round(1), finished: !!finished }
          mb_log("step #{name} #{finished ? 'ok' : 'TIMEOUT'} #{(Time.now - @started).round(1)}s")
          @steps.shift
          @started = nil
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        R[:problems] << "#{name}: #{e.class}: #{e.message} #{Array(e.backtrace).first(3).join(' ; ')}"
        mb_log("step #{name} error #{e.message}")
        @steps.shift
        @started = nil
      ensure
        @busy = false
      end
    end
  end

  def self.box_script(name, origin, size)
    <<~RUBY
      module MBScript
        def self.run(model, out_dir)
          tag = model.layers['MB_Proposal'] || model.layers.add('MB_Proposal')
          g = model.entities.add_group
          g.name = 'MB Proposal - #{name}'
          g.layer = tag
          o = ModelBuilder::Units.to_point(#{origin.inspect})
          s = ModelBuilder::Units.to_inches(#{size})
          f = g.entities.add_face(o, o.offset(X_AXIS, s), o.offset(X_AXIS, s).offset(Y_AXIS, s), o.offset(Y_AXIS, s))
          f.reverse! if f.normal.z < 0
          f.pushpull(s)
          model.active_view.write_image(filename: File.join(out_dir, 'view.png'), width: 400, height: 300)
          "group \#{g.persistent_id}"
        end
      end
    RUBY
  end

  def self.find_group(model, name)
    model.entities.grep(Sketchup::Group).find { |g| g.name == "MB Proposal - #{name}" }
  end

  def self.run
    model = Sketchup.active_model
    ModelBuilder::Dev.build_calibration_scene(model)
    model.active_view.zoom_extents
    down = Geom::Vector3d.new(0, 0, -1)
    ray = ->(x, y) { [U.to_point([x, y, 5]), down] }

    # --- marks: delete one, ids stay stable
    ModelBuilder::PinStore.clear
    ModelBuilder::MarkupStore.clear_strokes
    a = ModelBuilder::PinStore.add(model, ModelBuilder::Capture.from_ray(model, ray.(10.5, 10.5)))
    b = ModelBuilder::PinStore.add(model, ModelBuilder::Capture.from_ray(model, ray.(17, 10.5)))
    pts = [[10.2, 10.2], [10.8, 10.2], [10.8, 10.8]].map { |x, y| ModelBuilder::Capture.from_ray(model, ray.(x, y))[:point] }
    s1 = ModelBuilder::MarkupStore.add_stroke(model, 'polygon', pts, %w[face face face], [nil, nil, nil], 'one')
    s2 = ModelBuilder::MarkupStore.add_stroke(model, 'line', pts.first(2), %w[face face], [nil, nil], 'two')
    ModelBuilder.delete_mark(a.id)
    ModelBuilder.delete_mark(s1.id)
    c = ModelBuilder::PinStore.add(model, ModelBuilder::Capture.from_ray(model, ray.(13.75, 10.25)))
    s3 = ModelBuilder::MarkupStore.add_stroke(model, 'line', pts.last(2), %w[face face], [nil, nil])
    check(ModelBuilder::PinStore.pins.map(&:id) == %w[p2 p3], "pin ids #{ModelBuilder::PinStore.pins.map(&:id)}")
    check(ModelBuilder::MarkupStore.strokes.map(&:id) == %w[s2 s3], "stroke ids #{ModelBuilder::MarkupStore.strokes.map(&:id)}")
    check(b.id == 'p2' && c.id == 'p3' && s2.id == 's2' && s3.id == 's3', 'ids reused after delete')

    # MarkPick on screen coords of p2 and s2
    view = model.active_view
    sp = view.screen_coords(b.point)
    hit = ModelBuilder::MarkPick.at(view, sp.x + 3, sp.y + 2)
    check(hit && hit[1].id == 'p2', "MarkPick pin #{hit && hit[1].id}")
    m1 = view.screen_coords(s2.points[0])
    m2 = view.screen_coords(s2.points[1])
    hit = ModelBuilder::MarkPick.at(view, (m1.x + m2.x) / 2, (m1.y + m2.y) / 2 + 3)
    check(hit && %w[s2 s3].include?(hit[1].id), "MarkPick stroke #{hit && hit[1].id}")

    # references incl. a DWG-like file and an in-model ref
    ModelBuilder::MarkupStore.clear_references
    dwg = File.join(File.dirname($mb_status), 'fake_site.dwg')
    File.binwrite(dwg, 'AC1032 fake')
    ModelBuilder::MarkupStore.add_reference(model, dwg, 'cad', 'site plan (test)')
    cube = model.entities.grep(Sketchup::Group).find { |g| g.name == 'Cube_A' }
    ModelBuilder::MarkupStore.add_reference(model, nil, 'cad_in_model', 'cube as reference', model_ref: ModelBuilder::Refs.ref(cube))

    # panel state + agents
    st = ModelBuilder::Panel.state
    JSON.generate(st)
    R[:agents] = st[:agents].map { |x| [x[:id], x[:available], x[:detail]] }
    check(st[:marks].map { |x| x[:id] } == %w[p2 p3 s2 s3] && st[:refs].size == 2, "panel state marks #{st[:marks].map { |x| x[:id] }}")
    check(st[:agents].any? { |x| x[:id] == 'claude' && x[:available] }, 'claude not detected')

    steps = []
    # --- Kit helpers (the DeepSeek failure: local vs world coordinates)
    b2 = model.entities.grep(Sketchup::Group).find { |g| g.name == 'Outer' }&.entities&.grep(Sketchup::ComponentInstance)&.first
    wb = b2 && ModelBuilder::Kit.world_bounds(b2)
    check(wb && (wb[:min][0] - 11).abs < 1e-6 && (wb[:max][0] - 12).abs < 1e-6 && (wb[:min][1] - 13).abs < 1e-6, "Kit.world_bounds B2 #{wb}")
    near = ModelBuilder::Kit.around([10.5, 10.5, 1.0], 2.0)
    check(near.first && near.first[:name] == 'Cube_A' && near.first[:contains_point], "Kit.around #{near.first}")
    lv = ModelBuilder::Kit.level_at(10.5, 10.5, 1.0)
    check(lv[:floor] && (lv[:floor] - 1.0).abs < 1e-6 && lv[:ceiling].nil?, "Kit.level_at #{lv}")
    pk0 = JSON.parse(JSON.generate(ModelBuilder::Packet.pin_json(b, view)))
    check(pk0['surroundings'] && pk0['surroundings']['nearby'].any?, 'pin surroundings missing')

    # --- live link with the manual agent: plan (read-only) -> approve -> build -> reject
    task = nil
    mb = ModelBuilder::Tasks.mb_exec_path
    run_py = ->(t, file, out) { Process.spawn('python', mb, '--task', t.dir, file, out: File.join(t.dir, out)) }
    stage = :start
    steps << ['manual_flow', 150, lambda do
      next true if ENV['MB_TEST_SKIP_LIVE'].to_s != ''

      case stage
      when :start
        ModelBuilder::MarkupStore.set_task(model, 'TEST live link: add a box', 'massing')
        task = ModelBuilder::Tasks.send_task(model, 'manual')
        R[:manual_task] = task.dir
        pk = JSON.parse(File.read(task.packet_path, encoding: 'UTF-8'))
        check(pk['references'].any? { |r| r['kind'] == 'cad' && r['file'].end_with?('.dwg') }, 'dwg ref not exported')
        check(pk['references'].any? { |r| r['kind'] == 'cad_in_model' && r['model_ref'] }, 'in-model ref not exported')
        check(task.status == 'planning', "status after send #{task.status}")
        File.write(File.join(task.dir, 'probe.rb'), box_script('planning probe', [0, 0, 30], 1.0))
        @pids = [run_py.(task, File.join(task.dir, 'probe.rb'), 'py_plan.txt')]
        stage = :planning
        false
      when :planning
        out = Dir.glob(File.join(task.outbox, '*.json'))
        next false if out.empty?

        r = JSON.parse(File.read(out.first, encoding: 'UTF-8'))
        check(r['ok'] && r['mode'] == 'read_only' && r['created'].zero?, "planning script #{r}")
        check(find_group(model, 'planning probe').nil?, 'planning script changed the model')
        File.write(File.join(task.dir, 'plan.md'), "Plan: add a 1 m box at (0,0,10).\n")
        stage = :plan_written
        false
      when :plan_written
        ModelBuilder::Tasks.poll
        next false unless task.status == 'plan_ready'

        ModelBuilder::Tasks.approve(task, 'ok')
        check(task.status == 'building' && File.file?(task.build_prompt_path), "approve -> #{task.status}")
        File.write(File.join(task.dir, 'box_test.rb'), box_script('live link test', [0, 0, 10], 1.0))
        File.write(File.join(task.dir, 'bad_test.rb'), "module MBScript\n  def self.run(model, out_dir)\n    model.entities.add_group\n    raise 'boom'\n  end\nend\n")
        @pids = [run_py.(task, File.join(task.dir, 'box_test.rb'), 'py1.txt'), run_py.(task, File.join(task.dir, 'bad_test.rb'), 'py2.txt')]
        stage = :building
        false
      when :building
        outs = Dir.glob(File.join(task.outbox, '*.json'))
        next false if outs.size < 3

        @pids.each { |pid| Process.wait(pid) rescue nil }
        res = outs.sort.map { |f| JSON.parse(File.read(f, encoding: 'UTF-8')) }.reject { |r| r['mode'] == 'read_only' }
        good = res.find { |r| r['ok'] }
        badr = res.find { |r| !r['ok'] }
        check(good && good['mode'] == 'build' && good['created'] == 1 && good['files'].any? { |f| f.end_with?('view.png') }, "build good #{good}")
        check(badr && badr['error'].include?('boom'), "build bad #{badr}")
        check(find_group(model, 'live link test'), 'built box missing')
        check(model.entities.grep(Sketchup::Group).none? { |g| g.name.empty? && g.entities.length.zero? }, 'failed script not rolled back')
        File.write(File.join(task.dir, 'reply.md'), "Built a test box.\n")
        stage = :reply
        false
      when :reply
        ModelBuilder::Tasks.poll
        next false unless task.status == 'done'

        ModelBuilder::Tasks.reject(task)
        check(find_group(model, 'live link test').nil?, 'reject did not remove the box')
        ev = ModelBuilder::Tasks.events(task).map { |e| e['role'] }
        R[:manual_events] = ev
        check(ev.include?('plan') && ev.include?('reply'), "events #{ev}")
        # after the task: scripts are refused
        r = ModelBuilder::LiveLink.execute(task, 'module MBScript; def self.run(m, o); 1; end; end', 'late')
        check(!r[:ok], 'script accepted after the task ended')
        true
      end
    end]

    agent_flow = lambda do |label, agent, text, finder, timeout|
      fl = { t: nil, stage: :start } # own state per flow (outer variables would be shared)
      steps << [label, timeout, lambda do
        case fl[:stage]
        when :start
          ModelBuilder::MarkupStore.set_task(model, text, 'massing')
          fl[:t] = ModelBuilder::Tasks.send_task(model, agent)
          R[label.to_sym] = { dir: fl[:t].dir }
          fl[:stage] = :plan
          false
        when :plan
          next false if fl[:t].status == 'planning'

          R[label.to_sym][:plan_status] = fl[:t].status
          R[label.to_sym][:plan_tokens] = fl[:t].tokens
          R[label.to_sym][:plan] = File.file?(fl[:t].plan_path) ? File.read(fl[:t].plan_path, encoding: 'UTF-8')[0, 600] : nil
          R[label.to_sym][:planning_created] = fl[:t].created.size
          check(fl[:t].status == 'plan_ready', "#{label}: plan status #{fl[:t].status}")
          check(model.entities.grep(Sketchup::Group).none?(&finder), "#{label}: built during planning")
          next true unless fl[:t].status == 'plan_ready'

          ModelBuilder::Tasks.approve(fl[:t], nil)
          fl[:stage] = :build
          false
        when :build
          next false if fl[:t].running?

          g = model.entities.grep(Sketchup::Group).find(&finder)
          R[label.to_sym].merge!(status: fl[:t].status, tokens: fl[:t].tokens, cost: fl[:t].cost_usd, created: fl[:t].created.size,
                                 scripts: fl[:t].scripts, bounds: g && U.bbox(g.bounds),
                                 report: File.file?(fl[:t].reply_path) ? File.read(fl[:t].reply_path, encoding: 'UTF-8')[0, 400] : nil)
          check(fl[:t].status == 'done', "#{label}: status #{fl[:t].status}")
          check(g, "#{label}: cube missing")
          true
        end
      end]
    end

    if (api = ENV['MB_TEST_API'].to_s) != ''
      agent_flow.('api', "api:#{api}",
                  'TEST: create a 1 m cube with its lower corner at (0, 0, 20) m. Keep the plan to 3 lines.',
                  ->(x) { x.name =~ /MB Proposal/i && x.bounds.min.z > U.to_inches(19) && x.bounds.min.z < U.to_inches(21) }, 400)
    end
    if ENV['MB_TEST_CLAUDE'].to_s != ''
      agent_flow.('claude', 'claude',
                  'TEST: create a 2 m cube with its lower corner at (30, 0, 0) m. Skip renders. Keep the plan and the report to 3 lines.',
                  ->(x) { x.name =~ /MB Proposal/i && (x.bounds.min.x - U.to_inches(30)).abs < 1 }, 700)
    end
    sequence(steps)
  end
end

UI.start_timer(3, false) do
  begin
    MBAgentTest.run
  rescue Exception => e # rubocop:disable Lint/RescueException
    mb_log("error #{e.class}: #{e.message}\n#{Array(e.backtrace).first(10).join("\n")}")
    MBAgentTest.quit
  end
end
