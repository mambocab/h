# Abstract anchor class.
class Anchor

  constructor: (@annotator, @annotation, @target, @type,
      @startPage, @endPage,
      @quote, @diffHTML, @diffCaseOnly) ->

    unless @annotator? then throw new Error "annotator is required!"
    unless @annotation? then throw new Error "annotation is required!"
    unless @target? then throw new Error "target is required!"
    unless @type then throw new Error "type is required!"
    unless @startPage? then new Error "startPage is required!"
    unless @endPage? then throw new Error "endPage is required!"
    unless @quote? then throw new Error "quote is required!"

    @highlight = {}

  # Create the missing highlights for this anchor
  realize: () =>
    return if @fullyRealized # If we have everything, go home

    # Collect the pages that are already rendered
    renderedPages = [@startPage .. @endPage].filter (index) =>
      @annotator.domMapper.isPageMapped index

    # Collect the pages that are already rendered, but not yet anchored
    pagesTodo = renderedPages.filter (index) => not @highlight[index]?

    return unless pagesTodo.length # Return if nothing to do

    # Create the new highlights
    created = for page in pagesTodo
      @highlight[page] = @annotator._createHighlight this, page

    # Check if everything is rendered now
    @fullyRealized = renderedPages.length is @endPage - @startPage + 1

    # Announce the creation of the highlights
    @annotator.publish 'highlightsCreated', created

  # Remove the highlights for the given set of pages
  virtualize: (pageIndex) =>
    highlight = @highlight[pageIndex]

    return unless highlight? # No highlight for this page

    highlight.removeFromDocument()

    delete @highlight[pageIndex]

    # Mark this anchor as not fully rendered
    @fullyRealized = false

    # Announce the removal of the highlight
    @annotator.publish 'highlightRemoved', highlight

  # Virtualize and remove an anchor from all involved pages
  remove: ->
    # Go over all the pages
    for index in [@startPage .. @endPage]
      @virtualize index
      anchors = @annotator.anchors[index]
      # Remove the anchor from the list
      i = anchors.indexOf this
      anchors[i..i] = []
      # Kill the list if it's empty
      delete @annotator.anchors[index] unless anchors.length

  # This is called when the underlying Annotator has been udpated
  annotationUpdated: ->
    # Notify the highlights
    for index in [@startPage .. @endPage]
      @highlight[index]?.annotationUpdated()
