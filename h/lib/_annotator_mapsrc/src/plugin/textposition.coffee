# This anchor type stores information about a piece of text,
# described using start and end character offsets
class TextPositionAnchor extends Annotator.Anchor

  constructor: (annotator, annotation, target,
      @start, @end, startPage, endPage,
      quote, diffHTML, diffCaseOnly) ->

    super annotator, annotation, target, "text position",
      startPage, endPage,
      quote, diffHTML, diffCaseOnly

    # This pair of offsets is the key information,
    # upon which this anchor is based upon.
    unless @start? then throw new Error "start is required!"
    unless @end? then throw new Error "end is required!"

# Annotator plugin for text position-based anchoring
class Annotator.Plugin.TextPosition extends Annotator.Plugin

  pluginInit: ->

    @Annotator = Annotator

    # Do we have the basic text anchors plugin loaded?
    unless @annotator.plugins.DomTextMapper
      throw new Error "The TextPosition Annotator plugin requires the DomTextMapper plugin."

    # Register the creator for text quote selectors
    @annotator.selectorCreators.push
      name: "TextPositionSelector"
      describe: @_getTextPositionSelector

    @annotator.anchoringStrategies.push
      # Position-based strategy. (The quote is verified.)
      # This can handle document structure changes,
      # but not the content changes.
      name: "position"
      code: @createFromPositionSelector

    # Export the anchor type
    @Annotator.TextPositionAnchor = TextPositionAnchor

  # Create a TextPositionSelector around a range
  _getTextPositionSelector: (selection) =>
    return [] unless selection.type is "text range"

    startOffset = (@annotator.domMapper.getInfoForNode selection.range.start).start
    endOffset = (@annotator.domMapper.getInfoForNode selection.range.end).end

    [
      type: "TextPositionSelector"
      start: startOffset
      end: endOffset
    ]

  # Create an anchor using the saved TextPositionSelector.
  # The quote is verified.
  createFromPositionSelector: (annotation, target) =>

    # We need the TextPositionSelector
    selector = @annotator.findSelector target.selector, "TextPositionSelector"
    return unless selector?

    content = @annotator.domMapper.getCorpus()[selector.start .. selector.end-1].trim()
    currentQuote = @annotator.normalizeString content
    savedQuote = @annotator.getQuoteForTarget? target
    if savedQuote? and currentQuote isnt savedQuote
      # We have a saved quote, let's compare it to current content
      #console.log "Could not apply position selector" +
      #  " [#{selector.start}:#{selector.end}] to current document," +
      #  " because the quote has changed. " +
      #  "(Saved quote is '#{savedQuote}'." +
      #  " Current quote is '#{currentQuote}'.)"
      return null

    # Create a TextPositionAnchor from this data
    new TextPositionAnchor @annotator, annotation, target,
      selector.start, selector.end,
      (@annotator.domMapper.getPageIndexForPos selector.start),
      (@annotator.domMapper.getPageIndexForPos selector.end),
      currentQuote

