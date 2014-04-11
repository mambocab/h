# This plugin defines the TextQuote selector
class Annotator.Plugin.TextQuote extends Annotator.Plugin

  @Annotator = Annotator
  @$ = Annotator.$

  # Plugin initialization
  pluginInit: ->

    # Register the creator for text quote selectors
    @annotator.selectorCreators.push
      name: "TextQuoteSelector"
      describe: @_getTextQuoteSelector

    # Register function to get quote from this selector
    @annotator.getQuoteForTarget = (target) =>
      selector = @annotator.findSelector target.selector, "TextQuoteSelector"
      if selector?
        @annotator.normalizeString selector.exact
      else
        null

  # Create a TextQuoteSelector around a range
  _getTextQuoteSelector: (selection) =>
    return [] unless selection.type is "text range"

    unless selection.range?
      throw new Error "Called getTextQuoteSelector(range) with null range!"

    rangeStart = selection.range.start
    unless rangeStart?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid start."
    rangeEnd = selection.range.end
    unless rangeEnd?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid end."

    [
      if @annotator.plugins.DomTextMapper
        # Get a d-t-m ready state from the selection
        state = selection.data.dtmState

        # Calculate the quote and context using DTM

        #console.log "Start info:", state.getInfoForNode rangeStart

        startOffset = (state.getStartInfoForNode rangeStart).start
        endOffset = (state.getEndInfoForNode rangeEnd).end
        quote = state.getCorpus()[ startOffset ... endOffset ].trim()
        [prefix, suffix] = state.getContextForCharRange startOffset, endOffset

        type: "TextQuoteSelector"
        prefix: prefix
        exact: quote
        suffix: suffix
      else
        # Get the quote directly from the range

        type: "TextQuoteSelector"
        exact: selection.range.text().trim()
    ]
