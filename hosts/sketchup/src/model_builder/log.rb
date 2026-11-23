require 'fileutils'

module ModelBuilder
  # File logger. Errors inside tool callbacks and timers are easy to lose in
  # SketchUp, so everything also goes to
  # %LOCALAPPDATA%\ModelBuilder\logs\model_builder.log
  module Log
    def self.base_dir
      File.join(ENV['LOCALAPPDATA'] || Dir.home, 'ModelBuilder')
    end

    def self.dir
      File.join(base_dir, 'logs')
    end

    def self.path
      File.join(dir, 'model_builder.log')
    end

    def self.info(msg)
      write('INFO', msg)
    end

    def self.warn(msg)
      write('WARN', msg)
    end

    def self.error(msg, exception = nil)
      text = msg.to_s
      if exception
        text += " -- #{exception.class}: #{exception.message}\n  " +
                Array(exception.backtrace).first(15).join("\n  ")
      end
      write('ERROR', text)
      puts "[ModelBuilder] ERROR #{text}"
    end

    def self.write(level, msg)
      FileUtils.mkdir_p(dir)
      File.open(path, 'a:UTF-8') do |f|
        f.puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} [#{level}] #{msg}"
      end
    rescue StandardError
      nil # logging must never break the host
    end
  end

  # Runs the block, logging (and optionally showing) any error instead of
  # letting it escape into SketchUp.
  def self.guard(context, notify: false)
    yield
  rescue StandardError => e
    Log.error("#{context} failed", e)
    UI.messagebox("Model Builder: #{context} failed.\n\n#{e.message}\n\nSee #{Log.path}") if notify
    nil
  end
end
