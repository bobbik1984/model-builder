module ModelBuilder
  # Click a surface to drop a numbered pin, then optionally type a note.
  #   Left click        : place pin (snaps to endpoints/midpoints/edges like native tools)
  #   Shift+click       : place pin without the note prompt
  #   Backspace         : remove last pin
  #   Delete            : delete the pin/outline under the cursor
  #   Right click       : on a mark: edit note / delete it; elsewhere: last pin, clear, export
  #   Esc / other tool  : leave the tool (pins are kept)
  class PinTool
    VK_BACKSPACE = 8
    VK_DELETE_KEY = 46

    @active = false

    class << self
      attr_writer :active

      def active?
        @active
      end
    end

    def activate
      @ip = Sketchup::InputPoint.new
      PinTool.active = true
      update_status
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      PinTool.active = false
      view.invalidate
    end

    def resume(view)
      update_status
      view.invalidate
    end

    def onMouseMove(_flags, x, y, view)
      ModelBuilder.guard('PinTool#onMouseMove') do
        @ip.pick(view, x, y)
        @mouse = [x, y]
        hover = MarkPick.at(view, x, y)
        view.tooltip = hover ? "#{hover[1].id}: right-click or Delete key to edit/delete" : (@ip.valid? ? @ip.tooltip : '')
        view.invalidate
      end
    end

    def onLButtonDown(flags, x, y, view)
      ModelBuilder.guard('Placing a pin', notify: true) do
        @ip.pick(view, x, y)
        capture = Capture.from_screen(view, x, y, @ip)
        unless capture
          UI.beep
          update_status('No geometry under the cursor.')
          next
        end

        pin = PinStore.add(view.model, capture)
        view.invalidate
        pt = Units.point(pin.point).map { |c| format('%.3f', c) }.join(', ')
        Log.info("#{pin.id} at [#{pt}] m on #{pin.data[:entity][:ref]} (snap: #{pin.data[:snap]})")
        ModelBuilder.edit_pin_note(pin) if (flags & CONSTRAIN_MODIFIER_MASK).zero?
        update_status("#{pin.id} placed at (#{pt}) m on #{pin.data[:entity][:kind]} #{pin.data[:entity][:ref]}.")
        view.invalidate
      end
    end

    def onKeyDown(key, _repeat, _flags, view)
      if key == VK_DELETE_KEY && @mouse
        hit = MarkPick.at(view, *@mouse)
        return false unless hit

        ModelBuilder.delete_mark(hit[1].id)
        view.invalidate
        return true
      end
      return false unless key == VK_BACKSPACE

      ModelBuilder.remove_last_pin
      view.invalidate
      true
    end

    def getMenu(menu, _flags, x, y, view)
      MarkPick.add_menu_items(menu, view, x, y)
      last = PinStore.pins.last
      menu.add_item("Edit Note of #{last.id}...") { ModelBuilder.edit_pin_note(last) } if last
      menu.add_item('Remove Last Pin') { ModelBuilder.remove_last_pin }
      menu.add_item('Clear All Markup') { ModelBuilder.clear_markup }
      menu.add_separator
      menu.add_item('Export Context Packet...') { ModelBuilder.export_context }
      true
    end

    def getExtents
      MarkupDraw.extents(Sketchup.active_model)
    end

    def draw(view)
      @ip.draw(view) if @ip&.display?
      MarkupDraw.draw_all(view) unless Overlays.active?(view.model)
    rescue StandardError => e
      Log.error('PinTool#draw failed', e) # never re-raise from draw
    end

    private

    def update_status(prefix = nil)
      n = PinStore.pins.size
      text = "Model Builder: click a surface to place pin #{n + 1} (Shift = no note). " \
             'Backspace = remove last, right-click = more.'
      Sketchup.status_text = prefix ? "#{prefix}  #{text}" : text
    end
  end
end
