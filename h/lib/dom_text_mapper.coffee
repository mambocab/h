class SubTreeCollection

  constructor: ->
    @roots = []

  # Unite a new node with a pre-existing set of nodex.
  #
  # The rules are as follows:
  #  * If the node is identical to, or a successor of any of the
  #    the existing nodes, then it's dropped.
  #  * Otherwise it's added.
  #  * If the node is an ancestor of any of the existing nodes,
  #    the those nodes are dropper.
  add: (node) ->

    # Is this node already contained by any of the existing subtrees?
    for root in @roots
      return if root.contains node

    # If we made it to this point, then it means that this is new.

    newRoots = @roots.slice()

    # Go over the collected roots, and see if some of them should be dropped
    for root in @roots
      if node.contains root # Is this root obsolete now?
        i = newRoots.indexOf this  # Drop this root
        newRoots[i..i] = []

    # Add the new node to the end of the list
    newRoots.push node

    # Replace the old list with the new one
    @roots = newRoots

class window.DomTextMapper extends TextMapperCore

  @applicable: -> true

  USE_TABLE_TEXT_WORKAROUND = true
  USE_EMPTY_TEXT_WORKAROUND = true
  SELECT_CHILDREN_INSTEAD = ["thead", "tbody", "tfoot", "ol", "a", "caption", "p", "span", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "li", "form"]

  @instances: 0

  constructor: (@options = {})->
    super(@options.id ? "d-t-m #" + DomTextMapper.instances)
    if @options.rootNode?
      @setRootNode @options.rootNode
    else
      @setRealRoot()
    DomTextMapper.instances += 1

  _createSyncAPI: ->
    super
    @_syncAPI.getInfoForPath = @_getInfoForPath
    @_syncAPI.getContentForPath = @_getContentForPath
    @_syncAPI.getLengthForPath = @_getLengthForPath

  # ===== Public methods =======

  # Consider only the sub-tree beginning with the given node.
  # 
  # This will be the root node to use for all operations.
  setRootNode: (rootNode) ->
    @rootWin = window
    @pathStartNode = @_changeRootNode rootNode

  # Consider only the sub-tree beginning with the node whose ID was given.
  # 
  # This will be the root node to use for all operations.
  setRootId: (rootId) -> @setRootNode document.getElementById rootId

  # Use this iframe for operations.
  #
  # Call this when mapping content in an iframe.
  setRootIframe: (iframeId) ->
    iframe = window.document.getElementById iframeId
    unless iframe?
      throw new Error "Can't find iframe with specified ID!"
    @rootWin = iframe.contentWindow
    unless @rootWin?
      throw new Error "Can't access contents of the specified iframe!"
    @_changeRootNode @rootWin.document
    @pathStartNode = @getBody()

  # Return the default path
  getDefaultPath: -> @getPathTo @pathStartNode

  # Work with the whole DOM tree
  # 
  # (This is the default; you only need to call this, if you have configured
  # a different root earlier, and now you want to restore the default setting.)
  setRealRoot: ->
    @rootWin = window
    @_changeRootNode document
    @pathStartNode = @getBody() 

  setExpectedContent: (content) ->
    @expectedContent = content

  # Scan the document
  #
  # Traverses the DOM, collects various information, and
  # creates mappings between the string indices
  # (as appearing in the rendered text) and the DOM elements.  
  # 
  # An map is returned, where the keys are the paths, and the
  # values are objects with info about those parts of the DOM.
  #   path: the valid path value
  #   node: reference to the DOM node
  #   content: the text content of the node, as rendered by the browser
  #   length: the length of the next content
  _startScan: (reason = "unknown reason") ->
    return if @_pendingScan
    @_pendingScan = true

    # Have we ever scanned?
    if @path?
      # Do an incremental update instead
      @_syncState reason

      # We are done; take care of any callbacks
      @_scanFinished()
      return

    unless @pathStartNode.ownerDocument.body.contains @pathStartNode
      # We cannot map nodes that are not attached.
      throw new Error "This node is not attached to dom."

    @log "Starting DOM scan, because", reason
    # Forget any recorded changes, we are starting with a clean slate.
    @observer.takeSummaries()
    startTime = @timestamp()
    @saveSelection()
    @path = {}
    @traverseSubTree @pathStartNode, @getDefaultPath()
    t1 = @timestamp()
    @log "Phase I (Path traversal) took " + (t1 - startTime) + " ms."

    path = @getPathTo @pathStartNode
    node = @path[path].node
    @collectPositions node, path, null, 0, 0
    @_corpus = @getNodeContent @path[path].node, false
    @restoreSelection()
#    @log "Corpus is: " + @_corpus

    t2 = @timestamp()
    @log "Phase II (offset calculation) took " + (t2 - t1) + " ms."

    @log "Scan took", t2 - startTime, "ms."

    # We are done; take care of any callbacks
    @_scanFinished()

  # Select the given path (for visual identification),
  # and optionally scroll to it
  selectPath: (path, scroll = false) ->
    @scan "selectPath('" + path + "')"
    info = @path[path]
    unless info? then throw new Error "I have no info about a node at " + path
    node = info?.node
    node or= @lookUpNode info.path
    @selectNode node, scroll

  # Update the mapping information to react to changes in the DOM
  #
  # node is the sub-tree of the changed part.
  _performUpdateOnNode: (node, reason = "(no reason)") ->
    # We really need a node
    unless node
      throw new Error "Called performUpdate with a null node!"

    # No point in runnign this, we don't even have mapping data yet.
    return unless @path

    # Look up the info we have about this node
    path = @getPathTo node
    pathInfo = @path[path]

    #@log "Performing update on node @", path

    # Do we have data about this node?
    while not pathInfo
      # If not, go up one level.
      @log "We don't have any data about the node @", path, ". Moving up."
      node = node.parentNode
      path = @getPathTo node
      pathInfo = @path[path]

    # Start the clock
    startTime = @timestamp()

    # Save the selection, since we will have to restore it later.
    @saveSelection()

    #@log reason, ": performing update on node @ path", path,
    #  "(", pathInfo.length, "characters)"

    # Save the old and the new content, for later reference
    oldContent = pathInfo.content
    content = @getNodeContent node, false

    # Decide whether we are dealing with a corpus change
    corpusChanged = oldContent isnt content

    if corpusChanged
      lengthDelta = content.length - oldContent.length
#      @dmp ?= new DTM_DMPMatcher()
#      diff = @dmp.compare oldContent, content, true
#      @log "** Corpus change (at", path, "):", diff.diffExplanation
#      @log "** Length change: ", lengthDelta, " chars"
#      @log "Remaining corpus (at", path, "):", content

    # === Phase 1: Drop the invalidated data

    #@log "Dropping obsolete path info for children of", path, "..."
    prefix = path + "/" # The path to drop

    # Collect the paths to delete (all children of this node)
    pathsToDrop = (p for p, data of @path when @stringStartsWith p, prefix)

    # Has the corpus changed?
    if corpusChanged
      # If yes, drop all data about this node / path
      pathsToDrop.push path

      # Also save the start and end positions from the pathInfo
      oldStart = pathInfo.start
      oldEnd = pathInfo.end

    # Actually drop the selected paths
    delete @path[p] for p in pathsToDrop

    # === Phase 2: if necessary, modify the parts impacted by this change
    # (Parent nodes and later siblings)

    if corpusChanged
      #@log "Hmm... overall node content has changed @", path, "!"
      unless node is @pathStartNode
        #@log "Updating ancestors and siblings"
        @_alterAncestorsMappingData node, pathInfo, oldStart, oldEnd, content
        @_alterSiblingsMappingData node, pathInfo, oldStart, oldEnd, content

    # Phase 3: re-scan the invalidated part

    #@log "Collecting new path info for", path

    @traverseSubTree node, path

    #@log "Done. Updating mappings..."

    # Is this the root node?
    if node is @pathStartNode
      # Yes, we have rescanned starting with the root node!
      @log "Ended up rescanning the whole doc."
      @collectPositions node, path, null, 0, 0
      @_updateCorpus lengthDelta
    else
      # This was not the root path, so we must have a valid parent.
      parentPath = @_parentPath path
      parentPathInfo = @path[parentPath]

      # Now let's find out where we are inside our parent
      predecessorInfo = @_findRelevantPredecessor node, parentPath
      oldIndex = unless predecessorInfo?
        0
      else
        predecessorInfo.end - parentPathInfo.start

      # Recursively calculate all the positions
      @collectPositions node, path, parentPathInfo.content,
          parentPathInfo.start, oldIndex
        
#    @log "Data update took " + (@timestamp() - startTime) + " ms."

    # Restore the selection
    @restoreSelection()

    # Return whether the corpus has changed
    corpusChanged

  # Update the corpus
  _updateCorpus: (lengthDelta) ->
    #@log "Recalculating corpus."
    if lengthDelta
      #@log "(Length delta:", lengthDelta, ")"
    else
      lengthDelta = 0

    @_corpus = if @expectedContent?  # Do we have expected content?
      @expectedContent               # There not much to calculate, then
    else                             # No hard-wired result, let's calculate
      unless @path["."]
        @log "We can't find info about root."
        throw new Error "Internal error"
      content = @path["."].content   # This is the base we are going to use
      if @_ignorePos?                # Is there stuff at the end to ignore?
        @_ignorePos += lengthDelta   # Update the ignore index
        if @_ignorePos               # Is there anything left?
          content[ ... @_ignorePos ] # Return the wanted segment
        else                         # No, whole text is ignored
          ""                         # Return an empty string
      else                           # There is no ignore
        content                      # We are going to use the whole content


  # Given the fact the the corpus of a given note has changed,
  # update the mapping info of its ancestors
  _alterAncestorsMappingData: (node, pathInfo, oldStart, oldEnd, newContent) ->

    # Don't bother if this is a mystery node; the ancestors don't contain
    # this content anyway
    return if pathInfo.mystery

    # Calculate how the length has changed
    lengthDelta = newContent.length - (oldEnd - oldStart)

    # Is this the root node?
    if node is @pathStartNode
      @_updateCorpus lengthDelta

      # There are no more ancestors, so return
      return

    parentPath = @_parentPath pathInfo.path
    parentPathInfo = @path[parentPath]

    # Save old start and end
    opStart = parentPathInfo.start
    opEnd = parentPathInfo.end

    # Calculate where the old content used to go in this parent
    pStart = oldStart - opStart
    pEnd = oldEnd - opStart
    #@log "Relative to the parent: [", pStart, "..", pEnd, "]"

    pContent = parentPathInfo.content

    # Calculate the changed content

    # Get the prefix
    prefix = pContent[ ... pStart ]

    # Get the suffix
    suffix = pContent[pEnd ..]

    # Replace the changed part in the parent's content
    parentPathInfo.content = newContent = prefix + newContent + suffix

    # Fix up the length and the end position
    parentPathInfo.length += lengthDelta
    parentPathInfo.end += lengthDelta
    if isNaN parentPathInfo.end
      throw new Error "Internal error: got a NaN"

    # Do the same with the next ancestor
    @_alterAncestorsMappingData parentPathInfo.node, parentPathInfo,
      opStart, opEnd, newContent


  # Given the fact the the corpus of a given note has changed,
  # update the mapping info of all later nodes.
  _alterSiblingsMappingData: (node, pathInfo, oldStart, oldEnd, newContent) ->

    # Don't bother if this is a mystery node; the ancestors don't contain
    # this content anyway, so no cortinates to fix up.
    return if pathInfo.mystery
        
    # Calculate the offset, based on the difference in length
    delta = newContent.length - (oldEnd - oldStart)

    # If the length delta is zero (ie. the old content has the same length
    # as the new content), we don't have to do anything
    return unless delta

    # Go over all the elements that are later then the changed node
    for p, info of @path when (not info.mystery) and info.start >= oldEnd
      # Correct their positions
      info.start += delta
      info.end += delta
      if isNaN info.end
        throw new Error "Internal error: got a NaN"

  # Return info for a given path in the DOM
  _getInfoForPath: (path) =>
    result = @path[path]
    unless result?
      throw new Error "Found no info for path '" + path + "'!"
    result

  # Return info for a given node in the DOM
  _getInfoForNode: (node) =>
    @_startScan "getInfoForNode()"
    unless node?
      throw new Error "Called getInfoForNode(node) with null node!"
    @_getInfoForPath @getPathTo node

  # Return the rendered value of a part of the dom.
  # If path is not given, the default path is used.
  _getContentForPath: (path = null) =>
    path ?= @getDefaultPath()
    @path[path].content

  # Return the length of the rendered value of a part of the dom.
  # If path is not given, the default path is used.
  _getLengthForPath: (path = null) =>
    path ?= @getDefaultPath()
    @path[path].length

  # Get the matching DOM elements for a given charRange
  # 
  # If the "path" argument is supplied, scan is called automatically.
  # (Except if the supplied path is the same as the last scanned path.)
  _getMappingsForCharRange: (start, end) =>
    @_startScan "getMappingsForCharRange()"
    unless (start? and end?)
      throw new Error "start and end is required!"

#    @log "Collecting nodes for [" + start + ":" + end + "]"

    # Collect the matching path infos
    # @log "Collecting mappings"
    mappings = []
    for p, info of @path when info.atomic and
        @_regions_overlap info.start, info.end, start, end
      do (info) =>
#        @log "Checking " + info.path
#        @log info
        mapping =
          element: info

        full = start <= info.start and info.end <= end
        if full
          mapping.full = true
          mapping.wanted = info.content
          mapping.yields = info.content
          mapping.startCorrected = 0
          mapping.endCorrected = 0
        else
          if info.node.nodeType is Node.TEXT_NODE        
            if start <= info.start
              mapping.end = end - info.start
              mapping.wanted = info.content.substr 0, mapping.end
            else if info.end <= end
              mapping.start = start - info.start
              mapping.wanted = info.content.substr mapping.start        
            else
              mapping.start = start - info.start
              mapping.end = end - info.start
              mapping.wanted = info.content.substr mapping.start,
                  mapping.end - mapping.start

            @computeSourcePositions mapping
            mapping.yields = info.node.data.substr mapping.startCorrected,
                mapping.endCorrected - mapping.startCorrected
          else if (info.node.nodeType is Node.ELEMENT_NODE) and
              (info.node.tagName.toLowerCase() is "img")
            @log "Can not select a sub-string from the title of an image.
 Selecting all."
            mapping.full = true
            mapping.wanted = info.content
          else
            @log "Warning: no idea how to handle partial mappings
 for node type " + info.node.nodeType
            if info.node.tagName? then @log "Tag: " + info.node.tagName
            @log "Selecting all."
            mapping.full = true
            mapping.wanted = info.content

        mappings.push mapping
#        @log "Done with " + info.path

    if mappings.length is 0
      @log "Collecting nodes for [" + start + ":" + end + "]"
      @log "Should be: '" + @_corpus[ start ... end ] + "'."
      throw new Error "No mappings found for [" + start + ":" + end + "]!"

    mappings = mappings.sort (a, b) -> a.element.start - b.element.start
        
    # Create a DOM range object
#    @log "Building range..."
    r = @rootWin.document.createRange()
    startMapping = mappings[0]
    startNode = startMapping.element.node
    startPath = startMapping.element.path
    startOffset = startMapping.startCorrected
    if startMapping.full
      r.setStartBefore startNode
      startInfo = startPath
    else
      r.setStart startNode, startOffset
      startInfo = startPath + ":" + startOffset

    endMapping = mappings[mappings.length - 1]
    endNode = endMapping.element.node
    endPath = endMapping.element.path
    endOffset = endMapping.endCorrected
    if endMapping.full
      r.setEndAfter endNode
      endInfo = endPath
    else
      r.setEnd endNode, endOffset
      endInfo = endPath + ":" + endOffset

    result = {
      mappings: mappings
      realRange: r
      rangeInfo:
        startPath: startPath
        startOffset: startOffset
        startInfo: startInfo
        endPath: endPath
        endOffset: endOffset
        endInfo: endInfo
      safeParent: r.commonAncestorContainer
    }

    # Return the result
    sections: [result]

  # Call this fnction to wait for any pending operations
  ready: (reason, callback) ->
    unless callback?
      throw new Error "missing callback!"
    @_pendingCallbacks ?= []
    @_pendingCallbacks.push callback
    @_startScan reason
    null

  # ===== Private methods (never call from outside the module) =======

  stringStartsWith: (string, prefix) ->
    unless prefix
      throw Error "Requires a non-empty prefix!"
    string[ 0 ... prefix.length ] is prefix

  stringEndsWith: (string, suffix) ->
    unless suffix
      throw Error "Requires a non-empty suffix!"
    string[ string.length - suffix.length ... string.length ] is suffix

  _parentPath: (path) -> path.substr 0, path.lastIndexOf "/"

  getProperNodeName: (node) ->
    nodeName = node.nodeName
    switch nodeName
      when "#text" then return "text()"
      when "#comment" then return "comment()"
      when "#cdata-section" then return "cdata-section()"
      else return nodeName

  # Gets a list of children of the given node, together with their paths.
  _enumerateChildren: (node, path) ->
    return [] unless node.hasChildNodes()
    results = []
    children = node.childNodes
    i = 0
    typeCount = Object()

    while i < children.length # Go over allt he children
      child = children[i]
      nodeName = @getProperNodeName child

      # Count how many of this type do we have, including this one
      oldCount = typeCount[nodeName]
      newCount = if oldCount? then oldCount + 1 else 1
      typeCount[nodeName] = newCount

      # Come up with an XPath
      childPath = path + "/" + nodeName + (if newCount > 1
        "[" + newCount + "]"
      else
        ""
      )
      results.push
        node: child
        path: childPath
      i++

    results

  # Find the first predecessor of a given node, which is not a mystery node
  _findRelevantPredecessor: (successor, parentPath) ->
    node = successor.previousSibling
    while node
      path = parentPath + "/" + @getPathSegment node
      info = @path[path]
      if info.mystery or info.irrelevant
        node = node.previousSibling
      else
        return info
    return null

  getNodePosition: (node) ->
    pos = 0
    tmp = node
    while tmp
      if tmp.nodeName is node.nodeName
        pos++
      tmp = tmp.previousSibling
    pos

  getPathSegment: (node) ->
    name = @getProperNodeName node
    pos = @getNodePosition node
    name + (if pos > 1 then "[#{pos}]" else "")

  getPathTo: (node) ->
    unless origNode = node
      throw new Error "Called getPathTo with null node!"
    xpath = '';
    while node != @rootNode
      unless node?
        @log "Root node:", @rootNode
        @log "Wanted node:", origNode
        @log "Is this even a child?", @rootNode.contains origNode
        throw new Error "Called getPathTo on a node which was not a descendant of the configured root node."
      xpath = (@getPathSegment node) + '/' + xpath
      node = node.parentNode
    xpath = (if @rootNode.ownerDocument? then './' else '/') + xpath
    xpath = xpath.replace /\/$/, ''
    xpath

  # This method is called recursively, to traverse a given sub-tree of the DOM.
  traverseSubTree: (node, path, invisible = false, verbose = false) ->

    debug = false #path in ["./DIV", "./DIV/DIV"]
    if debug
      @log "Traversing path", path

    # Should this node be ignored?
    return if @_isIgnored node

    # Step one: get rendered node content, and store path info,
    # if there is valuable content
    @underTraverse = path
    cont = @getNodeContent node, false
    @path[path] =
      path: path
      content: cont
      length: cont.length
      node : node
    if cont.length
      if verbose then @log "Collected info about path " + path
      if invisible
        @log "Something seems to be wrong. I see visible content @ " +
            path + ", while some of the ancestor nodes reported empty contents.
 Probably a new selection API bug...."
        @log "Anyway, text is '" + cont + "'."        
    else
      if verbose then @log "Found no content at path " + path
      invisible = true

    # Step two: cover all children.
    # Q: should we check children even if
    # the given node had no rendered content?
    # A: I seem to remember that the answer is yes, but I don't remember why.
    for item in @_enumerateChildren node, path
      @traverseSubTree item.node, item.path, invisible, verbose
    null

  getBody: -> (@rootWin.document.getElementsByTagName "body")[0]

  _regions_overlap: (start1, end1, start2, end2) ->
      start1 < end2 and start2 < end1

  lookUpNode: (path) ->
    doc = @rootNode.ownerDocument ? @rootNode
    results = doc.evaluate path, @rootNode, null, 0, null
    node = results.iterateNext()

  # save the original selection
  saveSelection: ->
    if @savedSelection?
      @log "Selection saved at:"
      @log @selectionSaved
      throw new Error "Selection already saved!"
    sel = @rootWin.getSelection()        
#    @log "Saving selection: " + sel.rangeCount + " ranges."

    @savedSelection = ((sel.getRangeAt i) for i in [0 ... sel.rangeCount])

    @selectionSaved = (new Error "selection was saved here").stack

  # restore selection
  restoreSelection: ->
#    @log "Restoring selection: " + @savedSelection.length + " ranges."
    unless @savedSelection? then throw new Error "No selection to restore."
    sel = @rootWin.getSelection()
    sel.removeAllRanges()
    sel.addRange range for range in @savedSelection
    delete @savedSelection

  # Select the given node (for visual identification),
  # and optionally scroll to it
  selectNode: (node, scroll = false) ->
    unless node?
      throw new Error "Called selectNode with null node!"
    sel = @rootWin.getSelection()

    # clear the selection
    sel.removeAllRanges()

    # create our range, and select it
    realRange = @rootWin.document.createRange()

    # There is some weird, bogus behaviour in Chrome,
    # triggered by whitespaces between the table tag and it's children.
    # See the select-tbody and the select-the-parent-when-selecting problems
    # described here:
    #    https://github.com/hypothesis/h/issues/280
    # And the WebKit bug report here:
    #    https://bugs.webkit.org/show_bug.cgi?id=110595
    # 
    # To work around this, when told to select specific nodes, we have to
    # do various other things. See bellow.

    if node.nodeType is Node.ELEMENT_NODE and node.hasChildNodes() and
        node.tagName.toLowerCase() in SELECT_CHILDREN_INSTEAD
      # This is an element where direct selection sometimes fails,
      # because if the WebKit bug.
      # (Sometimes it selects nothing, sometimes it selects something wrong.)
      # So we select directly the children instead.
      children = node.childNodes
      realRange.setStartBefore children[0]
      realRange.setEndAfter children[children.length - 1]
      sel.addRange realRange
    else
      if USE_TABLE_TEXT_WORKAROUND and node.nodeType is Node.TEXT_NODE and
          node.parentNode.tagName.toLowerCase() is "table"
        # This is a text element that should not even be here.
        # Selecting it might select the whole table,
        # so we don't select anything
      else
        # Normal element, should be selected
        try
          realRange.setStartBefore node
          realRange.setEndAfter node
          sel.addRange realRange
        catch exception
          # This might be caused by the fact that FF can't select a
          # TextNode containing only whitespace.
          # If this is the case, then it's OK.
          unless USE_EMPTY_TEXT_WORKAROUND and @isWhitespace node
            # No, this is not the case. Then this is an error.
            @log "Warning: failed to scan element @ " + @underTraverse
            @log "Content is: " + node.innerHTML
            @log "We won't be able to properly anchor to any text inside this element."
#            throw exception
    if scroll
      sn = node
      while sn? and not sn.scrollIntoViewIfNeeded?
        sn = sn.parentNode
      if sn?
        sn.scrollIntoViewIfNeeded()
      else
        @log "Failed to scroll to element. (Browser does not support scrollIntoViewIfNeeded?)"
    sel

  # Read and convert the text of the current selection.
  readSelectionText: (sel) ->
    sel or= @rootWin.getSelection()
    sel.toString().trim().replace(/\n/g, " ").replace /\s{2,}/g, " "

  # Read the "text content" of a sub-tree of the DOM by
  # creating a selection from it
  getNodeSelectionText: (node, shouldRestoreSelection = true) ->
    if shouldRestoreSelection then @saveSelection()

    sel = @selectNode node
    text = @readSelectionText sel

    if shouldRestoreSelection then @restoreSelection()
    text


  # Convert "display" text indices to "source" text indices.
  computeSourcePositions: (match) ->
    @log "In computeSourcePosition",
      match.element.path,
      match.element.node.data

    # the HTML source of the text inside a text element.
    @log "Calculating source position at " + match.element.path
    sourceText = match.element.node.data.replace /\n/g, " "
    @log "sourceText is '" + sourceText + "'"

    # what gets displayed, when the node is processed by the browser.
    displayText = match.element.content
    @log "displayText is '" + displayText + "'"

    if displayText.length > sourceText.length
      throw new Error "Invalid match at" + match.element.path + ": sourceText is '" + sourceText + "'," +
        " displayText is '" + displayText + "'."

    # The selected charRange in displayText.
    displayStart = if match.start? then match.start else 0
    displayEnd = if match.end? then match.end else displayText.length
    @log "Display charRange is: " + displayStart + "-" + displayEnd

    if displayEnd is 0
      # Handle empty text nodes  
      match.startCorrected = 0
      match.endCorrected = 0
      @log "This is empty. Returning"
      return

    sourceIndex = 0
    displayIndex = 0

    until sourceStart? and sourceEnd?
      sc = sourceText[sourceIndex]
      dc = displayText[displayIndex]
      if sc is dc
        if displayIndex is displayStart
          sourceStart = sourceIndex
        displayIndex++        
        if displayIndex is displayEnd
          sourceEnd = sourceIndex + 1

      sourceIndex++
    match.startCorrected = sourceStart
    match.endCorrected = sourceEnd
    @log "computeSourcePosition done. Corrected charRange is: ",
      match.startCorrected + "-" + match.endCorrected
    null

  # Internal function used to read out the text content of a given node,
  # as render by the browser.
  # The current implementation uses the browser selection API to do so.
  getNodeContent: (node, shouldRestoreSelection = true) ->
    if (node is @pathStartNode) and @expectedContent?
#      @log "Returning fake expectedContent for getNodeContent"
      return @expectedContent
    content = @getNodeSelectionText node, shouldRestoreSelection
    if (node is @pathStartNode) and @_ignorePos?
      #@log "getNodeContent for root: cutting stream @", @_ignorePos, ".",
      #  "(Total length is", content.length, "."
      return content[ 0 ... @_ignorePos ]

    content


  # Marking a node as irrelevent means that we have determined
  # that this node does not contribute to the corpus at all.
  _markNodeAsIrrelevant: (node, path, verbose) ->
    if verbose
       @log "Marking node at path", path, "as irrelevant."
    @path[path].irrelevant = true

    for item in @_enumerateChildren node, path, verbose
      @_markNodeAsIrrelevant item.node, item.path, verbose

  # Marking a node as mystery means that we have determined
  # that this node has some content, but it does not seem to be part
  # of the corpus of it's parent. How is this possible is still
  # a mistery. Our current guess is that these nodes are always
  # invisible, so they should not really have any "user visible"
  # content, so this is just a fluke of the selection API implementations.
  _markNodeAsMystery: (node, path, verbose) ->
    if verbose
       @log "Marking node at path", path, "as mystery."
    @path[path].mystery = true

    for item in @_enumerateChildren node, path, verbose
      @_markNodeAsMystery item.node, item.path, verbose

  # Internal function to collect mapping data from a given DOM element.
  # 
  # Input parameters:
  #    node: the node to scan
  #    path: the path to the node (relative to rootNode
  #    parentContent: the content of the node's parent node
  #           (as rendered by the browser)
  #           This is used to determine whether the given node is rendered
  #           at all.
  #           If not given, it will be assumed that it is rendered
  #    parentIndex: the starting character offset
  #           of content of this node's parent node in the rendered content
  #    index: ths first character offset position in the content of this
  #           node's parent node
  #           where the content of this node might start
  #
  # Returns:
  #    the first character offset position in the content of this node's
  #    parent node that is not accounted for by this node
  collectPositions: (node, path, parentContent = null, parentIndex = 0, index = 0) ->
    if isNaN parentIndex
      throw new Error "Internal error: got a NaN"
    debug = false # path in ["./DIV", "./DIV/DIV"]
    if debug
      @log "Post-processing path ", path

    # Should this node be ignored?
    if @_isIgnored node, false, debug
      if debug
        @log "This is ignored!"  
      pos = parentIndex + index  # Where were we?
      unless @_ignorePos? and @_ignorePos < pos # Have we seen better ?
        @_ignorePos = pos
      return index

    pathInfo = @path[path]
    content = pathInfo?.content

    unless content
      # node has no content, not interesting
      pathInfo.start = parentIndex + index
      pathInfo.end = parentIndex + index
      if isNaN pathInfo.end
        throw new Error "Internal error: got a NaN"
      pathInfo.atomic = false
      if debug
        @log "Path", path, "is empty; setting it to atomic."
      @_markNodeAsIrrelevant node, path, debug
      return index

    startIndex = if parentContent?
      parentContent.indexOf content, index
    else
      index
    if startIndex is -1
      # content of node is not present in parent's content - probably hidden,
      # or something similar
#      @log "Content of", path, "is not present in content of it's parent",
#       "(Content: '" + content + "'.)"
      @_markNodeAsMystery node, path, debug
      return index


    endIndex = startIndex + content.length
    atomic = not node.hasChildNodes()
    pathInfo.start = parentIndex + startIndex
    pathInfo.end = parentIndex + endIndex
    if isNaN pathInfo.end
      throw new Error "Internal error: got a NaN"
    pathInfo.atomic = atomic

    if debug
      @log "Is", path, "atomic?", atomic

    if not atomic # If this node has children,
      for item in @_enumerateChildren node, path # Take the children
        pos = @collectPositions item.node, item.path, content, # and repeat
          parentIndex + startIndex, pos

    endIndex

  WHITESPACE = /^\s*$/

  # Decides whether a given node is a text node that only contains whitespace
  isWhitespace: (node) ->
    result = switch node.nodeType
      when Node.TEXT_NODE
        WHITESPACE.test node.data
      when Node.ELEMENT_NODE
        mightBeEmpty = true
        for child in node.childNodes
          mightBeEmpty = mightBeEmpty and @isWhitespace child
        mightBeEmpty
      else false
    result

  # Internal debug method to verify the consistency of mapping info of a node
  _testNodeMapping: (path, info, verbose = false) ->

    # If the info was not passed in, look it up
    info ?= @path[path]

    # Do we have it?
    unless info
      console.trace()
      throw new Error "Could not look up node @ '" + path + "'!"

    # Don't bother with weird nodes
    return true if info.mystery

    # Get the range from corpus
    inCorpus = if (info.start? and info.end?)
      @_corpus[ info.start ... info.end ]
    else
      ""

    # Get the actual node content
    realContent = @getNodeContent info.node

    # Compare stored content with the data in corpus
    ok1 = info.content is inCorpus

    # Compare stored content with actual content
    ok2 = info.content is realContent

    if verbose and not (ok1 and ok2)
      @dmp ?= new DTM_DMPMatcher()        
      ok3 = inCorpus is realContent

      if ok1
        @log "X=*=*=X Stored and corpus content matches at", path
      else  
        diff = @dmp.compare info.content, inCorpus
        @log "X=*=*=X Mismatch between stored content and corpus[",
          info.start, "...", info.end, "] at", path,  diff.diff

      if ok2
        @log "X=*=*=X Stored and actual content matches at", path
      else
        diff = @dmp.compare info.content, realContent
        @log "X=*=*=X Mismatch between stored and actual content at", path,
          diff.diff

      if ok3
        @log "X=*=*=X Corpus and actual content matches at", path,        
      else  
        diff = @dmp.compare inCorpus, realContent
        @log "X=*=*=X Mismatch between corpus[", info.start, "...", info.end,
          "] and actual content at", path, diff.diff
        
    ok1 and ok2

  # Internal debug method to verify the consistency of all mapping info
  _testAllMappings: (verbose = false)->
    @log "Verifying map info: was it all properly traversed & post-processed?"
    correct = true
    for i, p of @path
      unless p.irrelevant or p.mystery or p.atomic?
        if verbose or correct
          @log i, "is missing data."
        correct = false

    return false unless correct

    @log "Verifying map info: do nodes match?"
    for path, info of @path
      unless @_testNodeMapping path, info, verbose
        if correct and not verbose
          @_testNodeMapping path, info, true
        correct = false

    return correct


  # Fake two-phase / pagination support, used for HTML documents
  getPageIndex: -> 0
  getPageCount: -> 1
  getPageRoot: -> @rootNode
  _getPageIndexForPos: -> 0
  isPageMapped: -> true

  # Change tracking ===================

  # Get the list of nodes that should be totally ignored
  _getIgnoredParts: ->
   # Do we have to ignore some parts?
    if @options.getIgnoredParts # Yes, some parts should be ignored.
      # Do we already have them, and are we allowed to cache?
      if @_ignoredParts and @options.cacheIgnoredParts # Yes, in cache
        @_ignoredParts
      else # No cache (yet?). Get a new list!
        @_ignoredParts = @options.getIgnoredParts()
    else # Not ignoring anything; facing reality as it is
      []

  # Irrelevant nodes are nodes that are guaranteed not to content any valid
  # text. Usually, we don't need to care about them.
  _isIrrelevant: (node) ->
    node.nodeType is Node.ELEMENT_NODE and
      node.tagName.toLowerCase() in ["canvas", "script"]

  # Determines whether a node should be ignored
  # This can be caused by either being part of a sub-tree which is ignored,
  # or being irrelevant by nature, if this option is allowed.
  _isIgnored: (node, ignoreIrrelevant = false, debug = false) ->
    # Don't bother with totally removed nodes
    unless @pathStartNode.contains node
      if debug
        @log "Node", node, "is ignored, because it's not a descendant of",
          @pathStartNode, "."
      return true

    for container in @_getIgnoredParts()
      if container.contains node
        if debug
          @log "Node", node, "is ignore, because it's a descendant of",
            containter
        return true

    # Should we ignore irrelevant nodes here?
    if ignoreIrrelevant
      if @_isIrrelevant node
        if debug
          @log "Node", node, "is ignored, because it's irrelevant."
        return true

    # OK, we have found no excuse to ignore this node.
    if debug
      @log "Node", node, "is NOT ignored."
    false


  # Determine whether an attribute change has to be taken seriously
  _isAttributeChangeImportant: (node, attributeName, oldValue, newValue) ->
    # Do we have an attribute change filter configured?
    if @options.filterAttributeChanges
      # Use the filter to decide whether this change is important
      @options.filterAttributeChanges node, attributeName, oldValue, newValue
    else
      # No filter, so we assume it's important
      true

  # Filter a change list
  _filterChanges: (changes) ->

    # If the list of parts to ignore is empty, don't filter
    return changes if @_getIgnoredParts().length is 0

    # OK, start filtering.

    # Go through added elements
    changes.added = changes.added.filter (element) =>
      not @_isIgnored(element, true)

    # Go through removed elements
    removed = changes.removed
    changes.removed = removed.filter (element) =>
      # Get the first non-removed parent
      parent = element
      while parent in removed
        parent = changes.getOldParentNode parent
#      pInDoc = @pathStartNode.contains parent
#      unless pInDoc
#        @log "First non-removed parent is", parent, ". In doc?", pInDoc
      not @_isIgnored(element, true)

    # Go through attributeChanged elements
    attributeChanged = {}
    for attrName, elementList of changes.attributeChanged ? {}
      # Filter out the ignored elements
      list = elementList.filter (element) => not @_isIgnored(element, true)

      # Filter out the ignored attribute changes
      list = list.filter (element) =>
        @_isAttributeChangeImportant element, attrName,
          changes.getOldAttribute(element, attrName),
          element.getAttribute(attrName)

      if list.length
        attributeChanged[attrName] = list
    changes.attributeChanged = attributeChanged

    # Go through the characterDataChanged elements
    changes.characterDataChanged =
      changes.characterDataChanged.filter (element) =>
        not @_isIgnored(element, true)

    # Go through the reordered elements
    changes.reordered = changes.reordered.filter (element) =>
      parent = element.parentNode
      not @_isIgnored(parent, true)

    # Go through the reparented elements
    # TODO

    attributeChangedCount = 0
    for k, v of changes.attributeChanged
      attributeChangedCount++
    if changes.added.length or
        changes.characterDataChanged.length or
        changes.removed.length or
        changes.reordered.length or
        changes.reparented.length or
        attributeChangedCount
      return changes
    else
      return null

    changes

  _addToTrees: (trees, node, reason, data...) ->
    unless @pathStartNode.contains node
#      @log "Not adding node", node,
#        "to change collection, since it seems to have been removed."
      return null
    trees.add node
    if node is @pathStartNode
      @log "Added change on root node, because", reason, data...
#    else
#      @log "Added node", node, "because", reason, data...

  # Callect all nodes involved in any of the passed changes
  _getInvolvedNodes: (changes) ->
    trees = new SubTreeCollection()

    # Collect the parents of the added nodes
    for n in changes.added
      @_addToTrees trees, n.parentNode, "a child was added", n

    # Collect attribute changed nodes
    for k, list of changes.attributeChanged
      for n in list
        @_addToTrees trees, n, "attribute changed", k

    # Collect character data changed nodes
#    trees.add n for n in changes.characterDataChanged
    for n in changes.characterDataChanged
      @_addToTrees trees, n, "data content changed"

    # Collect the non-removed parents of removed nodes
    for n in changes.removed
      parent = n
      while (parent in changes.removed) or (parent in changes.reparented)
        parent = changes.getOldParentNode parent
      @_addToTrees trees, n, "a child was removed"

    # Collect the parents of reordered nodes
#    trees.add n.parentNode for n in changes.reordered
    for n in changes.reordered
      @_addToTrees trees, n.parentNode, "children were reordered"

    # Collect the parents of reparented nodes
    for n in changes.reparented
      # Get the current parent
      @_addToTrees trees, n.parentNode, "reparented node landed here"

      # Get the old parent
      parent = n
      while (parent in changes.removed) or (parent in changes.reparented)
        parent = changes.getOldParentNode parent
      @_addToTrees trees, parent, "child was reparented from here"

    return trees.roots


  # React to the pasted list of changes
  _reactToChanges: (reason, changes, data) ->
    if changes
      changes = @_filterChanges changes # Filter the received changes
    unless changes # Did anything remain ?
#      unless reason is "Observer called"
#      @log reason, ", but no (real) changes detected"
      return

    # Actually react to the changes
    #@log reason, changes

#    @log "=== Collecting changes. ==="

    # Collect the changed sub-trees
    changedNodes = @_getInvolvedNodes changes

    corpusChanged = false

    # Go over the changed parts
    for node in changedNodes
      # Perform an incremental update on them
      if @_performUpdateOnNode node, reason, false, data
        # If this change involved a root change, set the flag
        corpusChanged = true
#        @log "Setting the corpus changed flag on changes @", node

#      p = @getPathTo node
#      @log "Testing node mapping @", p, ":", @_testNodeMapping p, null, true

#    @log "=== Finished reacting to changes. ==="

    # If there was a corpus change, announce it
    if corpusChanged then setTimeout =>
#      @log "CORPUS HAS CHANGED"
      event = document.createEvent "UIEvents"
      event.initUIEvent "corpusChange", true, false, window, 0
      @rootNode.dispatchEvent event

  # Bring the our data up to date
  _syncState: (reason = "i am in the mood", data) ->

#    @log "Syncing state, because", reason
#    t0 = @timestamp()

    # Get the changes from the observer
    summaries = @observer.takeSummaries()

#    if summaries # react to them
    @_reactToChanges "SyncState for " + reason, summaries?[0], data

#    t1 = @timestamp()
#    @log "State synced in", t1-t0, "ms."

  # Change handler, called when we receive a change notification
  _onChange: (event) =>
    @_syncState "change event '" + event.reason + "'", event.data


  # Callback for the mutation observer
  _onMutation: (summaries) =>
#    @log "DOM mutated!"
    @_reactToChanges "Observer called", summaries[0]


  # Change the root node, and subscribe to the events
  _changeRootNode: (node) ->
    @observer?.disconnect()
    @rootNode = node
    @observer = new MutationSummary
      callback: @_onMutation
      rootNode: node
      queries: [
        all: true
      ]
    node
