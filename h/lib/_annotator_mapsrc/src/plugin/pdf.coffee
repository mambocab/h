# Annotator plugin for annotating documents handled by PDF.js
class Annotator.Plugin.PDF extends Annotator.Plugin

  pluginInit: ->
    # We need dom-text-mapper
    unless @annotator.plugins.DomTextMapper
      throw "The PDF Annotator plugin requires the DomTextMapper plugin."

    @annotator.documentAccessStrategies.unshift
      # Strategy to handle PDF documents rendered by PDF.js
      name: "PDF.js"
      applicable: PDFTextMapper.applicable
      get: -> new PDFTextMapper()
