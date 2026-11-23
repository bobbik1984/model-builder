module ModelBuilder
  # Per-model, in-memory markup besides pins: outlines/strokes, attached
  # reference images, and the task message. Cleared when the active model
  # changes. Not saved in the .skp yet (M2).
  module MarkupStore
    # points: Array<Geom::Point3d> (world, inches); snaps: per point;
    # paths: per point, the entity path refs (Array<String>) or nil.
    Stroke = Struct.new(:id, :kind, :points, :snaps, :hits, :note) unless defined?(Stroke)
    # source: absolute path of the original file (image, DWG/DXF, PDF), or nil
    # for an in-model reference; model_ref: "su:<pid>" of an in-model CAD import.
    Reference = Struct.new(:id, :kind, :source, :note, :model_ref) unless defined?(Reference)

    REFERENCE_KINDS = %w[render sketch photo cad section pdf cad_in_model].freeze
    LODS = %w[massing schematic detail].freeze

    @state ||= nil
    @model ||= nil

    def self.state(model = Sketchup.active_model)
      unless @model.equal?(model) && @state
        @model = model
        @state = { strokes: [], references: [], message: '', lod: 'detail', ref_seq: 0, stroke_seq: 0 }
      end
      @state
    end

    def self.strokes(model = Sketchup.active_model)
      state(model)[:strokes]
    end

    def self.references(model = Sketchup.active_model)
      state(model)[:references]
    end

    # hits: per point, nil or {path: [refs], detail: path_detail}
    def self.add_stroke(model, kind, points, snaps, hits, note = nil)
      st = state(model)
      st[:stroke_seq] += 1 # numbers are not reused after a delete
      s = Stroke.new("s#{st[:stroke_seq]}", kind, points, snaps, hits, note)
      st[:strokes] << s
      s
    end

    def self.find_stroke(id, model = Sketchup.active_model)
      strokes(model).find { |s| s.id == id }
    end

    def self.remove_stroke(id, model = Sketchup.active_model)
      s = find_stroke(id, model)
      strokes(model).delete(s) if s
      s
    end

    def self.remove_reference(id, model = Sketchup.active_model)
      r = references(model).find { |x| x.id == id }
      references(model).delete(r) if r
      r
    end

    def self.remove_last_stroke(model = Sketchup.active_model)
      strokes(model).pop
    end

    def self.add_reference(model, source, kind, note = nil, model_ref: nil)
      st = state(model)
      st[:ref_seq] += 1
      r = Reference.new("r#{st[:ref_seq]}", kind, source, note, model_ref)
      st[:references] << r
      r
    end

    def self.clear_strokes(model = Sketchup.active_model)
      st = state(model)
      st[:strokes] = []
      st[:stroke_seq] = 0
    end

    def self.clear_references(model = Sketchup.active_model)
      st = state(model)
      st[:references] = []
      st[:ref_seq] = 0
    end

    def self.message(model = Sketchup.active_model)
      state(model)[:message]
    end

    def self.lod(model = Sketchup.active_model)
      state(model)[:lod]
    end

    def self.set_task(model, message, lod)
      st = state(model)
      st[:message] = message.to_s
      st[:lod] = LODS.include?(lod) ? lod : 'detail'
    end
  end
end
