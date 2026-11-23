module ModelBuilder
  # Entity <-> protocol reference ("su:<persistent_id>") and path descriptions.
  #
  # Note: entities inside a component definition share one persistent_id
  # across all instances of that definition. Only the full path (instances
  # from the model root down to the entity) identifies one occurrence.
  module Refs
    def self.ref(entity)
      "su:#{entity.persistent_id}"
    end

    def self.instance?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def self.kind(entity)
      case entity
      when Sketchup::Face then 'face'
      when Sketchup::Edge then 'edge'
      when Sketchup::Group then 'group'
      when Sketchup::ComponentInstance then 'component'
      else 'other'
      end
    end

    # {ref, kind, name?, definition?, layer?, material?} for one entity.
    def self.basic(entity)
      h = { ref: ref(entity), kind: kind(entity) }
      if instance?(entity)
        h[:name] = entity.name unless entity.name.to_s.empty?
        # Group definition names ("Group#3") are internal noise; skip them.
        h[:definition] = entity.definition.name if entity.is_a?(Sketchup::ComponentInstance)
      end
      layer = entity.respond_to?(:layer) ? entity.layer : nil
      # The default tag ("Layer0" / "Untagged") carries no meaning.
      h[:layer] = layer.name if layer && layer != entity.model.layers[0]
      mat = entity.respond_to?(:material) ? entity.material : nil
      h[:material] = mat.display_name if mat
      h
    end

    def self.path_refs(path)
      path.map { |e| ref(e) }
    end

    def self.path_detail(path)
      path.map { |e| basic(e) }
    end

    # Human-readable breadcrumb for a path_detail array, e.g.
    # "group[tag 幕墙] > component:Curtain Wall_Half > face(Glass)".
    def self.breadcrumb(detail)
      detail.map do |e|
        label = e[:kind].dup
        label << ":#{e[:name]}" if e[:name]
        label << ":#{e[:definition]}" if e[:definition] && !e[:name]
        extras = []
        extras << "tag #{e[:layer]}" if e[:layer]
        extras << "mat #{e[:material]}" if e[:material]
        label << "[#{extras.join(', ')}]" unless extras.empty?
        label
      end.join(' > ')
    end
  end
end
