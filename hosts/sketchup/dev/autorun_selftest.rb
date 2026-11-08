# Unattended self-test inside SketchUp (dev only, not packaged).
#
#   "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_selftest.rb"
#
# Loads the extension (unless the dev loader already did), runs
# ModelBuilder::Dev.run_self_test, writes a status line to
# %LOCALAPPDATA%\ModelBuilder\selftest\autorun_status.txt and quits SketchUp
# without saving. Full report: ...\selftest\last_result.json
require 'fileutils'

mb_status_dir = File.join(ENV['LOCALAPPDATA'] || Dir.home, 'ModelBuilder', 'selftest')
FileUtils.mkdir_p(mb_status_dir)
mb_status = File.join(mb_status_dir, 'autorun_status.txt')
File.write(mb_status, "started #{Time.now}\n")

begin
  require File.expand_path('../src/model_builder', __dir__) unless defined?(ModelBuilder::Dev)
  File.write(mb_status, "loaded #{Time.now}\n", mode: 'a')
  UI.start_timer(3, false) do
    begin
      r = ModelBuilder::Dev.run_self_test(Sketchup.active_model)
      File.write(mb_status, "done #{r[:passed]}/#{r[:total]} #{Time.now}\n", mode: 'a')
      # Markup features; MB_TEST_REFS = image paths separated by ';' (optional)
      refs = ENV['MB_TEST_REFS'].to_s.split(';').map(&:strip).reject(&:empty?)
      m = ModelBuilder::Dev.run_markup_test(Sketchup.active_model, reference_paths: refs)
      File.write(mb_status, "markup #{m[:pass] ? 'PASS' : 'FAIL'} #{m[:problems].join('; ')} views=#{m[:views].join(',')}\n", mode: 'a')
    rescue Exception => e # rubocop:disable Lint/RescueException
      File.write(mb_status, "error #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}\n", mode: 'a')
    ensure
      if ENV['MB_AUTORUN_KEEP_OPEN'].to_s.empty?
        begin
          Sketchup.active_model.close(true)
        rescue StandardError
          nil
        end
        Sketchup.quit
      end
    end
  end
rescue Exception => e # rubocop:disable Lint/RescueException
  File.write(mb_status, "load error #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}\n", mode: 'a')
end
