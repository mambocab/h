$ = Annotator.$

class Annotator.Plugin.Bridge extends Annotator.Plugin
  # These events maintain the awareness of annotations between the two
  # communicating annotators.
  events:
    'beforeAnnotationCreated': 'beforeAnnotationCreated'
    'annotationCreated': 'annotationCreated'
    'annotationUpdated': 'annotationUpdated'
    'annotationDeleted': 'annotationDeleted'
    'annotationsLoaded': 'annotationsLoaded'
    'enableAnnotating': 'enableAnnotating'

  # Helper method for merging info from a remote target
  @_mergeTarget: (local, remote, gateway) =>
#    console.log "Updating target in",
#      if gateway then "sidebar" else "host frame"

    deleted = []
    for field, val of local when (not remote[field]?)
      if not gateway and field in ["diffHTML", "diffCaseOnly"]
#        console.log "Ignoring attempt to delete", field, "from host frame"
      else
        deleted.push
          field: field
          value: val

    changed = []
    for field, val of local when (remote[field]? and remote[field] isnt val)
      unless Array.isArray val
        if not gateway and field in ["quote"]
#          console.log "Ignoring attempt to change", field, "in host frame"
        else
          changed.push
            field: field
            oldValue: val
            newValue: remote[field]

    added = []
    for field, val of remote when (not local[field]?)
      added.push
        field: field
        val: val

    if deleted.length
#      console.log "Deleted old values:"
      deleted.forEach (d) ->
#        console.log "'" + d.field + "': ", d.value
        delete local[d.field]


    if changed.length
#      console.log "Changed values:"
      changed.forEach (c) ->
#        console.log "'" + c.field + "': '" + c.oldValue + "'" + " -> " + "'" + c.newValue + "'"
        local[c.field] = c.newValue

    if added.length
#      console.log "Newly added values:"
      added.forEach (a) ->
#        console.log "'" + a.field + "': ", a.val
        local[a.field] = a.val


  # Helper method for merging info from a list of remote targets
  @_mergeTargets: (annotation, remote, gateway) =>

    local = annotation.target  # The current target list

    if local and local.length > remote.length
#      console.log "Ignoring update which would make me loose a target in",
        if gateway then "sidebar" else "host frame"
    else if local and local.length is remote.length
      # Same targets, just update the data
      for i in [0 ... local.length]
        @_mergeTarget local[i], remote[i], gateway
    else
      # We have more targets now!
#      console.log "Receiving new targets in",
        if gateway then "sidebar" else "host frame"
      annotation.target = remote

  # Plugin configuration
  options:

    # Origins allowed to communicate on the channel
    origin: '*'

    # Scope identifier to distinguish this channel from any others
    scope: 'annotator:bridge'

    # When this is true, this bridge will act as a gateway and, similar to DHCP,
    # offer to connect to bridges in other frames it discovers.
    gateway: false

    # A callback to invoke when a connection is established. The function is
    # passed two arguments, the source window and origin of the other frame.
    onConnect: -> true

    # Formats an annotation for sending across the bridge
    formatter: (annotation) -> annotation

    # Parses an annotation received from the bridge
    parser: (annotation) -> annotation

    # Merge function. If specified, it will be called with the local copy of
    # an annotation and a parsed copy received as an argument to an RPC call
    # to reconcile any differences. The default behavior is to merge all
    # keys of the remote object into the local copy
    merge: (local, remote) ->
      for k, v of remote
        if k is "target"
          Bridge._mergeTargets local, v, @gateway
        else
          local[k] = v
      local

  # Cache of annotations which have crossed the bridge for fast, encapsulated
  # association of annotations received in arguments to window-local copies.
  cache: null

  # Connected bridge links
  links: null

  # Annotations currently being updated -- used to avoid event callback loops
  updating: null

  constructor: (elem, options) ->
    if options.window?
      # Pull the option out and restore it after the super constructor is
      # called. Unfortunately, Delegator uses a jQuery function which
      # inspects this too closely and causes security errors.
      window = options.window
      delete options.window
      super elem, options
      @options.window = window
    else
      super

    @cache = {}
    @links = []
    @updating = {}

  pluginInit: ->
    $(window).on 'message', this._onMessage
    this._beacon()

  destroy: ->
    super
    $(window).off 'message', this._onMessage

  # Assign a non-enumerable tag to objects which cross the bridge.
  # This tag is used to identify the objects between message.
  _tag: (msg, tag) ->
    return msg if msg.$$tag
    tag = tag or (window.btoa Math.random())
    Object.defineProperty msg, '$$tag', value: tag
    @cache[tag] = msg
    msg

  # Parse an annotation from a RPC with the configured parser
  _parse: ({tag, msg}) ->
    local = @cache[tag]
    remote = @options.parser msg

    if local?
      merged = @options.merge local, remote
    else
      merged = remote

    this._tag merged, tag

  # Format an annotation for RPC with the configured formatter
  _format: (annotation) ->
    this._tag annotation
    msg = @options.formatter annotation
    tag: annotation.$$tag
    msg: msg

  # Construct a channel to another frame
  _build: (options) ->
    # jschannel chokes on FF and Chrome extension origins.
    if (options.origin.match /^chrome-extension:\/\//) or
        (options.origin.match /^resource:\/\//)
      options.origin = '*'

    console.log "Bridge plugin connecting to #{options.origin}"
#    options.debugOutput = true
    channel = Channel.build(options)

    ## Remote method call bindings
    .bind('setupAnnotation', (txn, annotation) =>
      this._format (@annotator.setupAnnotation (this._parse annotation))
    )

    .bind('beforeCreateAnnotation', (txn, annotation) =>
      annotation = this._parse annotation
      delete @cache[annotation.$$tag]
      @annotator.publish 'beforeAnnotationCreated', annotation
      @cache[annotation.$$tag] = annotation
      this._format annotation
    )

    .bind('createAnnotation', (txn, annotation) =>
      annotation = this._parse annotation
      delete @cache[annotation.$$tag]
      @annotator.publish 'annotationCreated', annotation
      @cache[annotation.$$tag] = annotation
      this._format annotation
    )

    .bind('updateAnnotation', (txn, annotation) =>
      annotation = this._parse annotation
      delete @cache[annotation.$$tag]
      annotation = @annotator.updateAnnotation annotation
      @cache[annotation.$$tag] = annotation
      this._format annotation
    )

    .bind('deleteAnnotation', (txn, annotation) =>
      annotation = this._parse annotation
      delete @cache[annotation.$$tag]
      annotation = @annotator.deleteAnnotation annotation
      res = this._format annotation
      delete @cache[annotation.$$tag]
      res
    )

    ## Notifications
    .bind('loadAnnotations', (txn, annotations) =>
      # First, parse the existing ones, for any updates
      oldOnes = (this._parse a for a in annotations when @cache[a.tag])

      # Announce the changes in old annotations
      if oldOnes.length
        @selfPublish = true
        @annotator.publish 'annotationsLoaded', [oldOnes]
        delete @selfPublish

      # Then collect the new ones
      newOnes = (this._parse a for a in annotations when not @cache[a.tag])
      if newOnes.length
        @annotator.loadAnnotations newOnes
    )

    .bind('showEditor', (ctx, annotation) =>
      @annotator.showEditor (this._parse annotation)
    )

    .bind('enableAnnotating', (ctx, state) =>
      @annotator.enableAnnotating state, false
    )

  # Send out a beacon to let other frames know to connect to us
  _beacon: ->
    queue = [window.top]
    while queue.length
      parent = queue.shift()
      if parent isnt window
        console.log window.location.toString(), 'sending beacon...'
        parent.postMessage '__annotator_dhcp_discovery', @options.origin
      for child in parent.frames
        queue.push child

  # Make a method call on all links
  _call: (options) ->
    _makeDestroyFn = (c) =>
      (error, reason) =>
        c.destroy()
        @links = (l for l in @links when l.channel isnt c)

    deferreds = @links.map (l) ->
      d = $.Deferred().fail (_makeDestroyFn l.channel)
      options = $.extend {}, options,
        success: (result) -> d.resolve result
        error: (error, reason) ->
          if error isnt 'timeout_error'
            console.log 'Error in call! Reason: ' + reason
            console.log error
            console.log "Call was:", options
            console.log 'Destroying channel!'
            d.reject error, reason
          else
            d.resolve null
        timeout: 1000
      l.channel.call options
      d.promise()

    $.when(deferreds...)
    .then (results...) =>
      annotation = {}
      for r in results when r isnt null
        $.extend annotation, (this._parse r)
      options.callback? null, annotation
    .fail (failure) =>
      options.callback? failure

  # Publish a notification to all links
  _notify: (options) ->
    for l in @links
      l.channel.notify options

  _onMessage: (e) =>
    {source, origin, data} = e.originalEvent
    match = data.match? /^__annotator_dhcp_(discovery|ack|offer)(:\d+)?$/
    return unless match

    if match[1] is 'discovery'
      if @options.gateway
        scope = ':' + ('' + Math.random()).replace(/\D/g, '')
        source.postMessage '__annotator_dhcp_offer' + scope, origin
      else
        source.postMessage '__annotator_dhcp_ack', origin
        return
    else if match[1] is 'ack'
      if @options.gateway
        scope = ':' + ('' + Math.random()).replace(/\D/g, '')
        source.postMessage '__annotator_dhcp_offer' + scope, origin
      else
        return
    else if match[1] is 'offer'
      if @options.gateway
        return
      else
        scope = match[2]

    scope = @options.scope + scope
    options = $.extend {}, @options,
      window: source
      origin: origin
      scope: scope
      onReady: =>
        options.onConnect.call @annotator, source, origin, scope
        annotations = (this._format a for t, a of @cache)
        if annotations.length
          channel.notify
            method: 'loadAnnotations'
            params: annotations

    channel = this._build options

    @links.push
      channel: channel
      window: source

  beforeAnnotationCreated: (annotation) =>
    return if annotation.$$tag?
    this.beforeCreateAnnotation annotation
    this

  annotationCreated: (annotation) =>
    return unless annotation.$$tag? and @cache[annotation.$$tag]
    this.createAnnotation annotation
    this

  annotationUpdated: (annotation) =>
    return unless annotation.$$tag? and @cache[annotation.$$tag]
    this.updateAnnotation annotation
    this

  annotationDeleted: (annotation) =>
    return unless annotation.$$tag? and @cache[annotation.$$tag]
    this.deleteAnnotation annotation, (err) =>
      if err then @annotator.setupAnnotation annotation
      else delete @cache[annotation.$$tag]
    this

  annotationsLoaded: (annotations) =>
    return if @selfPublish
    unless annotations.length
      console.log "Useless call to 'annotationsLoaded()' with an empty list"
      console.trace()
      return
    this._notify
      method: 'loadAnnotations'
      params: (this._format a for a in annotations)
    this

  beforeCreateAnnotation: (annotation, cb) ->
    this._call
      method: 'beforeCreateAnnotation'
      params: this._format annotation
      callback: cb
    annotation

  setupAnnotation: (annotation, cb) ->
    this._call
      method: 'setupAnnotation'
      params: this._format annotation
      callback: cb
    annotation

  createAnnotation: (annotation, cb) ->
    this._call
      method: 'createAnnotation'
      params: this._format annotation
      callback: cb
    annotation

  updateAnnotation: (annotation, cb) ->
    this._call
      method: 'updateAnnotation'
      params: this._format annotation
      callback: cb
    annotation

  deleteAnnotation: (annotation, cb) ->
    this._call
      method: 'deleteAnnotation'
      params: this._format annotation
      callback: cb
    annotation

  showEditor: (annotation) ->
    this._notify
      method: 'showEditor'
      params: this._format annotation
    this

  enableAnnotating: (state) ->
    this._notify
      method: 'enableAnnotating'
      params: state
