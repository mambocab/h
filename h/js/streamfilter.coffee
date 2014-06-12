class ClauseParser
  filter_fields : ['references', 'text', 'user', 'uri', 'id', 'tags', 'created', 'updated']
  operators: [
    '#<=', '#>=', '#<', '#>', '#=',
    '=>', '>=', '<=', '=<', '>', '<',
    '[', '=~', '^', '{',
    '='
  ]
  operator_mapping:
    '=': 'equals'
    '>': 'gt'
    '<': 'lt'
    '=>': 'ge'
    '>=': 'ge'
    '=<': 'le'
    '<=': 'le'
    '[' : 'one_of'
    '=~' : 'matches'
    '^' : 'first_of'
    '{' : 'match_of' # one_of but not exact search
    '#=' : 'lene'
    '#>' : 'leng'
    '#>=' : 'lenge'
    '#<' : 'lenl'
    '#<=' : 'lenle'
  insensitive_operator : 'i'

  parse_clauses: (clauses) ->
    bads = []
    structure = []
    unless clauses
      return
    clauses = clauses.split ' '
    for clause in clauses
      #Here comes the long and boring validation checking
      clause = clause.trim()
      if clause.length < 1 then continue

      parts = clause.split /:(.+)/
      unless parts.length > 1
        bads.push [clause, 'Filter clause is not well separated']
        continue

      unless parts[0] in @filter_fields
        bads.push [clause, 'Unknown filter field']
        continue

      field = parts[0]

      if parts[1][0] is @insensitive_operator
        sensitive = false
        rest = parts[1][1..]
      else
        sensitive = true
        rest = parts[1]

      operator_found = false
      for operator in @operators
        if (rest.indexOf operator) is 0
          oper = @operator_mapping[operator]
          if operator is '[' or operator is '{'
            value = rest[operator.length..].split ','
          else
            value = rest[operator.length..]
          operator_found = true
          if field is 'user'
            value = 'acct:' + value + '@' + window.location.hostname
          break

      unless operator_found
        bads.push [clause, 'Unknown operator']
        continue

      structure.push
        'field'   : '/' + field
        'operator': oper
        'value'   : value
        'case_sensitive': sensitive
    [structure, bads]


# This class will process the results of search and generate the correct filter
# It expects the following dict format as rules
# { facet_name : {
#      formatter: to format the value (optional)
#      path: json path mapping to the annotation field
#      exact_match: true|false (default: true)
#      case_sensitive: true|false (default: false)
#      and_or: and|or for multiple values should it threat them as 'or' or 'and' (def: or)
#      es_query_string: should the streaming backend use query_string es query for this facet
#      operator: if given it'll use this operator regardless of other circumstances
# }
# The models is the direct output from visualsearch
# The limit is the default limit
class QueryParser
  rules:
    user:
      formatter: (user) ->
        'acct:' + user + '@' + window.location.hostname
      path: '/user'
      exact_match: true
      case_sensitive: false
      and_or: 'or'
    text:
      path: '/text'
      exact_match: false
      case_sensitive: false
      and_or: 'and'
    tags:
      path: '/tags'
      exact_match: false
      case_sensitive: false
      and_or: 'or'
    quote:
      path: "/quote"
      exact_match: false
      case_sensitive: false
      and_or: 'and'
    uri:
      formatter: (uri) ->
        uri = uri.toLowerCase()
        if uri.match(/http:\/\//) then uri = uri.substring(7)
        if uri.match(/https:\/\//) then uri = uri.substring(8)
        if uri.match(/^www\./) then uri = uri.substring(4)
        uri
      path: '/uri'
      exact_match: false
      case_sensitive: false
      es_query_string: true
      and_or: 'or'
    since:
      formatter: (past) ->
        seconds =
          switch past
            when '5 min' then 5*60
            when '30 min' then 30*60
            when '1 hour' then 60*60
            when '12 hours' then 12*60*60
            when '1 day' then 24*60*60
            when '1 week' then 7*24*60*60
            when '1 month' then 30*24*60*60
            when '1 year' then 365*24*60*60
        new Date(new Date().valueOf() - seconds*1000)
      path: '/created'
      exact_match: false
      case_sensitive: true
      and_or: 'and'
      operator: 'ge'

  populateFilter: (filter, models) ->
    # First cluster the different facets into categories
    categories = {}
    for searchItem in models
      category = searchItem.attributes.category
      value = searchItem.attributes.value

      if category is 'results' then limit = value
      else
        if category is 'text'
          # Visualsearch sickly automatically cluster the text field
          # (and only the text filed) into a space separated string
          catlist = []
          catlist.push val for val in value.split ' '
          categories[category] = catlist
        else
          if category of categories then categories[category].push value
          else categories[category] = [value]

    # Now for the categories
    for category, values of categories
      unless @rules[category]? then continue
      unless values.length then continue
      rule = @rules[category]

      # Now generate the clause with the help of the rule
      exact_match = if rule.exact_match? then rule.exact_match else true
      case_sensitive = if rule.case_sensitive? then rule.case_sensitive else false
      and_or = if rule.and_or? then rule.and_or else 'or'
      mapped_field = if rule.path? then rule.path else '/'+category
      es_query_string = if rule.es_query_string? then rule.es_query_string else false

      if values.length is 1
        oper_part =
          if rule.operator? then rule.operator
          else if exact_match then 'equals' else 'matches'
        value_part = if rule.formatter then rule.formatter values[0] else values[0]
        filter.addClause mapped_field, oper_part, value_part, case_sensitive, es_query_string
      else
        if and_or is 'or'
          val_list = ''
          first = true
          for val in values
            unless first then val_list += ',' else first = false
            value_part = if rule.formatter then rule.formatter val else val
            val_list += value_part
          oper_part =
            if rule.operator? then rule.operator
            else if exact_match then 'one_of' else 'match_of'
          filter.addClause mapped_field, oper_part, val_list, case_sensitive, es_query_string
        else
          oper_part =
            if rule.operator? then rule.operator
            else if exact_match then 'equals' else 'matches'
          for val in values
            value_part = if rule.formatter then rule.formatter val else val
            filter.addClause mapped_field, oper_part, value_part, case_sensitive, es_query_string

    if limit != 50 then categories['results'] = [limit]

    categories


class StreamFilter
  strategies: ['include_any', 'include_all', 'exclude_any', 'exclude_all']
  past_modes: ['none','hits','time']

  filter:
      match_policy :  'include_any'
      clauses : []
      actions :
        create: true
        update: true
        delete: true
      past_data:
        load_past: "none"

  constructor: ->
    @parser = new ClauseParser()

  getFilter: -> return @filter
  getPastData: -> return @filter.past_data
  getMatchPolicy: -> return @filter.match_policy
  getClauses: -> return @filter.clauses
  getActions: -> return @filter.actions
  getActionCreate: -> return @filter.actions.create
  getActionUpdate: -> return @filter.actions.update
  getActionDelete: -> return @filter.actions.delete

  setPastDataNone: ->
    @filter.past_data =
      load_past: 'none'
    this

  setPastDataHits: (hits) ->
    @filter.past_data =
      load_past: 'hits'
      hits: hits
    this

  setPastDataTime: (time) ->
    @filter.past_data =
      load_past: 'hits'
      go_back: time
    this

  setMatchPolicy: (policy) ->
    @filter.match_policy = policy
    this

  setMatchPolicyIncludeAny: ->
    @filter.match_policy = 'include_any'
    this

  setMatchPolicyIncludeAll: ->
    @filter.match_policy = 'include_all'
    this

  setMatchPolicyExcludeAny: ->
    @filter.match_policy = 'exclude_any'
    this

  setMatchPolicyExcludeAll: ->
    @filter.match_policy = 'exclude_all'
    this

  setActions: (actions) ->
    @filter.actions = actions
    this

  setActionCreate: (action) ->
    @filter.actions.create = action
    this

  setActionUpdate: (action) ->
    @filter.actions.update = action
    this

  setActionDelete: (action) ->
    @filter.actions.delete = action
    this

  noClauses: ->
    @filter.clauses = []
    this

  addClause: (clause) ->
    @filter.clauses.push clause
    this

  addClause: (field, operator, value, case_sensitive = false, es_query_string = false) ->
    @filter.clauses.push
      field: field
      operator: operator
      value: value
      case_sensitive: case_sensitive
      es_query_string: es_query_string
    this

  setClausesParse: (clauses_to_parse, error_checking = false) ->
    res = @parser.parse_clauses clauses_to_parse
    if res[1].length
      console.log "Errors while parsing clause:"
      console.log res[1]
    if res? and (not error_checking) or (error_checking and res[1]?.length is 0)
      @filter.clauses = res[0]
    this

  addClausesParse: (clauses_to_parse, error_checking = false) ->
    res = @parser.parse_clauses clauses_to_parse
    if res? and (not error_checking) or (error_checking and res[1]?.length is 0)
      for clause in res[0]
        @filter.clauses.push clause
    this

  resetFilter: ->
    @setMatchPolicyIncludeAny()
    @setActionCreate(true)
    @setActionUpdate(true)
    @setActionDelete(true)
    @setPastDataNone()
    @noClauses()
    this


angular.module('h.streamfilter', [])
.service('clauseparser', ClauseParser)
.service('queryparser', QueryParser)
.service('streamfilter', StreamFilter)
