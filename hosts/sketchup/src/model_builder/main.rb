require 'sketchup.rb'

module ModelBuilder
  PLUGIN_DIR = __dir__ unless defined?(PLUGIN_DIR)

  # Load order matters. Keep in sync when adding files.
  def self.source_files
    %w[
      version log units refs geometry capture pin_store markup_store
      markup_draw mark_pick overlay kit checks packet brief raster exporter
      agents prompts tasks live_link api_agent ui/panel
      tools/pin_tool tools/outline_tool tools/ai_build_tool
      dev/calibration_scene dev/self_test dev/model_probe dev/markup_test
    ]
  end

  source_files.each { |f| Sketchup.require(File.join(PLUGIN_DIR, f)) }

  # ---- Commands ------------------------------------------------------------

  def self.activate_pin_tool
    guard('Activating the pin tool', notify: true) do
      Sketchup.active_model.select_tool(PinTool.new)
    end
  end

  def self.activate_outline_tool
    guard('Activating the outline tool', notify: true) do
      Sketchup.active_model.select_tool(OutlineTool.new)
    end
  end

  def self.remove_last_pin
    guard('Removing the last pin', notify: true) do
      pin = PinStore.remove_last
      Sketchup.active_model.active_view.invalidate
      Sketchup.status_text = pin ? "Model Builder: removed #{pin.id}" : 'Model Builder: no pins'
    end
  end

  # Clears pins and outlines (references and the task message are kept).
  def self.clear_markup
    guard('Clearing markup', notify: true) do
      n = PinStore.pins.size
      m = MarkupStore.strokes.size
      PinStore.clear
      MarkupStore.clear_strokes
      Sketchup.active_model.active_view.invalidate
      Sketchup.status_text = "Model Builder: cleared #{n} pin(s) and #{m} outline(s)"
    end
  end
  singleton_class.send(:alias_method, :clear_pins, :clear_markup)

  # Delete one pin ("p3") or outline ("s2"). Numbers are not reused.
  def self.delete_mark(id)
    guard("Deleting #{id}", notify: true) do
      removed = PinStore.remove(id) || MarkupStore.remove_stroke(id)
      Sketchup.active_model.active_view.invalidate
      Sketchup.status_text = removed ? "Model Builder: deleted #{id}" : "Model Builder: #{id} not found"
    end
  end

  def self.show_panel
    guard('Opening the panel', notify: true) { Panel.show }
  end

  # The main entry: mark (pin or outline) -> the request dialog opens.
  def self.activate_ai_build
    guard('Starting AI Build', notify: true) do
      Sketchup.active_model.select_tool(AiBuildTool.new)
      Panel.show
    end
  end

  def self.edit_pin_note(pin)
    input = UI.inputbox(["Note for #{pin.id} (optional):"], [pin.data[:note].to_s], 'Model Builder: Pin Note')
    pin.data[:note] = input[0].to_s.strip if input
  end

  def self.edit_stroke_note(stroke)
    input = UI.inputbox(["Note for #{stroke.id} (optional):"], [stroke.note.to_s], 'Model Builder: Outline Note')
    stroke.note = input[0].to_s.strip if input
  end

  IMAGE_FILTER = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif;*.webp||'.freeze unless defined?(IMAGE_FILTER)

  def self.attach_reference
    guard('Attaching a reference image', notify: true) do
      model = Sketchup.active_model
      path = UI.openpanel('Attach reference image (sketch, render, photo, CAD export)', @last_ref_dir, IMAGE_FILTER)
      next unless path

      @last_ref_dir = File.dirname(path)
      guess = File.basename(path).downcase =~ /sketch|detail|草图|大样|节点/ ? 'sketch' : 'render'
      input = UI.inputbox(['Kind:', 'Note (what should the agent take from it?):'], [guess, ''],
                          [MarkupStore::REFERENCE_KINDS.join('|'), ''], "Model Builder: #{File.basename(path)}")
      next unless input

      r = MarkupStore.add_reference(model, path, input[0], input[1].to_s.strip.empty? ? nil : input[1].strip)
      Sketchup.status_text = "Model Builder: attached #{r.id} (#{File.basename(path)}). " \
                             "#{MarkupStore.references.size} reference(s) will be exported."
    end
  end

  def self.clear_references
    guard('Clearing references', notify: true) do
      n = MarkupStore.references.size
      MarkupStore.clear_references
      Sketchup.status_text = "Model Builder: removed #{n} reference(s)"
    end
  end

  # The plugin warns on export when imported CAD (DWG/DXF) has not been
  # confirmed to line up with the model (see docs/studies/park-handoff.md).
  # The user selects the CAD import(s) after checking and confirms here.
  def self.mark_cad_registered
    guard('Confirming CAD placement', notify: true) do
      model = Sketchup.active_model
      cads = model.selection.grep(Sketchup::ComponentInstance).select { |i| i.definition.name =~ Checks::CAD_EXTENSIONS }
      if cads.empty?
        UI.messagebox('Select the imported DWG/DXF component(s) first (top level), after checking they line up with the model.')
        next
      end
      input = UI.inputbox(['How was it checked?'], ['lined up with model by user'], 'Model Builder: Confirm CAD Placement')
      next unless input

      model.start_operation('Model Builder: confirm CAD placement', true)
      cads.each { |c| Checks.mark_registered(c, input[0].to_s.strip) }
      model.commit_operation
      Sketchup.status_text = "Model Builder: marked #{cads.size} CAD import(s) as registered"
    end
  end

  def self.export_context
    guard('Exporting the context packet', notify: true) { Exporter.export_interactive }
  end

  def self.open_session_folder
    guard('Opening the session folder', notify: true) { Exporter.open_folder(Exporter.sessions_root) }
  end

  def self.open_log_folder
    guard('Opening the log folder', notify: true) { Exporter.open_folder(Log.dir) }
  end

  # Re-load every Ruby file from disk. Menus/toolbars are not rebuilt (they
  # call these module methods, so they pick up the new code). Markup is kept.
  def self.reload
    old_verbose = $VERBOSE
    $VERBOSE = nil # silence "method redefined" warnings
    source_files.each { |f| load(File.join(PLUGIN_DIR, "#{f}.rb")) }
    load(__FILE__)
    Log.info("Reloaded #{source_files.size + 1} files")
    puts "[ModelBuilder] reloaded #{source_files.size + 1} files from #{PLUGIN_DIR}"
    true
  ensure
    $VERBOSE = old_verbose
  end

  # ---- UI ------------------------------------------------------------------

  def self.icon(name)
    File.join(PLUGIN_DIR, 'icons', "#{name}.svg")
  end

  def self.command(title, tip, icon_name = nil, &block)
    cmd = UI::Command.new(title, &block)
    cmd.tooltip = title
    cmd.status_bar_text = tip
    if icon_name
      cmd.small_icon = icon(icon_name)
      cmd.large_icon = icon(icon_name)
    end
    cmd
  end

  unless file_loaded?(__FILE__)
    pin_cmd = command('Pin Tool', 'Click surfaces to place numbered pins with notes.', 'pin') do
      ModelBuilder.activate_pin_tool
    end
    pin_cmd.set_validation_proc { PinTool.active? ? MF_CHECKED : MF_UNCHECKED }

    outline_cmd = command('Outline Tool', 'Click points to outline an area or draw a line on the model.',
                          'outline') { ModelBuilder.activate_outline_tool }
    outline_cmd.set_validation_proc { OutlineTool.active? ? MF_CHECKED : MF_UNCHECKED }

    ref_cmd = command('Attach Reference Image...', 'Attach a sketch, render or photo to the next export.',
                      'reference') { ModelBuilder.attach_reference }
    clear_cmd = command('Clear Markup', 'Remove all pins and outlines.', 'clear') { ModelBuilder.clear_markup }
    export_cmd = command('Export Context Packet...',
                         'Write the task, markup, camera, screenshots and references to the session folder.',
                         'export') { ModelBuilder.export_context }

    ai_cmd = command('AI Build', 'Click a point (click again = pin) or outline an area, describe it, send it to an agent.',
                     'ai_build') { ModelBuilder.activate_ai_build }
    ai_cmd.set_validation_proc { AiBuildTool.active? ? MF_CHECKED : MF_UNCHECKED }
    panel_cmd = command('AI Build Request', 'Open the request dialog (description, attachments, send to, plan, result).',
                        'panel') { ModelBuilder.show_panel }

    menu = UI.menu('Extensions').add_submenu('Model Builder')
    menu.add_item(ai_cmd)
    menu.add_item(panel_cmd)
    menu.add_separator
    menu.add_item(pin_cmd)
    menu.add_item(outline_cmd)
    menu.add_item(ref_cmd)
    menu.add_item('Clear References') { ModelBuilder.clear_references }
    menu.add_item('Confirm Selected CAD Placement...') { ModelBuilder.mark_cad_registered }
    menu.add_item(clear_cmd)
    menu.add_separator
    menu.add_item(export_cmd)
    menu.add_item('Open Session Folder') { ModelBuilder.open_session_folder }
    dev = menu.add_submenu('Dev')
    dev.add_item('Build Calibration Scene') { ModelBuilder::Dev.build_calibration_scene_interactive }
    dev.add_item('Run Self-Test') { ModelBuilder::Dev.run_self_test_interactive }
    dev.add_item('Probe Current View') { ModelBuilder::Dev.probe_view_interactive }
    dev.add_item('Reload Ruby Files') { ModelBuilder.reload }
    dev.add_item('Open Log Folder') { ModelBuilder.open_log_folder }

    toolbar = UI::Toolbar.new('Model Builder')
    # AI Build is the main entry; the older single-purpose tools stay in the menu.
    [ai_cmd, panel_cmd, clear_cmd].each { |c| toolbar.add_item(c) }
    toolbar.get_last_state == TB_NEVER_SHOWN ? toolbar.show : toolbar.restore

    if defined?(Overlays::AppHook)
      Sketchup.add_observer(Overlays::AppHook.new) # also fires for the startup model
    end
    Overlays.attach(Sketchup.active_model)

    Log.info("Loaded Model Builder #{VERSION} (protocol #{PROTOCOL_VERSION}) from #{PLUGIN_DIR}, " \
             "SketchUp #{Sketchup.version}, overlays #{Overlays.supported? ? 'yes' : 'no'}")
    file_loaded(__FILE__)
  end
end
