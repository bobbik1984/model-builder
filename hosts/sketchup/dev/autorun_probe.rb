# Unattended probe of a real model (dev only, not packaged).
#
#   $env:MB_PROBE_MODEL = "C:\path\to\COPY_of_model.skp"     # opens it; never saves
#   & "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_probe.rb"
#
# Uses the model's saved camera. Runs ModelBuilder::Dev.probe_view, writes
# %LOCALAPPDATA%\ModelBuilder\selftest\probe_status.txt (+ probe_result.json),
# exports a packet, and quits without saving. Point it at a COPY of the model.
require 'fileutils'

mb_dir = File.join(ENV['LOCALAPPDATA'] || Dir.home, 'ModelBuilder', 'selftest')
FileUtils.mkdir_p(mb_dir)
mb_status = File.join(mb_dir, 'probe_status.txt')
File.write(mb_status, "started #{Time.now}\n")

mb_finish = lambda do
  if ENV['MB_AUTORUN_KEEP_OPEN'].to_s.empty?
    begin
      Sketchup.active_model.close(true)
    rescue StandardError
      nil
    end
    Sketchup.quit
  end
end

begin
  require File.expand_path('../src/model_builder', __dir__) unless defined?(ModelBuilder::Dev)
  UI.start_timer(2, false) do
    begin
      target = ENV['MB_PROBE_MODEL'].to_s
      unless target.empty?
        raise "MB_PROBE_MODEL not found: #{target}" unless File.exist?(target)

        Sketchup.active_model.close(true) rescue nil
        Sketchup.open_file(target)
        File.write(mb_status, "opened #{Sketchup.active_model.path}\n", mode: 'a')
      end
      UI.start_timer(4, false) do
        begin
          r = ModelBuilder::Dev.probe_view(Sketchup.active_model)
          File.write(mb_status, "done #{r[:passed]}/#{r[:checks]} hits=#{r[:hits]} #{Time.now}\n", mode: 'a')
        rescue Exception => e # rubocop:disable Lint/RescueException
          File.write(mb_status, "error #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}\n", mode: 'a')
        ensure
          mb_finish.call
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      File.write(mb_status, "error #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}\n", mode: 'a')
      mb_finish.call
    end
  end
rescue Exception => e # rubocop:disable Lint/RescueException
  File.write(mb_status, "load error #{e.class}: #{e.message}\n", mode: 'a')
end
