class Annotator.Plugin.TextPosition extends Annotator.Plugin
  pluginInit: ->

    @Annotator = Annotator
    @$ = Annotator.$

    # Do we have the basic text anchors plugin loaded?
    unless @annotator.plugins.DomTextMapper
      throw new Error "The TextPosition Annotator plugin requires the DomTextMapper plugin."

    # Register the creator for text quote selectors
    @annotator.registerSelectorCreator
      name: "TextPosition"
      describe: @_createTextPositionSelectorFromRange

    # Register the position-based anchoring strategy
    @annotator.registerAnchoringStrategy
      # Position-based strategy. (The quote is verified.)
      # This can handle document structure changes,
      # but not the content changes.
      name: "position"
      priority: 50
      create: @_createAnchorFromTextPositionSelector
      verify: @_verifyPositionAnchor

  # Create a TextPositionSelector around a range
  _createTextPositionSelectorFromRange: (selection) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    unless selection.type is "text range"
      dfd.reject "I can only describe text ranges"
      return dfd.promise()

    # Get a d-t-m ready-state token out from selection data
    state = selection.data.dtmState

    startOffset = (state.getStartInfoForNode selection.range.start).start
    endOffset = (state.getEndInfoForNode selection.range.end).end

    # Resolve the pormise with the selector
    dfd.resolve [
      type: "TextPositionSelector"
      start: startOffset
      end: endOffset
    ]

    # Return the promise
    dfd.promise()


  # Create an anchor using the saved TextPositionSelector.
  # The quote is verified.
  _createAnchorFromTextPositionSelector: (target) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    # This strategy depends on dom-text-mapper
    unless @annotator.plugins.DomTextMapper
      dfd.reject "DTM is not present"
      return dfd.promise()

    # We need the TextPositionSelector
    selector = @annotator.findSelector target.selector, "TextPositionSelector"
    unless selector
      dfd.reject "no TextPositionSelector found", true
      return dfd.promise()

    # Get the d-t-m in a consistent state
    @annotator.domMapper.prepare("anchoring").then (s) =>
      # When the d-t-m is ready, do this

      content = s.getCorpus()[ selector.start ... selector.end ].trim()
      currentQuote = @annotator.normalizeString content
      savedQuote = @annotator.getQuoteForTarget? target
      if savedQuote? and currentQuote isnt savedQuote
        # We have a saved quote, let's compare it to current content
        #console.log "Could not apply position selector" +
        #  " [#{selector.start}:#{selector.end}] to current document," +
        #  " because the quote has changed. " +
        #  "(Saved quote is '#{savedQuote}'." +
        #  " Current quote is '#{currentQuote}'.)"
        dfd.reject "the saved quote doesn't match"
        return dfd.promise()

      # Create a TextPositionAnchor from this data
      dfd.resolve
        type: "text position"
        start: selector.start
        end: selector.end
        startPage: s.getPageIndexForPos selector.start
        endPage: s.getPageIndexForPos selector.end
        quote: currentQuote

    dfd.promise()

  # If there was a corpus change, verify that the text
  # is still the same.
  _verifyPositionAnchor: (anchor, reason, data) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    unless reason is "corpus change"
      dfd.resolve true # We don't care until the corpus has changed
      return dfd.promise()

    # Prepare d-t-m for action
    @annotator.domMapper.prepare("verifying an anchor").then (s) =>
      # Get the current quote
      corpus = s.getCorpus()
      content = corpus[ anchor.start ... anchor.end ].trim()
      currentQuote = @annotator.normalizeString content

      # Compare it with the stored one
      dfd.resolve (currentQuote is anchor.quote)

    # Return the promise
    dfd.promise()
