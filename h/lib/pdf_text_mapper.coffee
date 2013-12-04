# PDF-Text-Mapper does for PDF.js documents what DOM-text-mapper does
# for regular documents.
class window.PDFTextMapper extends window.PageTextMapperCore

  # Are we working with a PDF document?
  @applicable: -> PDFView?.initialized ? false

  requiresSmartStringPadding: true

  # Get the number of pages
  getPageCount: -> PDFView.pages.length

  # Where are we in the document?
  getPageIndex: -> PDFView.page - 1

  # Jump to a given page
  setPageIndex: (index) -> PDFView.page = index + 1

  # Determine whether a given page has been rendered
  _isPageRendered: (index) ->
    return PDFView.pages[index]?.textLayer?.renderingDone

  # Get the root DOM node of a given page
  getRootNodeForPage: (index) ->
    PDFView.pages[index].textLayer.textLayerDiv

  constructor: ->
    @setEvents()
    super

  # Install watchers for various events to detect page rendering/unrendering
  setEvents: ->
    # Detect page rendering
    addEventListener "pagerender", (evt) =>

      # If we have not yet finished the initial scanning, then we are
      # not interested.
      return unless @pageInfo?

      index = evt.detail.pageNumber - 1
      @_onPageRendered index

    # Detect page un-rendering
    addEventListener "DOMNodeRemoved", (evt) =>
      node = evt.target
      if node.nodeType is Node.ELEMENT_NODE and node.nodeName.toLowerCase() is "div" and node.className is "textLayer"
        index = parseInt node.parentNode.id.substr(13) - 1

        # Forget info about the new DOM subtree
        @_unmapPage @pageInfo[index]

    $(PDFView.container).on 'scroll', => @_onScroll()

  _extractionPattern: /[ ]+/g
  _parseExtractedText: (text) => text.replace @_extractionPattern, " "

  # Update mapper data
  _startScan: (reason) ->
    return if @_pendingScan
    @_pendingScan = true

    if @pageInfo
      @_readyAllPages reason, => @_scanFinished()
    else
      @_startPDFTextExtraction reason

  # Start extracting the text from the PDF
  _startPDFTextExtraction: (reason) ->
    # Do we have a document yet?
    unless PDFView.pdfDocument?
      # If not, then wait for half a second, and retry
      #console.log "Delaying scan, because there is no document yet."
      setTimeout (=> @_startScan reason), 500
      return

    # Wait for the document to load
    PDFView.getPage(1).then =>
      console.log "Scanning PDF document for text, because", reason

      @pageInfo = []
      @_extractPDFPageText 0

  # Get a promise wrapper around ready()
  prepare: (reason) ->
    # Create a promise
    promise = new PDFJS.Promise()

    # Get everything ready
    @ready reason, (s) -> promise.resolve s # When done, resolve the promise

    # Return the promise
    promise

  # Manually extract the text from the PDF document.
  # This workaround is here to avoid depending PDFFindController's
  # own text extraction routines, which sometimes fail to add
  # adequate spacing.
  _extractPDFPageText: (pageIndex) ->
    # Get a handle on the page
    page = PDFFindController.pdfPageSource.pages[pageIndex]

    # Start the collection of page contents
    page.getTextContent().then (data) =>

      # First, join all the pieces from the bidiTexts
      rawContent = (text.str for text in data.bidiTexts).join " "

      # Do some post-processing
      content = @_parseExtractedText rawContent

      # Save the extracted content to our page information registery
      @pageInfo[pageIndex] = content: content

      if pageIndex is PDFView.pages.length - 1 # scanning is finished
        # Do some besic calculations with the content
        @_onHavePageContents()

        # OK, we are ready to rock.
        @_scanFinished()

        # Do whatever we need to do after scanning
        @_onAfterTextExtraction()
      else # There are some more pages to scan
        # Continue on the next page
        @_extractPDFPageText pageIndex + 1


  # Look up the page for a given DOM node
  _getPageForNode: (node) ->
    # Search for the root of this page
    div = node
    while (
      (div.nodeType isnt Node.ELEMENT_NODE) or
      not div.getAttribute("class")? or
      (div.getAttribute("class") isnt "textLayer")
    )
      div = div.parentNode

    # Fetch the page number from the id. ("pageContainerN")
    index = parseInt div.parentNode.id.substr(13) - 1

    # Look up the page
    @pageInfo[index]
