module ModelBuilder
  # Keeps pins and outlines visible whatever tool is active (SketchUp 2023+
  # Overlays API). On older versions markup is drawn only by our own tools.
  module Overlays
    ID = 'model_builder.markup'.freeze

    if defined?(Sketchup::Overlay) && !defined?(MarkupOverlay)
      class MarkupOverlay < Sketchup::Overlay
        def initialize
          super(ID, 'Model Builder Markup', description: 'Pins and outlines placed with Model Builder')
        end

        def draw(view)
          MarkupDraw.draw_all(view)
        rescue StandardError => e
          Log.error('MarkupOverlay#draw failed', e)
        end

        def getExtents
          MarkupDraw.extents(Sketchup.active_model)
        end
      end
    end

    def self.supported?
      defined?(Sketchup::Overlay) ? true : false
    end

    def self.find(model = Sketchup.active_model)
      return nil unless supported? && model.respond_to?(:overlays)

      model.overlays.find { |o| o.overlay_id == ID }
    end

    def self.attach(model = Sketchup.active_model)
      return nil unless supported? && model

      ov = find(model)
      unless ov
        ov = MarkupOverlay.new
        model.overlays.add(ov)
      end
      ov.enabled = true
      ov
    rescue StandardError => e
      Log.error('Attaching the markup overlay failed', e)
      nil
    end

    # True when the overlay is drawing markup (so tools should not draw it too).
    def self.active?(model = Sketchup.active_model)
      ov = find(model)
      ov ? ov.enabled? : false
    end

    if defined?(Sketchup::AppObserver) && !defined?(AppHook)
      class AppHook < Sketchup::AppObserver
        def onNewModel(model)
          Overlays.attach(model)
        end

        def onOpenModel(model)
          Overlays.attach(model)
        end

        def expectsStartupModelNotifications
          true
        end
      end
    end
  end
end
