# Annotator plugin for annotating documents handled by PDF.js
class Annotator.Plugin.PDF extends Annotator.Plugin

  pluginInit: ->

    # This plugin is intended to be used with the Enhanced Anchoring architecture.
    unless @annotator.plugins.EnhancedAnchoring
      throw new Error "The PDF Annotator plugin requires the EnhancedAnchoring plugin."

    # We need dom-text-mapper
    unless @annotator.plugins.DomTextMapper
      throw "The PDF Annotator plugin requires the DomTextMapper plugin."

    @annotator.registerDocumentAccessStrategy
      # Strategy to handle PDF documents rendered by PDF.js
      name: "PDF.js"
      priority: 10
      applicable: PDFTextMapper.applicable
      get: -> new PDFTextMapper()
