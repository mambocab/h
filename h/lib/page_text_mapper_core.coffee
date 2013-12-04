# Common functions for all page-based document mapper modules
class window.PageTextMapperCore extends TextMapperCore

  # Get the page index for a given character position
  _getPageIndexForPos: (pos) =>
    for info in @pageInfo
      if info.start <= pos < info.end
        return info.index
        @log "Not on page " + info.index
    return -1

  # Return the root node for a given page
  getPageRoot: (index) -> @getRootNodeForPage index

  # A new page was rendered
  _onPageRendered: (index) =>
    #@log "Allegedly rendered page #" + index

    # Is it really rendered?
    unless @_isPageRendered index
    #@log "Page #" + index + " is not really rendered yet."
      setTimeout (=> @_onPageRendered index), 1000
      return

    # Collect info about the new DOM subtree
    @_mapPage @pageInfo[index], "page has been rendered"

  # Determine whether a given page has been rendered and mapped
  isPageMapped: (index) ->
    return @pageInfo[index]?.domMapper?

   # Create the mappings for a given page    
  _mapPage: (info, reason) ->
    info.node = @getRootNodeForPage info.index        
    info.domMapper = new DomTextMapper
      id: "d-t-m for page #" + info.index
      rootNode: info.node
    if @requiresSmartStringPadding
      info.domMapper.setExpectedContent info.content
    info.domMapper.ready reason, (s) =>
      renderedContent = s.getCorpus()
      if renderedContent isnt info.content
        @log "Oops. Mismatch between rendered and extracted text, while mapping page #" + info.index + "!"
        console.trace()
        @log "Rendered: " + renderedContent
        @log "Extracted: " + info.content

      info.node.addEventListener "corpusChange", =>
        @log "Ooops. Corpus has changed on one of the pages!"
        @log "TODO: We should do something about this, to update the global corpus!"

      # Announce the newly available page
      setTimeout ->
        event = document.createEvent "UIEvents"
        event.initUIEvent "docPageMapped", false, false, window, 0
        event.pageIndex = info.index
        window.dispatchEvent event

  # Go over the pages, and get them ready
  _readyAllPages: (reason, callback) ->
    # This would be a breeze with promises, but we can't use them here,
    # because we want to keep the dependencies really minimal,
    # so we are doing it manually.

    # Set initial data
    pagesToGo = 0
    cycleOver = false
    endTriggered = false

    # Go over all the pages
    @pageInfo.forEach (info, i) =>
      if @_isPageRendered i
        pagesToGo++
        info.domMapper.ready reason, =>
          pagesToGo--
          if pagesToGo is 0 and cycleOver and not endTriggered
            endTriggered = true
            callback "Done"
    cycleOver = true
    unless endTriggered
      endTriggered = true
      callback "Done"

  # Delete the mappings for a given page
  _unmapPage: (info) ->
    delete info.domMapper

    # Announce the unavailable page
    event = document.createEvent "UIEvents"
    event.initUIEvent "docPageUnmapped", false, false, window, 0
    event.pageIndex = info.index
    window.dispatchEvent event

  # Announce scrolling
  _onScroll: ->
    event = document.createEvent "UIEvents"
    event.initUIEvent "docPageScrolling", false, false, window, 0
    window.dispatchEvent event

  # Look up info about a give DOM node, uniting page and node info
  _getInfoForNode: (node) =>
    pageData = @_getPageForNode node
    nodeData = pageData.domMapper._getInfoForNode node
    # Copy info about the node
    info = {}
    for k,v of nodeData
      info[k] = v
    # Correct the chatacter offsets with that of the page
    info.start += pageData.start
    info.end += pageData.start
    info.pageIndex = pageData.index
    info

  # Return some data about a given character range
  _getMappingsForCharRange: (start, end, pages) =>
    #@log "Get mappings for char range [" + start + "; " + end + "], for pages " + pages + "."

    # Check out which pages are these on
    startIndex = @_getPageIndexForPos start
    endIndex = @_getPageIndexForPos end
    #@log "These are on pages [" + startIndex + ".." + endIndex + "]."

    # Function to get the relevant section inside a given page
    getSection = (index) =>
      info = @pageInfo[index]

      # Calculate in-page offsets
      realStart = (Math.max info.start, start) - info.start
      realEnd = (Math.min info.end, end) - info.start

      # Get the range inside the page
      mappings = info.domMapper._getMappingsForCharRange realStart, realEnd
      mappings.sections[0]

    # Get the section for all involved pages
    sections = {}
    for index in pages ? [startIndex..endIndex]
      sections[index] = getSection index

    # Return the data
    sections: sections

  # Call this in scan, when you have the page contents
  _onHavePageContents: ->
    # Join all the text together
    @_corpus = (info.content for info in @pageInfo).join " "

    # Go over the pages, and calculate some basic info
    pos = 0
    @pageInfo.forEach (info, i) =>
      info.index = i
      info.len = info.content.length        
      info.start = pos
      info.end = (pos += info.len + 1)

  # Call this in scan, after resolving the promise  
  _onAfterTextExtraction: ->
    # Go over the pages again, and map the rendered ones
    @pageInfo.forEach (info, i) =>
      if @_isPageRendered i
        @_mapPage info, "text extraction finished"

  # Test all the mappings on all pages
  _testAllMappings: ->
    @pageInfo.forEach (info, i) =>
      info.domMapper?._testAllMappings?()
