# Annotator plugin providing dom-text-mapper
class Annotator.Plugin.DomTextMapper extends Annotator.Plugin

  pluginInit: ->

    @Annotator = Annotator

    @annotator.documentAccessStrategies.unshift
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
          t0 = mapper.timestamp()
          @annotator._reanchorAllAnnotations("corpus change").then ->
            t1 = mapper.timestamp()
#            console.log "corpus change -> refreshed text annotations.",
#              "Time used: ", t1-t0, "ms"
        mapper

