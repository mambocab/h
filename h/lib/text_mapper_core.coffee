# Common base class for all text mapper classes

class window.TextMapperCore

  CONTEXT_LEN = 32

  constructor: (@_id = "some mapper") ->
    @_createSyncAPI()

  # Create the _syncAPI field, used by the async API
  _createSyncAPI: ->
    @_syncAPI =
      getStartInfoForNode: @_getStartInfoForNode
      getEndInfoForNode: @_getEndInfoForNode
      getDocLength: => @_corpus.length
      getCorpus: => @_corpus
      getContextForCharRange: @_getContextForCharRange
      getMappingsForCharRange: @_getMappingsForCharRange
      getMappingsForCharRanges: @_getMappingsForCharRanges
      getPageIndexForPos: @_getPageIndexForPos

  _timestamp: -> new Date().getTime()

  # Call this fnction to wait for any pending operations
  ready: (reason, callback) ->
    unless callback?
      throw new Error "missing callback!"
    @_pendingCallbacks ?= []
    @_pendingCallbacks.push callback
    @_startScan reason
    null

  # This is done when scanning is finished
  _scanFinished: ->
    # Delete the flag;
    delete @_pendingScan

    # Call the callbacks (if any)
    while @_pendingCallbacks?.length
      callback = @_pendingCallbacks.shift()
      callback @_syncAPI

  # Get the context that encompasses the given charRange
  # in the rendered text of the document
  _getContextForCharRange: (start, end) =>
    if start < 0
      throw Error "Negative range start (", start, ") is invalid!"
    if end > @_corpus.length
      throw Error "Range end (", end, ") is after the end of corpus (",
        @_corpus.length, ")!"
    prefixStart = Math.max 0, start - CONTEXT_LEN
    prefix = @_corpus[ prefixStart ... start ]
    suffix = @_corpus[ end ... end + CONTEXT_LEN ]
    [prefix.trim(), suffix.trim()]

  # Get the matching DOM elements for a given set of charRanges
  # (Calles getMappingsForCharRange for each element in the given ist)
  _getMappingsForCharRanges: (charRanges) =>
    (@_getMappingsForCharRange charRange.start, charRange.end) for charRange in charRanges

  _getStartPosForNode: -> throw new Error "not implemented"
  _getEndPosForNode: -> throw new Error "not implemented"
  _getMappingsForCharRange: -> throw new Error "not implemented"
  _getPageIndexForPos: -> throw new Error "not implemented"

  _log: (msg...) ->
    console.log @_id, ":", msg...
