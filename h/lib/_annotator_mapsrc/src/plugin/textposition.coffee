# This anchor type stores information about a piece of text,
# described using start and end character offsets
class TextPositionAnchor extends Annotator.Anchor

  @Annotator = Annotator

  constructor: (annotator, annotation, target,
      @start, @end, startPage, endPage,
      quote, diffHTML, diffCaseOnly) ->

    super annotator, annotation, target,
      startPage, endPage,
      quote, diffHTML, diffCaseOnly

    # This pair of offsets is the key information,
    # upon which this anchor is based upon.
    unless @start? then throw new Error "start is required!"
    unless @end? then throw new Error "end is required!"

    #console.log "Created TextPositionAnchor [", start, ":", end, "]"

    @Annotator = TextPositionAnchor.Annotator
    @$ = @Annotator.$

  # This is how we create a highlight out of this kind of anchor
  _createHighlight: (page) ->

    # Prepare the deferred object
    dfd = @$.Deferred()

    # Get the d-t-m in a consistent state
    @annotator.domMapper.prepare("highlighting").then (s) =>
      # When the d-t-m is ready, do this

      try
        # First we create the range from the stored stard and end offsets
        mappings = s.getMappingsForCharRange @start, @end, [page]

        # Get the wanted range out of the response of DTM
        realRange = mappings.sections[page].realRange

        # Get a BrowserRange
        browserRange = new @Annotator.Range.BrowserRange realRange

        # Get a NormalizedRange
        normedRange = browserRange.normalize @annotator.wrapper[0]

        # Create the highligh
        hl = new @Annotator.TextHighlight this, page, normedRange

        # Resolve the promise
        dfd.resolve hl

      catch error
        # Something went wrong during creating the highlight

        # Reject the promise
        try
          dfd.reject
            message: "Cought exception"
            error: error
        catch e2
          console.log "WTF", e2.stack

    # Return the promise
    dfd.promise()

  _verify: (reason, data) ->
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

class Annotator.Plugin.TextPosition extends Annotator.Plugin
  pluginInit: ->

    @Annotator = Annotator
    @$ = Annotator.$

    # Do we have the basic text anchors plugin loaded?
    unless @annotator.plugins.DomTextMapper
      throw new Error "The TextPosition Annotator plugin requires the DomTextMapper plugin."

    # Register the creator for text quote selectors
    @annotator.selectorCreators.push
      name: "TextPositionSelector"
      describe: @_getTextPositionSelector

    # Register the position-based anchoring strategy
    @annotator.anchoringStrategies.push
      # Position-based strategy. (The quote is verified.)
      # This can handle document structure changes,
      # but not the content changes.
      name: "position"
      create: @_createFromPositionSelector
      verify: @verifyTextAnchor

    # Export this anchor type
    @Annotator.TextPositionAnchor = TextPositionAnchor

  # Create a TextPositionSelector around a range
  _getTextPositionSelector: (selection) ->
    return [] unless selection.type is "text range"

    # Get a d-t-m ready-state token out from selection data
    state = selection.data.dtmState

    startOffset = (state.getStartInfoForNode selection.range.start).start
    endOffset = (state.getEndInfoForNode selection.range.end).end

    [
      type: "TextPositionSelector"
      start: startOffset
      end: endOffset
    ]


  # Create an anchor using the saved TextPositionSelector.
  # The quote is verified.
  _createFromPositionSelector: (annotation, target) =>
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
      savedQuote = @annotator.getQuoteForTarget target
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
      dfd.resolve new TextPositionAnchor @annotator, annotation, target,
        selector.start, selector.end,
        (s.getPageIndexForPos selector.start),
        (s.getPageIndexForPos selector.end),
        currentQuote

    dfd.promise()
