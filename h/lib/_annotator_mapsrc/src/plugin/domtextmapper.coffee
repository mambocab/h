# Annotator plugin providing dom-text-mapper
class Annotator.Plugin.DomTextMapper extends Annotator.Plugin

  pluginInit: ->

    # This plugin is intended to be used with the Enhanced Anchoring architecture.
    unless @annotator.plugins.EnhancedAnchoring
      throw new Error "The DomTextMapper Annotator plugin requires the EnhancedAnchoring plugin."

    @Annotator = Annotator

    @annotator.registerDocumentAccessStrategy

      # Document access strategy for simple HTML documents,
      # with enhanced text extraction and mapping features.
      name: "DOM-Text-Mapper"
      applicable: -> true
      get: =>
        defaultOptions =
          rootNode: @annotator.wrapper[0]
          getIgnoredParts: -> $.makeArray $ [
            "div.annotator-notice",
            "div.annotator-outer",
            "div.annotator-editor",
            "div.annotator-viewer",
            "div.annotator-adder"
          ].join ", "
          cacheIgnoredParts: true
        options = $.extend {}, defaultOptions, @options.options
        mapper = new window.DomTextMapper options

        # Wrap the async "ready()" function in a promise
        mapper.prepare = (reason) =>
          # Prepare the deferred object
          dfd = @Annotator.$.Deferred()

          # Get the d-t-m in a consistent state
          @annotator.domMapper.ready reason, (s) => dfd.resolve s

          # Return a promise
          dfd.promise()

        options.rootNode.addEventListener "corpusChange", =>
          t0 = mapper._timestamp()
          @annotator._reanchorAllAnnotations("corpus change").then ->
            t1 = mapper._timestamp()
#            console.log "corpus change -> refreshed text annotations.",
#              "Time used: ", t1-t0, "ms"
        mapper

