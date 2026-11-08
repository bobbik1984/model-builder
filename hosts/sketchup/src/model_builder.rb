# Model Builder: SketchUp extension registration.
#
# This is the file SketchUp loads from the Plugins folder (in an .rbz) or that
# the dev loader requires from the git checkout. It only registers the
# extension; the real code starts in model_builder/main.rb.
require 'sketchup.rb'
require 'extensions.rb'

module ModelBuilder
  EXTENSION_ROOT = File.join(__dir__, 'model_builder') unless defined?(EXTENSION_ROOT)

  require File.join(EXTENSION_ROOT, 'version')

  unless file_loaded?(__FILE__)
    ext = SketchupExtension.new('Model Builder', File.join(EXTENSION_ROOT, 'main'))
    ext.description = 'Point at geometry with numbered pins and export a structured ' \
                      'context packet (JSON + screenshot) for an AI agent.'
    ext.version = VERSION
    ext.creator = 'Model Builder project'
    ext.copyright = '2026'
    Sketchup.register_extension(ext, true)
    file_loaded(__FILE__)
  end
end
