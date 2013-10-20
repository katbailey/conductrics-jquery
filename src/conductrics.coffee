# Reference jQuery
$ = jQuery

window.conductrics = (options) ->

  # developer may override any of these defaults
  settings = $.extend(true, {
    'baseUrl': 'http://api.conductrics.com',
    'apiKey': null,
    'agent': null,
    'session': null,
    'timeout': 1000,
    'caching': false, # set to 'localStorage' to enable local decision cache
    'cachingMaxAge': (30*60), # used only if caching enabled, expressed in seconds
  # Explicit cookie support - not needed in recent versions of jQuery, but required in 1.4-era jQuery
  # Ignored if a session identifier is provided explicitly (above)
    'sessionCookies': false, # set to true to forcibly store the session id returned by Conductrics as a cookie
    'sessionCookieName': 'mpid', # Name of 'mpid' is recommended
    'sessionCookieOptions': {
    # can specify 'domain', 'expires', 'path', and other options as explained here: https://github.com/carhartl/jquery-cookie
    # The most important options are:
    # expires: 30, // number of days that the session id should be retained - if not specified, cookie is discarded when browser closed
    # domain: '.example.com', // a top-level domain, within which the cookie may be shared - so a value of '.example.com' here will allow Conductrics tracking to work between say 'www.example.com' and 'store.example.com'
      path: '/'
    }
  }, options)

  # Private methods

  # Simple wrapper around $.ajax
  doAjax = (url, type, data, callback) ->
    # Local cookie support, if enabled
    if data.session == null && settings.sessionCookies
      storedId = $.cookie(settings.sessionCookieName)
      data.session = storedId if storedId

    # Workaround for IE 8/9 style cross-domain requests
    data.session = getWorkaroundId() if data.session == null && window.XDomainRequest

    # If we still have a null session id, don't send one at all (don't send 'null')
    delete data.session if data.session == null

    $.ajax({
      url: url,
      type: type,
      dataType: 'json',
      data: data,
      timeout: settings.timeout,
      success: (data, textStatus, jqXHR) ->
        # Local cookie support, if enabled
        if settings.sessionCookies && data != null && data.session != null
          $.cookie(settings.sessionCookieName, data.session, settings.sessionCookieOptions);

        # Notify callback
        if typeof(callback) == 'function'
          callback(data, textStatus, jqXHR)

      error: (jqXHR, textStatus, errorThrown) ->
        if typeof(callback) == 'function'
          callback(null, textStatus, jqXHR)

      xhrFields: {
        withCredentials:true
      }
    })


  # Make API url construction a bit less repetitive
  constructUrl = (parts, options) ->
    [settings.baseUrl, settings.owner, options.agent].concat(parts).join('/')


  getWorkaroundId = ->
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890".split("")
    randomElement = (arr) ->
      arr[Math.floor(Math.random() * arr.length)]
    randomString = (len, prefix) ->
      prefix = "" if prefix == null
      while prefix.length < len
        prefix += randomElement(alphabet)
      return prefix
    workaroundID = $.cookie('conductrics-id')
    if workaroundID == undefined
      workaroundID = randomString 32, 'cond-'
      $.cookie 'conductrics-id', workaroundID

    workaroundID


  # For error messaging
  complain = ->
    if console && console.log
      console.log arguments


  # Basic validation
  ensure = (options, keys) ->
    for key in keys
      if options[key] == undefined
        complain "Conductrics plugin cannot proceed because option '" + key + "' is not provided."
        return false
    true


  validCode = (s) ->
    s != null && s.length > 0 && s.length < 25 && !(/[^0-9A-Za-z_-]/).test(s)


  sanitizeCodesStr = (str) ->
    return "" unless str
    sanitizeCodes(str.split(',')).join(',')


  sanitizeCodes = (codes) ->
    return [] unless codes
    result = []
    for value in codes
      if validCode(value)
        result.push codes[i]
    result


  supportsHtmlLocalStorage = ->
    return false unless settings.caching == 'localStorage'
    try
      return 'localStorage' in window && window['localStorage'] != null
    catch e
      return false


  storageKey = (options, name) ->
    ar = []
    ks = ['baseUrl', 'owner', 'agent', 'session']
    for value in ks
      if options[value] != null
        ar.push options[value]
      else if settings[value] != null
        ar.push settings[value]
    ar.push name if name
    ar.join ':'


  storageRead = (options, name, defaultValue) ->
    return defaultValue unless supportsHtmlLocalStorage()
    store = localStorage
    key = storageKey(options, name)
    stored = store.getItem key
    if stored
      record = JSON.parse stored
      return record.val if record.val
    defaultValue


  storageWrite = (options, name, value) ->
    return unless supportsHtmlLocalStorage()
    store = localStorage
    key = storageKey(options, name)
    record = {ts:new Date().getTime(), val:value}
    store.setItem(key, JSON.stringify(record))


  storageMaintain = ->
    return unless supportsHtmlLocalStorage()
    store = localStorage
    for key, value of store
      if key.indexOf [settings.baseUrl, settings.owner].join(':') == 0
        # clean expired info for this server and owner
        if value
          record = JSON.parse value
          if record.ts && (record.ts + (settings.cachingMaxAge * 1000)) < new Date().getTime()
            store.removeItem(key)
    return

  storageMaintain()
  return {

  # Get a decision from an agent
  getDecision: (options, callback) ->
    # developer may override any of these defaults
    options = $.extend({
      agent: settings.agent,
      session: settings.session,
      decision: 'decision-1',
      choices: ['a','b']
    }, options)

    unless ensure(options, ['agent'])
      return # Bail if we don't have enough info

    unless ensure(settings, ['baseUrl', 'owner', 'apiKey'])
      return # Bail if we don't have enough info

    url = constructUrl(['decisions', options.choices.toString()], options)
    data = {apikey: settings.apiKey}
    data.session = options.session unless options.session == null
    if options.features
      data.features = sanitizeCodesStr options.features

    # Determine fallback selection - if anything goes wrong, we'll fall back to this
    if typeof options.choices == 'number'
      selection = {code: 0}
    else if typeof options.choices.join == 'function'
      # it's an array
      selection = {code: options.choices[0]}

    if settings.caching
      decisions = storageRead(options, 'dec')
      if decisions && decisions[options.decision]
        selection = decisions[options.decision]
        if typeof callback == 'function'
          callback.apply(this, [selection, null, 'stored', null])
          return

    doAjax(url, 'GET', data, (response, textStatus, jqXHR) ->
      if textStatus == 'success'
        selection = response.decisions[options.decision]
        if settings.caching && selection
          storageWrite(options, 'dec', response.decisions)

      if typeof callback == 'function'
        callback.apply(this, [selection, response, textStatus, jqXHR])
      )
    this


  # Send a goal to an agent.
  sendGoal: (options, callback) ->
    # developer may override any of these defaults
    options = $.extend({
      agent: settings.agent,
      session: settings.session,
      reward: null,
      goal: 'goal-1'
    }, options);

    url = constructUrl ['goal', options.goal], options
    data = {apikey: settings.apiKey}
    data.reward = options.reward if options.reward
    data.session = options.session if options.session

    doAjax(url, 'POST', data, (response, textStatus, jqXHR) ->
      if typeof callback == 'function'
        callback.apply(this, [response, textStatus, jqXHR])
    )


  # Expire a session.
  expireSession: (options, callback) ->
    options = $.extend({
      agent: settings.agent,
      session: settings.session
    }, options)

    url = constructUrl ['expire'], options
    data = {apikey: settings.apiKey}
    data.session = options.session if options.session

    doAjax(url, 'GET', data, (response, textStatus, jqXHR) ->
      if typeof callback == 'function'
        callback.apply(this, [response, textStatus, jqXHR])
    )
    this
  }