# This plugin defines the TextQuote selector
class Annotator.Plugin.TextQuote extends Annotator.Plugin

  # Plugin initialization
  pluginInit: ->

    @$ = Annotator.$

    # Register the creator for text quote selectors
    @annotator.selectorCreators.push
      name: "TextQuote"
      describe: @_createTextQuoteSelectorFromRange

    # Register function to get quote from this selector
    @annotator.getQuoteForTarget = (target) =>
      selector = @annotator.findSelector target.selector, "TextQuoteSelector"
      if selector?
        @annotator.normalizeString selector.exact
      else
        null

  # Create a TextQuoteSelector around a range
  _createTextQuoteSelectorFromRange: (selection) =>
    # Prepare the deferred object
    dfd = @$.Deferred()

    unless selection.type is "text range"
      dfd.reject "I can only describe text ranges"
      return dfd.promise()

    unless selection.range?
      throw new Error "Called getTextQuoteSelector(range) with null range!"

    rangeStart = selection.range.start
    unless rangeStart?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid start."
    rangeEnd = selection.range.end
    unless rangeEnd?
      throw new Error "Called getTextQuoteSelector(range) on a range with no valid end."

    # Resolve the promise with the selector
    dfd.resolve [
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
        exact: @annotator.normalizeString selection.range.text().trim()
    ]

    # Return the promise
    dfd.promise()
