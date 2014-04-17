# This plugin contains the "Enhanced Anchoring Framework" for Annotator,
# originally developed by the Hypothes.is team.
#
# This plugin overrides the original anchoring framework of Annotator
# (which is not really a framework, only some hard-wired behavior),
# and provides a new framework, with several extension points
#
# Other plugins can then be used to plug into those extension points.

# Abstract highlight class
class Highlight

  constructor: (@anchor, @pageIndex) ->
    @annotator = @anchor.annotator
    @annotation = @anchor.annotation

  # Mark/unmark this hl as temporary (while creating an annotation)
  setTemporary: (value) ->
    throw "Operation not implemented."

  # Is this a temporary hl?
  isTemporary: ->
    throw "Operation not implemented."

  # TODO: review the usage of the batch parameters.

  # Mark/unmark this hl as active
  #
  # Value specifies whether it should be active or not
  #
  # The 'batch' field specifies whether this call is only one of
  # many subsequent calls, which should be executed together.
  #
  # In this case, a "finalizeHighlights" event will be published
  # when all the flags have been set, and the changes should be
  # executed.
  setActive: (value, batch = false) ->
    throw "Operation not implemented."

  # Mark/unmark this hl as focused
  #
  # Value specifies whether it should be focused or not
  #
  # The 'batch' field specifies whether this call is only one of
  # many subsequent calls, which should be executed together.
  #
  # In this case, a "finalizeHighlights" event will be published
  # when all the flags have been set, and the changes should be
  # executed.
  setFocused: (value, batch = false) ->
    throw "Operation not implemented."

  # React to changes in the underlying annotation
  annotationUpdated: ->
    #console.log "In HL", this, "annotation has been updated."

  # Remove all traces of this hl from the document
  removeFromDocument: ->
    throw "Operation not implemented."

  # Get the HTML elements making up the highlight
  # If you implement this, you get automatic implementation for the functions
  # below. However, if you need a more sophisticated control mechanism,
  # you are free to leave this unimplemented, and manually implement the
  # rest.
  _getDOMElements: ->
    throw "Operation not implemented."

  # Get the Y offset of the highlight. Override for more control
  getTop: -> $(@_getDOMElements()).offset().top

  # Get the height of the highlight. Override for more control
  getHeight: -> $(@_getDOMElements()).outerHeight true

  # Get the bottom Y offset of the highlight. Override for more control.
  getBottom: -> @getTop() + @getBottom()

  # Scroll the highlight into view. Override for more control
  scrollTo: -> $(@_getDOMElements()).scrollintoview()

  # Scroll the highlight into view, with a comfortable margin.
  # up should be true if we need to scroll up; false otherwise
  paddedScrollTo: (direction) ->
    unless direction? then throw "Direction is required"
    dir = if direction is "up" then -1 else +1
    where = $(@_getDOMElements())
    wrapper = @annotator.wrapper
    defaultView = wrapper[0].ownerDocument.defaultView
    pad = defaultView.innerHeight * .2
    where.scrollintoview
      complete: ->
        scrollable = if this.parentNode is this.ownerDocument
          $(this.ownerDocument.body)
        else
          $(this)
        top = scrollable.scrollTop()
        correction = pad * dir
        scrollable.stop().animate {scrollTop: top + correction}, 300

  # Scroll up to the highlight, with a comfortable margin.
  paddedScrollUpTo: -> @paddedScrollTo "up"

  # Scroll down to the highlight, with a comfortable margin.
  paddedScrollDownTo: -> @paddedScrollTo "down"



# Fake two-phase / pagination support, used for HTML documents
class DummyDocumentAccess

  constructor: (@rootNode) ->
  @applicable: -> true
  getPageIndex: -> 0
  getPageCount: -> 1
  getPageRoot: -> @rootNode
  getPageIndexForPos: -> 0
  isPageMapped: -> true
  prepare: () ->


# Enhanced Anchoring Manager

class EnhancedAnchoringManager

  constructor: (@annotator) ->
    console.log "Initializing Enhanced Anchoring Manager"

    # Create buckets for various groups of annotations
    @orphans = []      # Orphans
    @halfOrphans = []  # Half-orphans
    @anchors = {}      # Annotations anchored to a given page

    @_setupAnchorEvents()

    # Register the dummy document access strategy
    @registerDocumentAccessStrategy
      # Default dummy strategy for simple HTML documents.
      # The generic fallback.
      name: "Dummy"
      priority: 99
      applicable: -> true
      get: => new DummyDocumentAccess @annotator.wrapper[0]


    @removeFromSet = Annotator.Util.removeFromSet
    @addToSet = Annotator.Util.addToSet

    this

  _selectorCreators: []

  # Exported to Annotator: register a selector creator. See docs.
  registerSelectorCreator: (selectorCreator) =>
    @_selectorCreators.push selectorCreator

  _anchoringStrategies: []

  # Exported to Annotator: register an anchoring strategy. See docs.
  registerAnchoringStrategy: (strategy) =>
    strategy.priority ?= 50
    @_anchoringStrategies.push strategy
    @_anchoringStrategies.sort (s1, s2) -> s1.priority > s2.priority

  _documentAccessStrategies: []

  # Exported to Annotator: register a document access strategy. See docs.
  registerDocumentAccessStrategy: (strategy) =>
    strategy.priority ?= 50
    @_documentAccessStrategies.push strategy
    @_documentAccessStrategies.sort (s1, s2) -> s1.priority > s2.priority

  _highlighters: []

  # Exported to Annotator: register a highligher implementation. See docs.
  registerHighlighter: (highlighter) =>
    highlighter.priority ?= 50
    @_highlighters.push highlighter
    @_highlighters.sort (h1, h2) -> h1.priority > h2.priority

  # Sets up handlers to anchor-related events
  _setupAnchorEvents: =>
    # When annotations are updated
    @annotator.on 'annotationUpdated', (annotation) =>
      # Notify the highlights
      for anchor in annotation.anchors or []
        for index in [anchor.startPage .. anchor.endPage]
          anchor.highlight[index]?.annotationUpdated()


  # Initializes the components used for analyzing the document
  _chooseAccessPolicy: =>
    # We only have to do this once.
    return if @domMapper

    # Go over the available strategies
    for s in @_documentAccessStrategies
      # Can we use this strategy for this document?
      if s.applicable()
#        @documentAccessStrategy = s
        console.log "Selected document access strategy: " + s.name
        @domMapper = @annotator.domMapper = s.get()
        addEventListener "docPageMapped", (evt) =>
          @_realizePage evt.pageIndex
        addEventListener "docPageUnmapped", (evt) =>
          @_virtualizePage evt.pageIndex
        return this

  # Exported to Annotator: initialize anchoring system
  initAnchoring: =>
    @_chooseAccessPolicy()

  # Create a target from a raw selection,
  # using selectors created by the registered selector creators
  _getTargetFromSelection: (selection) =>
    dfd = Annotator.$.Deferred()

    selectors = []

    # Call all selector creators
    promises = (for c in @_selectorCreators
      try
        c.describe(selection).then (description) ->
          for selector in description
            selectors.push selector
      catch error
        console.log "Internal error while using selection descriptor",
          "'" + c.name + "':"
        console.log error.stack
    )

    # Wait for all the descriptors to finish
    Annotator.$.when(promises...).always =>
      if selectors.length
        # Create the target
        dfd.resolve
          source: @annotator.getHref()
          selector: selectors
      else
        dfd.reject "No selector creator could describe this selection."

    # Return the promise
    dfd.promise()

  # Creates a list of targets from a list of raw selections,
  # using selectors created by the registered selector creators
  _getTargetsFromSelections: (selections) =>
    dfd = Annotator.$.Deferred()

    # Prepare a dict to collect the targets for each selection
    targets = {}

    # Start the creation of the targets for each selection
    promises = (for selection in selections
      @_getTargetFromSelection(selection).then(((target) ->
        targets[selection] = target
      ), ((reason) ->
        console.log "Could not create target from selection", selection,
         ":", reason
      ))
    )

    # Wait for all the pieces to finish
    Annotator.$.when(promises...).always =>

      # Did some of the target creations fail?
      if "rejected" in (p.state() for p in promises)
        dfd.reject "Failed to create the targets"
      else
        # Resolve the promise with the target list
        dfd.resolve (targets[sel] for sel in selections)

    # Return the promise
    dfd.promise()

  # Find the given type of selector from an array of selectors, if it exists.
  # If it does not exist, null is returned.
  findSelector: (selectors, type) =>
    for selector in selectors
      if selector.type is type then return selector
    null


  # Recursive method to go over the passed list of strategies,
  # and create an anchor with the first one that succeeds.
  _createAnchorWithStrategies: (annotation, target, strategies, promise) =>

    # Do we have more strategies to try?
    unless strategies.length
      # No, it's game over
      promise.reject "no more strateges to try"
      return

    # Fetch the next strategy to try
    s = strategies.shift()

    # We will do this if this strategy failes
    onFail = (error, boring = false) =>
      unless boring and false then console.log "Anchoring strategy",
        "'" + s.name + "'", "has failed:", error

      @_createAnchorWithStrategies annotation, target, strategies, promise

    try
      # Get a promise from this strategy
      #console.log "Executing strategy '" + s.name + "'..."
      iteration = s.create target

      # Run this strategy
      iteration.then( (anchor) => # This strategy has worked.
        #console.log "Anchoring strategy '" + s.name + "' has succeeded:",
        #  anchor

        unless anchor.startPage? and anchor.endPage? and anchor.quote?
          console.log "Warning: starategy", "'" + s.name + "'",
            "has returned an anchor without the mandatory fields.",
            anchor
          onFail("internal error")

        # Note the name of the successful strategy
        anchor.strategy = s

        # Save some object references
        anchor.annotator = this
        anchor.annotation = annotation
        anchor.target = target

        # Prepare the map for the hlighlights
        anchor.highlight = {}

        # Write the results of the re-attaching back to the target
        target.quote = anchor.quote

        # Copy the diff HTML
        if anchor.diffHTML
          target.diffHTML = anchor.diffHTML
        else
          delete anchor.diffHTML

        # Copy diff case only flag
        if anchor.diffCaseOnly
          target.diffCaseOnly = anchor.diffCaseOnly
        delete
          anchor.diffCaseOnly

        # Store this anchor for the annotation
        annotation.anchors.push anchor

        # Update the annotation's anchor status

        # This annotation is no longer an orphan
        @removeFromSet annotation, @orphans

        # Does it have all the wanted anchors?
        if annotation.anchors.length is annotation.target.length
          # Great. Not a half-orphan either.
#          console.log "Created anchor. Annotation", @annotation.id,
#            "is now fully anchored."
          @removeFromSet annotation, @halfOrphans
        else
         # No, some anchors are still missing. A half-orphan, then.
#         console.log "Created anchor. Annotation", @annotation.id,
#           "is now a half-orphan."
          @addToSet annotation, @halfOrphans

        # Store the anchor for all involved pages
        for pageIndex in [anchor.startPage .. anchor.endPage]
          @anchors[pageIndex] ?= []
          @anchors[pageIndex].push anchor

        # We can now resolve the promise
        promise.resolve anchor

      ).fail onFail
    catch error
      # The strategy has thrown an error!
      console.log "While trying anchoring strategy",
        "'" + s.name + "':",
      console.log error.stack
      onFail "see exception above"

    null

  # Try to find the right anchoring point for a given target
  #
  # Returns a promise, which will be resolved with an Anchor object
  _createAnchor: (annotation, target) =>
    unless target?
      throw new Error "Trying to find anchor for null target!"
    #console.log "Trying to find anchor for target: ", target

    # Create a Deferred object
    dfd = Annotator.$.Deferred()

    # Start to go over all the strategies
    @_createAnchorWithStrategies annotation, target,
      @_anchoringStrategies.slice(), dfd

    # Return the promise
    dfd.promise()

  # Create the missing highlights for this anchor, for the given page
  _realizeAnchor: (anchor, page) =>
    return if anchor.fullyRealized # If we have everything, go home

    # Collect the pages that are already rendered
    renderedPages = [anchor.startPage .. anchor.endPage].filter (index) =>
      @domMapper.isPageMapped index

    # Collect the pages that are already rendered, but not yet anchored
    pagesTodo = renderedPages.filter (index) -> not anchor.highlight[index]?

    return unless pagesTodo.length # Return if nothing to do

    try
      created = []
      promises = []

      # Create the new highlights
      for page in pagesTodo
        promises.push p = @_createHighlight anchor, page  # Get a promise
        p.then (hl) => created.push anchor.highlight[page] = hl
        p.fail (e) =>
          console.log "Error while trying to create highlight:", e

      # Wait for all attempts for finish/fail
      Annotator.$.when(promises...).always =>
        # Finished creating the highlights

        # Check if everything is rendered now
        anchor.fullyRealized =
          (renderedPages.length is anchor.endPage - anchor.startPage + 1) and # all rendered
          (created.length is pagesTodo.length) # all hilited

        # Announce the creation of the highlights
        if created.length
          @annotator.publish 'highlightsCreated', created

    catch error
      console.log "Internal error:"
      console.log error.stack

    null

  # Remove the highlights for this anchor from the given set of pages
  _virtualizeAnchor: (anchor, pageIndex) =>
    highlight = anchor.highlight[pageIndex]

    return unless highlight? # No highlight for this page

    try
      highlight.removeFromDocument()
    catch error
      console.log "Could not remove HL from page", pageIndex, ":", error.stack

    delete anchor.highlight[pageIndex]

    # Mark this anchor as not fully rendered
    anchor.fullyRealized = false

    # Announce the removal of the highlight
    @annotator.publish 'highlightRemoved', highlight

    null

  # Check if this anchor is still valid. If not, remove it.
  _verifyAnchor: (anchor, reason, data) =>
    # Create a Deferred object
    dfd = Annotator.$.Deferred()

    # Do we have a way to verify this anchor?
    if anchor.strategy.verify # We have a verify function to call.
      try
        anchor.strategy.verify(anchor, reason, data).then (valid) =>
          #console.log "Is", anchor.annotation.id, "still valid?", valid
          @_removeAnchor anchor unless valid        # Remove the anchor
          dfd.resolve()                 # Mark this as resolved
      catch error
        # The verify method crashed. How lame.
        console.log "Error while executing anchor's verify method:", error.stack
        @_removeAnchor anchor     # Remove the anchor
        dfd.resolve()     # Mark this as resolved
    else # No verify method specified
      console.log "Can't verify this anchor, because the",
        "'" + anchor.strategy.name + "'",
        "strategy (which was responsible for creating this anchor)"
        "did not specify a verify function."
      @_removeAnchor anchor    # Remove the anchor
      dfd.resolve()     # Mark this as resolved

    # Return the promise
    dfd.promise()

  # Virtualize and remove an anchor from all involved pages and the annotation
  _removeAnchor: (anchor) =>
    # Go over all the pages
    for index in [anchor.startPage .. anchor.endPage]
      @_virtualizeAnchor anchor, index
      anchors = @anchors[index]
      # Remove the anchor from the list
      @removeFromSet anchor, anchors
      # Kill the list if it's empty
      delete @anchors[index] unless anchors.length

    annotation = anchor.annotation

    # Remove the anchor from the list
    @removeFromSet anchor, annotation.anchors

    # Are there any anchors remaining?
    if annotation.anchors.length
      # This annotation is a half-orphan now
#      console.log "Removed anchor, annotation", annotation.id,
#        "is a half-orphan now."
      @addToSet annotation, @halfOrphans
    else
      # This annotation is an orphan now
#      console.log "Removed anchor, annotation", annotation.id,
#        "is an orphan now."
      @addToSet annotation, @orphans
      @removeFromSet annotation, @halfOrphans


  # Find the anchor belonging to a given target
  _findAnchorForTarget: (annotation, target) =>
    for anchor in annotation.anchors when anchor.target is target
      return anchor
    return null

  # Decides whether or not a given target is anchored
  _hasAnchorForTarget: (annotation, target) =>
    anchor = @_findAnchorForTarget annotation, target
    anchor?

  # Tries to create any missing anchors for the given annotation
  # Optionally accepts a filter to test targetswith
  _anchorAnnotation: (annotation, targetFilter, publishEvent = false) =>

    # Supply a dummy target filter, if needed
    targetFilter ?= (target) -> true

    # Build a filter to test targets with.
    shouldDo = (target) =>
      hasAnchor = @_hasAnchorForTarget annotation, target
      result = (not hasAnchor) and  # has no ancher
        (targetFilter target)       # Passes the optional filter
      # console.log "Should I anchor target", target, "?", result
      result

    annotation.quote = (t.quote for t in annotation.target)
    annotation.anchors ?= []

    # Collect promises for all the involved targets
    promises = for t in annotation.target when shouldDo t

      index = annotation.target.indexOf t

      # Create an anchor for this target
      @_createAnchor(annotation, t).then (anchor) =>
        # We have an anchor
        annotation.quote[index] = t.quote

        # Realizing the anchor
        @_realizeAnchor anchor

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    Annotator.$.when(promises...).always =>

      # Join all the quotes into one string.
      annotation.quote = annotation.quote.filter((q)->q?).join ' / '

      # Did we actually manage to anchor anything?
      if "resolved" in (p.state() for p in promises)

        if @_changedAnnotations? # Are we collecting anchoring changes?
          @_changedAnnotations.push annotation  # Add this annotation

        if publishEvent  # Are we supposed to publish an event?
          @annotator.publish "annotationsLoaded", [[annotation]]

      # We are done!
      dfd.resolve annotation

    # Return a promise
    dfd.promise()

  # Tries to create any missing anchors for all annotations
  _anchorAllAnnotations: (targetFilter) =>
    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    # We have to consider the orphans and half-orphans, since they are
    # the onees with missing annotations
    annotations = @halfOrphans.concat @orphans

    # Initiate the collection of changes
    @_changedAnnotations = []

    # Get promises for anchoring all annotations
    promises = for annotation in annotations
      @_anchorAnnotation annotation, targetFilter

    # Wait for all attempts for finish/fail
    Annotator.$.when(promises...).always =>

      # send out notifications and updates
      if @_changedAnnotations.length
        @annotator.publish "annotationsLoaded", [@_changedAnnotations]
      delete @_changedAnnotations

      # When all is said and done
      dfd.resolve()

    # Return a promise
    dfd.promise()

  # Recursive method to go over the passed list of highlighters
  # and create a highlight with the first one that succeeds.
  _createHighlightUsingHighlighters: (anchor, page, highlighters, promise) =>

    # Do we have more highlighters to try?
    unless highlighters.length
      # No, it's game over
      promise.reject "No highlighter that could handle anchor type" +anchor.type
      return

    # Fetch the next higlighter to try
    h = highlighters.shift()

    # We will do this if this strategy failes
    onFail = (error, boring = false) =>
      unless boring then console.log "Highlighter",
        "'" + s.name + "'",
        "has failed:",
        error

      @_createHighlightUsingHighlighters anchor, page, highlighters, promise

    try
      # Get a promise from this highlighter
      #console.log "Trying highlighter '" + h.name + "'..."
      iteration = h.highlight anchor, page

      # Run this strategy
      iteration.then( (highlight) => # This strategy has worked.
        #console.log "Highlighter '" + h.name + "' has succeeded:",
        #  highlight

        # We can now resolve the promise
        promise.resolve highlight

      ).fail onFail
    catch error
      # The highlighter has thrown an error!
      console.log "While trying highlighter",
        "'" + h.name + "':",
      console.log error.stack
      onFail "see exception above"

    null


  # Create a highlight for an anchor, using one of the registered
  # highlighting implementations.
  _createHighlight: (anchor, page) =>
    # Prepare the deferred object
    dfd = Annotator.$.Deferred()

    # Start to go over all the highlighters
    @_createHighlightUsingHighlighters anchor, page,
      @_highlighters.slice(), dfd

    # Return the promise
    return dfd.promise()

  # Collect all the highlights (optionally for a given set of annotations)
  getHighlights: (annotations) =>
    results = []
    if annotations?
      # Collect only the given set of annotations
      for annotation in annotations
        for anchor in annotation.anchors
          for page, hl of anchor.highlight
            results.push hl
    else
      # Collect from everywhere
      for page, anchors of @anchors
        $.merge results, (anchor.highlight[page] for anchor in anchors when anchor.highlight[page]?)
    results

  # Realize anchors on a given pages
  _realizePage: (index) =>
    # If the page is not mapped, give up
    return unless @domMapper.isPageMapped index

    # Go over all anchors related to this page
    for anchor in @anchors[index] ? []
      @_realizeAnchor anchor

    null

  # Virtualize anchors on a given page
  _virtualizePage: (index) =>
    # Go over all anchors related to this page
    for anchor in @anchors[index] ? []
      @_virtualizeAnchor anchor, index

    null

  # Tell all anchors to verify themselves
  _verifyAllAnchors: (reason = "no reason in particular", data = null) =>
#    console.log "Verifying all anchors, because of", reason, data

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    promises = [] # Let's collect promises from all anchors

    for page, anchors of @anchors     # Go over all the pages
      for anchor in anchors.slice()   # and all the anchors
        promises.push @_verifyAnchor anchor, reason, data # verify them

    # Wait for all attempts for finish/fail
    Annotator.$.when(promises...).always -> dfd.resolve()

    # Return a promise
    dfd.promise()

  # Re-anchor all the annotations
  _reanchorAllAnnotations: (reason = "no reason in particular",
      data = null, targetFilter = null
  ) =>

    # The deferred object we will use for timing
    dfd = Annotator.$.Deferred()

    @_verifyAllAnchors(reason, data)     # Verify all anchors
    .then => @_anchorAllAnnotations(targetFilter) # re-create anchors
    .then -> dfd.resolve()   # we are done

    # Return a promise
    dfd.promise()


  # This method is to be called by the mechanisms responsible for
  # triggering annotation (and highlight) creation.
  #
  # event - any event which has triggered this.
  #         The following fields are used:
  #   targets: an array of targets, which should be used to anchor the
  #            newly created annotation
  #   pageX and pageY: if the adder button is shown, use there coordinates
  #
  # immadiate - should we show the adder button, or should be proceed
  #             to create the annotation/highlight immediately ?
  #
  # returns a promise, which will be resolved with the creation of the
  # annotation can proceed, or will be rejected if the creation of
  # annotations is forbidden at the moment, or there is some other problem.
  # In this case, the calling code must clear up any constructs built around
  # the selection.
  onSuccessfulSelection: (event, immediate = false) =>
    # Prepare the deferred object
    dfd = Annotator.$.Deferred()

    # Check whether we got a proper event
    unless event?
      throw new Error "Called onSuccessfulSelection without an event!"
    unless event.segments?
      throw new Error "Called onSuccessulSelection with an event with missing segments!"

    # Are we allowed to create annotations?
    unless @annotator.canAnnotate
      dfd.reject "I can't annotate right now. (Maybe already creating an annotation?)"
      return dfd.promise()

    # Describe the selection with targets
    @_getTargetsFromSelections(event.segments).then(((targets) =>
      @_selectedTargets = targets
      @_selectedData = event.annotationData

      # Do we want immediate annotation?
      if immediate
        # Create an annotation
        @annotator.onAdderClick event
        dfd.resolve "adder clicked"
      else
        # Show the adder button
        @annotator.adder
          .css(Annotator.util.mousePosition(event, @annotator.wrapper[0]))
          .show()
        dfd.resolve "adder shown"
    ), ((reason) ->
      dfd.reject "Looks like I can't annotate these parts. Sorry."
    ))

    # Return the promise
    dfd.promise()

  onFailedSelection: (event) =>
    @annotator.adder.hide()
    @_selectedTargets = []
    delete @_selectedData

  # Public: Initialises an annotation either from an object representation or
  # an annotation created with Annotator#createAnnotation(). It finds the
  # selected range and higlights the selection in the DOM, extracts the
  # quoted text and serializes the range.
  #
  # annotation - An annotation Object to initialise.
  #
  # Examples
  #
  #   # Create a brand new annotation from the currently selected text.
  #   annotation = annotator.createAnnotation()
  #   annotation = annotator.setupAnnotation(annotation)
  #   # annotation has now been assigned the currently selected range
  #   # and a highlight appended to the DOM.
  #
  #   # Add an existing annotation that has been stored elsewere to the DOM.
  #   annotation = getStoredAnnotationWithSerializedRanges()
  #   annotation = annotator.setupAnnotation(annotation)
  #
  # Returns a promise which will be resolved with the initialised annotation.
  setupAnnotation: (annotation) =>

    # To work with annotations, we need to set up the anchoring system
    @initAnchoring?()

    # If this is a new annotation, we might have to add the targets
    annotation.target ?= @_selectedTargets
    @_selectedTargets = []

    unless annotation.target?
      throw new Error "Can not run setupAnnotation(). No target or selection available."

    # In the lonely world of annotations, everybody is born as an orphan.
    @orphans.push annotation

    # In order to change this, let's try to anchor this annotation!
    @_anchorAnnotation annotation

    # _anchorAnnotation will return a promise; we just pass it on
    # as our return value.

  # Public: Deletes the annotation by removing the highlight from the DOM.
  # Publishes the 'annotationDeleted' event on completion.
  #
  # annotation - An annotation Object to delete.
  #
  # Returns deleted annotation.
  deleteAnnotation: (annotation) =>
    if annotation.anchors?                     # If we have anchors,
      @_removeAnchor(a) for a in annotation.anchors   # remove them

    # By the time we delete them, every annotation is an orphan,
    # (since we have just deleted all of it's anchors),
    # so time to remove it from the orphan list.
    @removeFromSet annotation, this.orphans

    @annotator.publish('annotationDeleted', [annotation])
    annotation

  # Configure the highlights for an annotation as temporary
  setAnnotationTemporary: (annotation, value) =>
    for anchor in annotation.anchors
      for page, hl of anchor.highlight
        hl.setTemporary value

# This is the actual Annotator plugin, installing the framework
class Annotator.Plugin.EnhancedAnchoring extends Annotator.Plugin

  pluginInit: ->
    @annotator.anchoring = manager =
      new EnhancedAnchoringManager @annotator

    for own k,v of manager when k[0] isnt "_" and k isnt "annotator"
      #console.log "Exporting", k, "(", typeof(v), ")"
      @annotator[k] = v


Annotator.Highlight = Highlight

