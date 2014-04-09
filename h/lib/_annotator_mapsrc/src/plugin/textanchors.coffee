# This plugin implements the usual text anchor.
# Contains
#  * the the definitions of the corresponding selectors,
#  * the anchor class,
#  * the basic anchoring strategies

# This anhor type stores information about a piece of text,
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

# This anhor type stores information about a piece of text,
# described using the actual reference to the range in the DOM.
# 
# When creating this kind of anchor, you are supposed to pass
# in a NormalizedRange object, which should cover exactly
# the wanted piece of text; no character offset correction is supported.
#
# Also, please note that these anchors can not really be virtualized,
# because they don't have any truly DOM-independent information;
# the core information stored is the reference to an object which
# lives in the DOM. Therefore, no lazy loading is possible with
# this kind of anchor. For that, use TextPositionAnchor instead.
class TextRangeAnchor extends Annotator.Anchor

  @Annotator = Annotator

  constructor: (annotator, annotation, target, @range, quote) ->

    super annotator, annotation, target, 0, 0, quote

    unless @range? then throw new Error "range is required!"

    @Annotator = TextRangeAnchor.Annotator
    @$ = @Annotator.$

  # This is how we create a highlight out of this kind of anchor
  _createHighlight: ->

    # Prepare the deferred object
    dfd = @$.Deferred()

    # Create the highligh
    hl = new @Annotator.TextHighlight this, 0, @range

    # Resolve the promise
    dfd.resolve hl

    # Return the promise
    dfd.promise()


class Annotator.Plugin.TextAnchors extends Annotator.Plugin

  # Check whether we can rely on DTM
  checkDTM: -> @useDTM = @annotator.domMapper?.ready

  # Plugin initialization
  pluginInit: ->
    # We need text highlights
    unless @annotator.plugins.TextHighlights
      throw new Error "The TextAnchors Annotator plugin requires the TextHighlights plugin."

    @Annotator = Annotator
    @$ = Annotator.$
        
    # Register our anchoring strategies
    @annotator.anchoringStrategies.push
      # Simple strategy based on DOM Range
      name: "range"
      create: @createFromRangeSelector
      verify: @verifyTextAnchor

    @annotator.anchoringStrategies.push
      # Position-based strategy. (The quote is verified.)
      # This can handle document structure changes,
      # but not the content changes.
      name: "position"
      create: @createFromPositionSelector
      verify: @verifyTextAnchor

    # Register the event handlers required for creating a selection
    $(@annotator.wrapper).bind({
      "mouseup": @checkForEndSelection
    })

    # Export these anchor types
    @Annotator.TextPositionAnchor = TextPositionAnchor
    @Annotator.TextRangeAnchor = TextRangeAnchor

    # React to the enableAnnotation event
    @annotator.subscribe "enableAnnotating", (value) => if value
      # If annotation is now enable, check if we have a valid selection
      setTimeout @checkForEndSelection, 500

    null


  # Code used to create annotations around text ranges =====================

  # Gets the current selection excluding any nodes that fall outside of
  # the @wrapper. Then returns and Array of NormalizedRange instances.
  #
  # Examples
  #
  #   # A selection inside @wrapper
  #   annotation.getSelectedRanges()
  #   # => Returns [NormalizedRange]
  #
  #   # A selection outside of @wrapper
  #   annotation.getSelectedRanges()
  #   # => Returns []
  #
  # Returns Array of NormalizedRange instances.
  _getSelectedRanges: ->
    selection = @Annotator.util.getGlobal().getSelection()

    ranges = []
    rangesToIgnore = []
    unless selection.isCollapsed
      ranges = for i in [0...selection.rangeCount]
        r = selection.getRangeAt(i)
        browserRange = new @Annotator.Range.BrowserRange(r)
        normedRange = browserRange.normalize().limit @annotator.wrapper[0]

        # If the new range falls fully outside the wrapper, we
        # should add it back to the document but not return it from
        # this method
        rangesToIgnore.push(r) if normedRange is null

        normedRange

      # BrowserRange#normalize() modifies the DOM structure and deselects the
      # underlying text as a result. So here we remove the selected ranges and
      # reapply the new ones.
      selection.removeAllRanges()

    for r in rangesToIgnore
      selection.addRange(r)

    # Remove any ranges that fell outside of @wrapper.
    @$.grep ranges, (range) ->
      # Add the normed range back to the selection if it exists.
      selection.addRange(range.toRange()) if range
      range

  # This is called then the mouse is released.
  # Checks to see if a selection has been made on mouseup and if so,
  # calls Annotator's onSuccessfulSelection method.
  # Also resets the @mouseIsDown property.
  #
  # event - The event triggered this. Usually it's a mouseup Event,
  #         but that's not necessary. The coordinates will be used,
  #         if they are present. If the event (or the coordinates)
  #         are missing, new coordinates will be generated, based on the
  #         selected ranges.
  #
  # Returns nothing.
  checkForEndSelection: (event = {}) =>
    @annotator.mouseIsDown = false

    # We don't care about the adder button click
    return if @annotator.inAdderClick

    # Get the currently selected ranges.
    selectedRanges = @_getSelectedRanges()

    for range in selectedRanges
      container = range.commonAncestor
      # TODO: what is selection ends inside a different type of highlight?
      if @Annotator.TextHighlight.isInstance container
        container = @Annotator.TextHighlight.getIndependentParent container
      return if @annotator.isAnnotator(container)

    # Before going any further, re-evaluate the presence of DTM
    @checkDTM()

    if selectedRanges.length
      if @useDTM
        @annotator.domMapper.prepare("creating selectors").then (state) =>
          @_collectTargets event, selectedRanges, state
      else
        @_collectTargets event, selectedRanges
    else
      @annotator.onFailedSelection event

  # Build the targets from the annotation.
  #
  # Called when d-t-m is already prepared (or unavailable)
  _collectTargets: (event, selectedRanges, state) ->
    event.targets = (@getTargetFromRange(r, state) for r in selectedRanges)

    # Do we have valid page coordinates inside the event
    # which has triggered this function?
    unless event.pageX
      # No, we don't. Adding fake coordinates
      pos = selectedRanges[0].getEndCoords()
      event.pageX = pos.x
      event.pageY = pos.y #- window.scrollY

    @annotator.onSuccessfulSelection event

  # Create a RangeSelector around a range
  _getRangeSelector: (range) ->
    sr = range.serialize @annotator.wrapper[0]

    type: "RangeSelector"
    startContainer: sr.startContainer
    startOffset: sr.startOffset
    endContainer: sr.endContainer
    endOffset: sr.endOffset

  # Create a TextQuoteSelector around a range
  _getTextQuoteSelector: (range, state) ->
    unless range?
      throw new Error "Called getTextQuoteSelector(range) with null range!"

    rangeStart = range.start
    unless rangeStart?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid start."
    rangeEnd = range.end
    unless rangeEnd?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid end."

    if @useDTM
      # Calculate the quote and context using DTM
#
#      console.log "Start info:", state.getInfoForNode rangeStart

      startOffset = (state.getInfoForNode rangeStart).start
      endOffset = (state.getInfoForNode rangeEnd).end
      quote = state.getCorpus()[ startOffset ... endOffset ].trim()
      [prefix, suffix] = state.getContextForCharRange startOffset, endOffset

      type: "TextQuoteSelector"
      exact: quote
      prefix: prefix
      suffix: suffix
    else
      # Get the quote directly from the range

      type: "TextQuoteSelector"
      exact: range.text().trim()


  # Create a TextPositionSelector around a range
  _getTextPositionSelector: (range, state) ->
    startOffset = (state.getInfoForNode range.start).start
    endOffset = (state.getInfoForNode range.end).end

    type: "TextPositionSelector"
    start: startOffset
    end: endOffset

  # Create a target around a normalizedRange
  getTargetFromRange: (range, state) ->
    # Create the target
    result =
      source: @annotator.getHref()
      selector: [
        @_getRangeSelector range
        @_getTextQuoteSelector range, state
      ]

    if @useDTM
      # If we have DTM, then we can save a position selector, too
      result.selector.push @_getTextPositionSelector range, state
    result

  # Look up the quote from the appropriate selector
  getQuoteForTarget: (target) ->
    selector = @annotator.findSelector target.selector, "TextQuoteSelector"
    if selector?
      @annotator.normalizeString selector.exact
    else
      null

  # Strategies used for creating anchors from saved data

  # Verify a text position anchor
  verifyTextAnchor: (anchor, reason, data) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    # When we don't have d-t-m, we might create TextRangeAnchors.
    # Lets' handle that first!"
    if anchor instanceof @Annotator.TextRangeAnchor
      # Basically, we have no idea
      dfd.resolve false # we don't trust in text ranges too much
      return dfd.promise()

    # What else could this be?
    unless anchor instanceof @Annotator.TextPositionAnchor
      # This should not happen. No idea
      console.log "Hey, how come that I don't know anything about",
        "this kind of anchor?", anchor
      dfd.resolve false # we have no idea what this is
      return dfd.promise()

    # OK, now we know that we have TextPositionAnchor.

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

  # Create and anchor using the saved Range selector.
  # The quote is verified.
  createFromRangeSelector: (annotation, target) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    # Look up the required selector
    selector = @annotator.findSelector target.selector, "RangeSelector"
    unless selector?
      dfd.reject "no RangeSelector found", true
      return dfd.promise()

    # Before going any further, re-evaluate the presence of DTM
    @checkDTM()

    # Try to apply the saved XPath
    try
      range = @Annotator.Range.sniff selector
      normedRange = range.normalize @annotator.wrapper[0]
    catch error
      dfd.reject "failed to normalize range: " + error.message
      return dfd.promise()

    # Look up the saved quote
    savedQuote = @getQuoteForTarget target

    # Get the text of this range
    if @useDTM
      # Determine the current content of the given range using DTM

      # Get the d-t-m in a consistent state
      @annotator.domMapper.prepare("anchoring").then (s) =>
        # When the d-t-m is ready, do this

        # determine the start position
        startInfo = s.getInfoForNode normedRange.start
        startOffset = startInfo.start
        unless startOffset?
          dfd.reject "the saved quote doesn't match"
          return dfd.promise()

        # determine the end position
        endInfo = s.getInfoForNode normedRange.end
        endOffset = endInfo.end
        unless endOffset?
          dfd.reject "the saved quote doesn't match"
          return dfd.promise()

        # extract the content of the document
        q = s.getCorpus()[ startOffset ... endOffset ].trim()
        currentQuote = @annotator.normalizeString q

        # Compare saved and current quotes
        if savedQuote? and currentQuote isnt savedQuote
          #console.log "Could not apply XPath selector to current document, "+
          #  "because the quote has changed. "+
          #  "(Saved quote is '#{savedQuote}'."+
          #  " Current quote is '#{currentQuote}'.)"
          dfd.reject "the saved quote doesn't match"
          return dfd.promise()

        # Create a TextPositionAnchor from the start and end offsets
        # of this range
        # (to be used with dom-text-mapper)
        dfd.resolve new TextPositionAnchor @annotator, annotation, target,
          startInfo.start, endInfo.end,
          (startInfo.pageIndex ? 0), (endInfo.pageIndex ? 0),
          currentQuote

    else # No DTM present
      # Determine the current content of the given range directly
      currentQuote = @annotator.normalizeString normedRange.text().trim()

      # Compare quotes
      if savedQuote? and currentQuote isnt savedQuote
        #console.log "Could not apply XPath selector to current document, " +
        #  "because the quote has changed. (Saved quote is '#{savedQuote}'." +
        #  " Current quote is '#{currentQuote}'.)"
        dfd.reject "the saved quote doesn't match"
        return dfd.promise()

      # Create a TextRangeAnchor from this range
      # (to be used whithout dom-text-mapper)
      dfd.resolve new TextRangeAnchor @annotator, annotation, target,
        normedRange, currentQuote

    dfd.promise()

  # Create an anchor using the saved TextPositionSelector.
  # The quote is verified.
  createFromPositionSelector: (annotation, target) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    # Before going any further, re-evaluate the presence of DTM
    @checkDTM()

    # This strategy depends on dom-text-mapper
    unless @useDTM
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
      savedQuote = @getQuoteForTarget target
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
