# Unattended runner for an arbitrary Ruby script against a model COPY (dev only).
# This is the "agent executes Ruby in SketchUp" path that the bridge will need
# (see docs/studies/atrium-roof-build.md).
#
#   $env:MB_MODEL   = "C:\path\to\COPY.skp"   # optional; opened (never saved in place)
#   $env:MB_SCRIPT  = "C:\path\to\script.rb"  # must define MBScript.run(model, out_dir) -> String
#   $env:MB_OUT     = "C:\path\to\out_dir"    # created; status.txt is written here
#   $env:MB_SAVE_AS = "C:\path\to\result.skp" # optional; model saved there after the script
#   & "C:\Program Files\SketchUp\SketchUp 2024\SketchUp.exe" -RubyStartup "<repo>\hosts\sketchup\dev\autorun_script.rb"
require 'fileutils'

mb_out = ENV['MB_OUT'].to_s.empty? ? File.join(ENV['LOCALAPPDATA'] || Dir.home, 'ModelBuilder', 'script') : ENV['MB_OUT']
FileUtils.mkdir_p(mb_out)
mb_status = File.join(mb_out, 'status.txt')
File.write(mb_status, "started #{Time.now}\n")
mb_log = ->(s) { File.write(mb_status, "#{s}\n", mode: 'a') }

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
      target = ENV['MB_MODEL'].to_s
      unless target.empty?
        raise "MB_MODEL not found: #{target}" unless File.exist?(target)

        Sketchup.active_model.close(true) rescue nil
        Sketchup.open_file(target)
        mb_log.("opened #{Sketchup.active_model.path}")
      end
      UI.start_timer(4, false) do
        begin
          t0 = Time.now
          load ENV['MB_SCRIPT']
          result = MBScript.run(Sketchup.active_model, mb_out)
          mb_log.("result #{result}")
          save_as = ENV['MB_SAVE_AS'].to_s
          unless save_as.empty?
            ok = Sketchup.active_model.save_copy(save_as)
            mb_log.("saved copy #{save_as} #{ok}")
          end
          mb_log.("done #{(Time.now - t0).round(1)}s #{Time.now}")
        rescue Exception => e # rubocop:disable Lint/RescueException
          mb_log.("error #{e.class}: #{e.message}\n#{Array(e.backtrace).first(15).join("\n")}")
        ensure
          mb_finish.call
        end
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      mb_log.("error #{e.class}: #{e.message}\n#{Array(e.backtrace).first(15).join("\n")}")
      mb_finish.call
    end
  end
rescue Exception => e # rubocop:disable Lint/RescueException
  mb_log.("load error #{e.class}: #{e.message}")
end
