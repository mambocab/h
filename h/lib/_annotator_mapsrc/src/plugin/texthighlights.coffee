# This plugin containts the text highlight implementation,
# required for annotating text.

class TextHighlight extends Annotator.Highlight

  # Save the Annotator class reference, while we have access to it.
  # TODO: Is this really the way to go? How do other plugins do it?
  @$ = Annotator.$

  # Public: Wraps the DOM Nodes within the provided range with a highlight
  # element of the specified class and returns the highlight Elements.
  #
  # normedRange - A NormalizedRange to be highlighted.
  # cssClass - A CSS class to use for the highlight (default: 'annotator-hl')
  #
  # Returns an array of highlight Elements.
  _highlightRange: (normedRange, cssClass='annotator-hl') ->
    white = /^\s*$/

    hl = @$("<span class='#{cssClass}'></span>")

    # Ignore text nodes that contain only whitespace characters. This prevents
    # spans being injected between elements that can only contain a restricted
    # subset of nodes such as table rows and lists. This does mean that there
    # may be the odd abandoned whitespace node in a paragraph that is skipped
    # but better than breaking table layouts.

    nodes = @$(normedRange.textNodes()).filter((i) -> not white.test @nodeValue)
    nodes.wrap(hl).parent().show().toArray()

  constructor: (anchor, pageIndex, normedRange) ->
    super anchor, pageIndex

    @$ = TextHighlight.$

    # Create a highlights, and link them with the annotation
    @_highlights = @_highlightRange normedRange
    @$(@_highlights).data "annotation", @annotation

  # Implementing the required APIs

  # Is this a temporary hl?
  isTemporary: -> @_temporary

  # Mark/unmark this hl as active
  setTemporary: (value) ->
    @_temporary = value
    if value
      @$(@_highlights).addClass('annotator-hl-temporary')
    else
      @$(@_highlights).removeClass('annotator-hl-temporary')

  # Mark/unmark this hl as active
  setActive: (value) ->
    if value
      @$(@_highlights).addClass('annotator-hl-active')
    else
      @$(@_highlights).removeClass('annotator-hl-active')

  # Mark/unmark this hl as focused
  setFocused: (value) ->
    if value
      @$(@_highlights).addClass('annotator-hl-focused')
    else
      @$(@_highlights).removeClass('annotator-hl-focused')

  # Remove all traces of this hl from the document
  removeFromDocument: ->
    for hl in @_highlights
      # Is this highlight actually the part of the document?
      if hl.parentNode? and @annotator.domMapper.isPageMapped @pageIndex
        # We should restore original state
        child = hl.childNodes[0]
        @$(hl).replaceWith hl.childNodes

  # Get the HTML elements making up the highlight
  _getDOMElements: -> @_highlights

class Annotator.Plugin.TextHighlights extends Annotator.Plugin

  highlightType: 'TextHighlight'

  # Plugin initialization
  pluginInit: ->

    # This plugin is intended to be used with the Enhanced Anchoring architecture.        
    unless @annotator.plugins.EnhancedAnchoring
      throw new Error "The TextHighlights Annotator plugin requires the EnhancedAnchoring plugin."

    @Annotator = Annotator
    @$ = Annotator.$

    # Register this highlighting implementation
    @annotator.registerHighlighter
      name: "standard text highlighter"
      highlight: @_createTextHighlight
      isInstance: @_isInstance
      getIndependentParent: @_getIndependentParent

    # Set up events for annotator
    @annotator.element.delegate ".annotator-hl", "mouseover", this,
       (event) => @annotator.onHighlightMouseover event

    @annotator.element.delegate ".annotator-hl", "mouseout", this,
       (event) => @annotator.onHighlightMouseout event

    @annotator.element.delegate ".annotator-hl", "mousedown", this,
       (event) => @annotator.onHighlightMousedown event

    @annotator.element.delegate ".annotator-hl", "click", this,
       (event) => @annotator.onHighlightClick event

  # This is the entry point registered with Annotator
  _createTextHighlight: (anchor, page) =>

    # Prepare the deferred object
    dfd = @$.Deferred()

    # Check out the anchor type
    switch anchor.type

      when "text range"
        # Create the highligh
        hl = new TextHighlight anchor, page, anchor.range

        # Resolve the promise
        dfd.resolve hl

      when "text position"

        # Get the d-t-m in a consistent state
        @annotator.domMapper.prepare("highlighting").then (s) =>
          # When the d-t-m is ready, do this

          try
            # First we create the range from the stored stard and end offsets
            mappings = s.getMappingsForCharRange anchor.start, anchor.end, [page]

            # Get the wanted range out of the response of DTM
            realRange = mappings.sections[page].realRange

            # Get a BrowserRange
            browserRange = new @Annotator.Range.BrowserRange realRange

            # Get a NormalizedRange
            normedRange = browserRange.normalize @annotator.wrapper[0]

            # Create the highligh
            hl = new TextHighlight anchor, page, normedRange

            # Resolve the promise
            dfd.resolve hl

          catch error
            # Something went wrong during creating the highlight
            # Reject the promise
            try
              dfd.reject
                message: "Cought exception"
                error: error
            catch e2
              console.log "WTF", e2.stack

      else
        dfd.reject "Can only handle 'text range' and 'text position' anchors"

    # Return the promise
    dfd.promise()

  # Is this element a text highlight physical anchor ?
  isInstance: (element) => @$(element).hasClass 'annotator-hl'

  # Find the first parent outside this physical anchor
  getIndependentParent: (element) =>
    @$(element).parents(':not([class^=annotator-hl])')[0]

  # Collect the annotations impacted by an event
  getAnnotations: (event) =>
    @$(event.target)
      .parents('.annotator-hl')
      .andSelf()
      .map( -> TextHighlight.$(this).data("annotation"))
      .toArray()
