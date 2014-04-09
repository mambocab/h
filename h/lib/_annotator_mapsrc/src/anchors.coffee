# Abstract anchor class.
class Anchor

  constructor: (@annotator, @annotation, @target
      @startPage, @endPage,
      @quote, @diffHTML, @diffCaseOnly) ->

    unless @annotator? then throw "annotator is required!"
    unless @annotation? then throw "annotation is required!"
    unless @target? then throw "target is required!"
    unless @startPage? then "startPage is required!"
    unless @endPage? then throw "endPage is required!"
    unless @quote? then throw "quote is required!"

    @highlight = {}

    # Write our data back to the target
    @target.quote = @quote
    if @diffHTML
      @target.diffHTML = @diffHTML
    else
      delete @diffHTML
    if @diffCaseOnly
      @target.diffCaseOnly = @diffCaseOnly
    delete
      @diffCaseOnly

    # Store this anchor for the annotation
    @annotation.anchors.push this

    # Update the annotation's anchor status

    # This annotation is no longer an orphan
    Util.removeFromSet @annotation, @annotator.orphans

    # Does it have all the wanted anchors?
    if @annotation.anchors.length is @annotation.target.length
      # Great. Not a half-orphan either.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now fully anchored."
      Util.removeFromSet @annotation, @annotator.halfOrphans
    else
      # No, some anchors are still missing. A half-orphan, then.
#      console.log "Created anchor. Annotation", @annotation.id,
#        "is now a half-orphan."
      Util.addToSet @annotation, @annotator.halfOrphans

    # Store the anchor for all involved pages
    for pageIndex in [@startPage .. @endPage]
      @annotator.anchors[pageIndex] ?= []
      @annotator.anchors[pageIndex].push this

  # Creates the highlight for the given page. Should return a promise
  _createHighlight: (page) ->
    throw "Function not implemented"

  # Create the missing highlights for this anchor
  realize: () =>
    return if @fullyRealized # If we have everything, go home

    # Collect the pages that are already rendered
    renderedPages = [@startPage .. @endPage].filter (index) =>
      @annotator.domMapper.isPageMapped index

    # Collect the pages that are already rendered, but not yet anchored
    pagesTodo = renderedPages.filter (index) => not @highlight[index]?

    return unless pagesTodo.length # Return if nothing to do

    try
      created = []
      promises = []

      # Create the new highlights
      for page in pagesTodo
        promises.push p = @_createHighlight page  # Get a promise
        p.then (hl) => created.push @highlight[page] = hl
        p.fail (e) =>
          console.log "Error while trying to create highlight:",
            e.message, e.error.stack

      # Wait for all attempts for finish/fail
      Annotator.$.when(promises...).always =>
        # Finished creating the highlights

        # Check if everything is rendered now
        @fullyRealized =
          (renderedPages.length is @endPage - @startPage + 1) and # all rendered
          (created.length is pagesTodo.length) # all hilited

        # Announce the creation of the highlights
        if created.length
          @annotator.publish 'highlightsCreated', created

  # Remove the highlights for the given set of pages
  virtualize: (pageIndex) =>
    highlight = @highlight[pageIndex]

    return unless highlight? # No highlight for this page

    try
      highlight.removeFromDocument()
    catch error
      console.log "Could not remove HL from page", pageIndex, ":", error.stack

    delete @highlight[pageIndex]

    # Mark this anchor as not fully rendered
    @fullyRealized = false

    # Announce the removal of the highlight
    @annotator.publish 'highlightRemoved', highlight

  # Virtualize and remove an anchor from all involved pages and the annotation
  remove: () ->
    # Go over all the pages
    for index in [@startPage .. @endPage]
      @virtualize index
      anchors = @annotator.anchors[index]
      # Remove the anchor from the list
      Util.removeFromSet this, anchors
      # Kill the list if it's empty
      delete @annotator.anchors[index] unless anchors.length

    # Remove the anchor from the list
    Util.removeFromSet this, @annotation.anchors

    # Are there any anchors remaining?
    if @annotation.anchors.length
      # This annotation is a half-orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is a half-orphan now."
      Util.addToSet @annotation, @annotator.halfOrphans
    else
      # This annotation is an orphan now
#      console.log "Removed anchor, annotation", @annotation.id,
#        "is an orphan now."
      Util.addToSet @annotation, @annotator.orphans
      Util.removeFromSet @annotation, @annotator.halfOrphans

  # Check if this anchor is still valid. If not, remove it.
  verify: (reason, data) ->
    # Create a Deferred object
    dfd = Annotator.$.Deferred()

    # Do we have a way to verify this anchor?
    if @strategy.verify # We have a verify function to call.
      try
        @strategy.verify(this, reason, data).then (valid) =>
          @remove() unless valid        # Remove the anchor
          dfd.resolve()                 # Mark this as resolved
      catch error
        # The verify method crashed. How lame.
        console.log "Error while executing", @constructor.name,
          "'s verify method:", error.stack
        @remove()         # Remove the anchor
        dfd.resolve()     # Mark this as resolved
    else # No verify method specified
      console.log "Can't verify this", @constructor.name, "because the",
        "'" + @strategy.name + "'",
        "strategy (which was responsible for creating this anchor)"
        "did not specify a verify function."
      @remove()         # Remove the anchor
      dfd.resolve()     # Mark this as resolved

    # Return the promise
    dfd.promise()

  # Check if this anchor is still valid. If not, remove it.
  # This is called when the underlying annotation has been updated
  annotationUpdated: ->
    # Notify the highlights
    for index in [@startPage .. @endPage]
      @highlight[index]?.annotationUpdated()
