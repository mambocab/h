imports = [
  'bootstrap'
  'h.controllers'
  'h.directives'
  'h.filters'
  'h.flash'
  'h.helpers'
  'h.session'
  'h.socket'
  'h.streamfilter'
]

SEARCH_FACETS = ['text', 'tags', 'uri', 'quote', 'since', 'user', 'results']
SEARCH_VALUES =
  group: ['Public', 'Private'],
  since: ['5 min', '30 min', '1 hour', '12 hours',
          '1 day', '1 week', '1 month', '1 year']


class StreamSearch
  this.inject = [
    '$location', '$scope', '$timeout',
    'baseURI', 'socket', 'streamfilter'
  ]
  constructor: (
     $location,   $scope,   $timeout,
     baseURI,   socket,   streamfilter
  ) ->
    $scope.empty = false

    $scope.loadMore = (number) =>
      console.log 'loadMore'
      unless $scope.updater? then return
      sockmsg =
        messageType: 'more_hits'
        moreHits: number

      $scope.updater.send(JSON.stringify(sockmsg))


angular.module('h.streamsearch', imports, configure)
.constant('searchFacets', SEARCH_FACETS)
.constant('searchValues', SEARCH_VALUES)
.controller('StreamSearchController', StreamSearch)
