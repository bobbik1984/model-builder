module ModelBuilder
  # In-memory list of pins for the active model. Pins are numbered p1, p2, ...
  # in click order. Numbers are never reused within a model session, so
  # deleting p2 does not rename p3 (notes and messages may refer to "p3").
  # Not saved in the .skp yet (planned for M2).
  module PinStore
    Pin = Struct.new(:id, :point, :normal, :data) unless defined?(Pin)

    @pins ||= []
    @model ||= nil
    @seq ||= 0

    def self.pins(model = Sketchup.active_model)
      sync(model)
      @pins
    end

    # capture: hash from Capture (:point, :normal, :data). Returns the Pin.
    def self.add(model, capture)
      sync(model)
      @seq += 1
      pin = Pin.new("p#{@seq}", capture[:point], capture[:normal], capture[:data])
      @pins << pin
      pin
    end

    def self.find(id, model = Sketchup.active_model)
      pins(model).find { |p| p.id == id }
    end

    def self.remove(id, model = Sketchup.active_model)
      pin = find(id, model)
      @pins.delete(pin) if pin
      pin
    end

    def self.remove_last(model = Sketchup.active_model)
      sync(model)
      @pins.pop
    end

    def self.clear
      @pins = []
      @seq = 0
    end

    # Pins belong to one model; drop them when the active model changes.
    def self.sync(model)
      return if @model.equal?(model)

      unless @model.nil?
        @pins = []
        @seq = 0
      end
      @model = model
    end
  end
end
