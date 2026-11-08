require 'json'

module ModelBuilder
  # Which agents can take a task (docs/decisions/0003-agent-connection.md):
  #   - agent programs found on this machine (Claude Code, Codex, Antigravity IDE, custom)
  #   - direct API providers, with keys in USER environment variables (shared
  #     with other tools on the machine; the plugin never stores the key itself)
  module Agents
    SETTINGS = 'ModelBuilder' # Sketchup.read_default section

    CLI = {
      'claude' => { label: 'Claude Code', kind: 'cli', names: %w[claude.exe claude.cmd claude],
                    extra_paths: ['~/.local/bin/claude.exe', '%APPDATA%/npm/claude.cmd'],
                    note: 'runs headless, streams into this panel' },
      'codex' => { label: 'Codex CLI', kind: 'cli', names: %w[codex.cmd codex.exe codex],
                   extra_paths: ['%APPDATA%/npm/codex.cmd'], note: 'codex exec (flags unverified)' },
      'gemini' => { label: 'Gemini CLI', kind: 'cli', names: %w[gemini.cmd gemini.exe gemini],
                    extra_paths: ['%APPDATA%/npm/gemini.cmd'], note: 'gemini -p (flags unverified)' },
      'antigravity' => { label: 'Antigravity IDE', kind: 'ide', names: %w[antigravity-ide.cmd agy.cmd agy.exe agy],
                         extra_paths: ['%LOCALAPPDATA%/Programs/Antigravity IDE/bin/antigravity-ide.cmd'],
                         note: 'opens the task in the IDE agent chat; results come back through the live link' }
    }.freeze

    PROVIDERS = {
      'deepseek' => { label: 'DeepSeek API', style: 'openai', env: 'DEEPSEEK_API_KEY', base_env: 'DEEPSEEK_BASE_URL',
                      base: 'https://api.deepseek.com', model: 'deepseek-chat', vision: false },
      'anthropic' => { label: 'Anthropic API', style: 'anthropic', env: 'ANTHROPIC_API_KEY', base_env: 'ANTHROPIC_BASE_URL',
                       base: 'https://api.anthropic.com', model: 'claude-sonnet-5-5', vision: true },
      'openai' => { label: 'OpenAI-compatible API', style: 'openai', env: 'OPENAI_API_KEY', base_env: 'OPENAI_BASE_URL',
                    base: 'https://api.openai.com/v1', model: '', vision: true },
      'gemini_api' => { label: 'Gemini API (OpenAI-compatible)', style: 'openai', env: 'GEMINI_API_KEY', base_env: nil,
                        base: 'https://generativelanguage.googleapis.com/v1beta/openai', model: '', vision: true }
    }.freeze

    # Built-in providers plus the ones added with "+" in the dialog (stored as
    # JSON in the SketchUp settings; the key itself lives in an env variable).
    def self.providers
      custom = begin
        JSON.parse(setting('custom_apis', '[]'))
      rescue JSON::ParserError
        []
      end
      extra = custom.to_h do |c|
        [c['id'], { label: c['label'], style: c['style'] || 'openai', env: c['env'], base_env: nil, base: c['base'],
                    model: c['model'], vision: c['vision'] == true, custom: true }]
      end
      PROVIDERS.merge(extra)
    end

    def self.add_provider(label:, style:, base:, model:, env:, vision:, key: nil)
      id = label.to_s.downcase.gsub(/[^a-z0-9]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')
      id = "custom_#{Time.now.to_i}" if id.empty? || PROVIDERS.key?(id)
      env = env.to_s.strip.empty? ? "#{id.upcase}_API_KEY" : env.strip.upcase
      list = JSON.parse(setting('custom_apis', '[]')) rescue []
      list.reject! { |c| c['id'] == id }
      list << { 'id' => id, 'label' => label, 'style' => style, 'base' => base, 'model' => model, 'env' => env, 'vision' => vision }
      set_setting('custom_apis', JSON.generate(list))
      save_env(env, key) unless key.to_s.strip.empty?
      id
    end

    # ---- settings (non-secret) ---------------------------------------------

    def self.setting(key, default = nil)
      v = Sketchup.read_default(SETTINGS, key)
      v.nil? || v == '' ? default : v
    end

    def self.set_setting(key, value)
      Sketchup.write_default(SETTINGS, key, value.to_s)
    end

    # ---- executables -------------------------------------------------------

    def self.which(names, extra_paths = [])
      dirs = ENV['PATH'].to_s.split(File::PATH_SEPARATOR)
      names.each do |n|
        dirs.each do |d|
          f = File.join(d, n)
          return f if File.file?(f)
        end
      end
      extra_paths.each do |p|
        f = File.expand_path(p.gsub(/%(\w+)%/) { ENV[Regexp.last_match(1)].to_s })
        return f if File.file?(f)
      end
      nil
    end

    def self.executable(id)
      custom = setting("exe_#{id}")
      return custom if custom && File.file?(custom)

      spec = CLI[id]
      spec && which(spec[:names], spec[:extra_paths])
    end

    # ---- keys --------------------------------------------------------------

    # Current value of a user env var: process ENV first, then the registry
    # (so a key saved after SketchUp started is found without a restart).
    def self.env_value(name)
      return nil if name.nil?
      return ENV[name] unless ENV[name].to_s.empty?

      require 'win32/registry'
      Win32::Registry::HKEY_CURRENT_USER.open('Environment') do |reg|
        v = reg[name]
        return v.to_s.empty? ? nil : v
      end
    rescue LoadError, StandardError
      nil
    end

    # Writes a USER environment variable (no admin needed) and sets it for
    # this process too. Uses setx, which also notifies other programs.
    def self.save_env(name, value)
      raise ArgumentError, 'empty value' if value.to_s.strip.empty?

      ENV[name] = value.strip
      ok = system('setx', name, value.strip, out: File::NULL, err: File::NULL)
      Log.info("Saved user environment variable #{name} (setx #{ok ? 'ok' : 'failed'})")
      ok
    end

    def self.mask(key)
      return nil if key.to_s.empty?

      key.length > 8 ? "#{key[0, 3]}…#{key[-4..]}" : '…'
    end

    def self.provider_config(id)
      spec = providers[id] or return nil
      key = env_value(spec[:env])
      {
        id: id, label: spec[:label], style: spec[:style], env: spec[:env], vision: spec[:vision], custom: spec[:custom] == true,
        base: setting("base_#{id}") || env_value(spec[:base_env]) || spec[:base],
        model: setting("model_#{id}") || spec[:model],
        key_found: !key.nil?, key_masked: mask(key), key_status: setting("keystatus_#{id}")
      }
    end

    def self.api_key(id)
      env_value(providers.dig(id, :env))
    end

    # ---- list for the panel -------------------------------------------------

    def self.list
      cli = CLI.map do |id, spec|
        exe = executable(id)
        { id: id, label: spec[:label], kind: spec[:kind], available: !exe.nil?, detail: exe || 'not found', note: spec[:note] }
      end
      api = providers.keys.map do |id|
        c = provider_config(id)
        { id: "api:#{id}", label: c[:label], kind: 'api', available: c[:key_found],
          detail: c[:key_found] ? "#{c[:env]} found (#{c[:key_masked]})#{c[:key_status] ? ", #{c[:key_status]}" : ''}" : "#{c[:env]} not set",
          model: c[:model], base: c[:base], env: c[:env], vision: c[:vision], status: c[:key_status] }
      end
      manual = { id: 'manual', label: 'Any agent (copy the prompt)', kind: 'manual', available: true,
                 detail: 'Send exports and opens a live-link task; paste prompt.md into any agent',
                 note: 'Works with any agent that can read files and run a command.' }
      cli + api + [manual]
    end

    def self.default_agent
      saved = setting('agent')
      avail = list.select { |a| a[:available] }
      return saved if saved && avail.any? { |a| a[:id] == saved }

      avail.first&.dig(:id)
    end

    # ---- launching agent programs ------------------------------------------

    def self.repo_root
      File.expand_path('../../../..', __dir__)
    end

    # Command line (array) for an agent program; the prompt comes from stdin
    # where the program supports it.
    def self.command(id, exe, task, prompt_file, resume)
      case id
      when 'claude'
        cmd = [exe, '-p', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'acceptEdits',
               # Windows Claude Code runs commands through its PowerShell tool; allow both shells.
               '--allowedTools', 'Bash,PowerShell,Read,Write,Edit,Glob,Grep', '--add-dir', repo_root,
               '--add-dir', task.model_dir]
        cmd += ['--resume', resume] if resume
        cmd
      when 'codex' then [exe, 'exec', '--full-auto', '-']
      when 'gemini' then [exe, '-p', 'Follow the task in the input.', '--yolo']
      when 'antigravity'
        [exe, 'chat', '-m', 'agent', '-n', '-a', prompt_file,
         "Model Builder task #{task.id}: follow the instructions in the attached #{File.basename(prompt_file)} (#{prompt_file})."]
      else
        tmpl = setting("cmd_#{id}") or raise "No command for agent #{id}"
        tmpl.gsub('{exe}', exe.to_s).gsub('{prompt_file}', prompt_file).gsub('{task_dir}', task.dir).split(' ')
      end
    end

    def self.quote(arg)
      a = arg.to_s
      a =~ /[\s"&|<>^]/ ? "\"#{a.gsub('"', '\"')}\"" : a
    end

    # Starts the program hidden (no console window), stdin from the prompt,
    # stdout/stderr to the task log, exit code to exit_code.txt.
    def self.launch(id, task, stdin:, resume: nil)
      exe = executable(id) or raise "#{CLI.dig(id, :label) || id} was not found on this machine"
      args = command(id, exe, task, stdin, resume)
      stdin = nil if id == 'antigravity'
      line = args.map { |a| quote(a) }.join(' ')
      line = "#{line} < #{quote(stdin)}" if stdin
      inner = "cd /d #{quote(task.session_dir)} && #{line} > #{quote(task.log_path)} 2>&1 & echo %ERRORLEVEL% > #{quote(task.exit_path)}"
      full = "cmd.exe /s /c \"#{inner}\""
      Log.info("Launching #{id}: #{full}")
      begin
        require 'win32ole'
        WIN32OLE.new('WScript.Shell').Run(full, 0, false) # 0 = hidden window
      rescue LoadError, StandardError => e
        Log.warn("WScript.Shell launch failed (#{e.message}); using Process.spawn")
        Process.detach(Process.spawn(full))
      end
      true
    end
  end
end
