# This anchor type stores information about a piece of text,
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
#
# This plugin also adds a strategy to reanchor based on range selectors.
# If the TextQuote plugin is also loaded, then it will also check
# the saved quote against what is available now.
#
# If the TextPosition plugin is loaded, it will create a TextPosition
# anchor; otherwise it will record a TextRangeAnchor.
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

  _verify: ->
    # Prepare the deferred object
    dfd = @$.Deferred()

    # Basically, we have no idea
    dfd.resolve false # we don't trust in text ranges too much

    dfd.promise()


# Annotator plugin for creating, and anchoring based on text range
# selectors
class Annotator.Plugin.TextRange extends Annotator.Plugin

  pluginInit: ->

    @Annotator = Annotator
    @$ = Annotator.$

    # Register the creator for range selectors
    @annotator.selectorCreators.push
      name: "RangeSelector"
      describe: @_getRangeSelector

    # Register our anchoring strategy
    @annotator.anchoringStrategies.push
      # Simple strategy based on DOM Range
      name: "range"
      create: @_createFromRangeSelector

    # Export the anchor type
    @Annotator.TextRangeAnchor = TextRangeAnchor

  # Create a RangeSelector around a range
  _getRangeSelector: (selection) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    unless selection.type is "text range"
      # Resolve the promise with an empty list.
      # (We can only describe text range.)
      dfd.resolve []
      return dfd.promise()

    sr = selection.range.serialize @annotator.wrapper[0]
    # Resolve the promise with the selector
    dfd.resolve [
      type: "RangeSelector"
      startContainer: sr.startContainer
      startOffset: sr.startOffset
      endContainer: sr.endContainer
      endOffset: sr.endOffset
    ]

    # Return the promise
    dfd.promise()

  # Create and anchor using the saved Range selector.
  # The quote is verified.
  _createFromRangeSelector: (annotation, target) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    # Look up the required selector
    selector = @annotator.findSelector target.selector, "RangeSelector"
    unless selector?
      dfd.reject "no RangeSelector found", true
      return dfd.promise()

    # Try to apply the saved XPath
    try
      range = @Annotator.Range.sniff selector
      normedRange = range.normalize @annotator.wrapper[0]
    catch error
      dfd.reject "failed to normalize range: " + error.message
      return dfd.promise()

    # Look up the saved quote
    savedQuote = @annotator.getQuoteForTarget? target

    # Get the text of this range
    if @annotator.plugins.TextPosition
      # Determine the current content of the given range using DTM

      # Get the d-t-m in a consistent state
      @annotator.domMapper.prepare("anchoring").then (s) =>
        # When the d-t-m is ready, do this

        # determine the start position
        startInfo = s.getStartInfoForNode normedRange.start
        startOffset = startInfo.start
        unless startOffset?
          dfd.reject "the saved quote doesn't match"
          return dfd.promise()

        # determine the end position
        endInfo = s.getEndInfoForNode normedRange.end
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
        dfd.resolve new @Annotator.TextPositionAnchor @annotator, annotation, target,
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
