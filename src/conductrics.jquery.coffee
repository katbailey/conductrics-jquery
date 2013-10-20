# Add a conductrics jquery plugin
$.fn.extend
  conductrics: (method) ->

    # Interpret certain special "command" type decision strings such as "show" and "hide"
    processSelection = (selected, selector) ->
      switch selected
        when 'show'
          selector.show()
        when 'hide'
          selector.hide()
        else
          throw new Error('invalid operation')

    methods = {
      toggle: (optionz, callback) ->
        throw new Error('no conductrics instance') unless optionz.conductrics_api
        $this = $(this);
        # developer may override any of these defaults
        options = $.extend({
          choices: ['show', 'hide'],
          initial: 'hide',
        }, optionz)
        # Initial state of dom elements
        processSelection(options.initial, $this)
        # Call out to Conductrics
        options.conductrics_api.getDecision(options, (selection) ->
          processSelection(selection.code, $this)
        )
        this


      'redirect-to-best-url': (urls, optionz, callback) ->
        throw new Error('no conductrics instance') unless optionz.conductrics_api
        # developer may override any of these defaults
        options = $.extend {}, optionz
        options.choices = urls.length

        selectedUrl = urls[0] # in case anything goes wrong, we'll fall back to this
        # Call out to Conductrics
        options.conductrics_api.getDecision(options, (selection) ->
          selectedUrl = urls[selection.code] unless selection.code == null
        )
        window.location.replace selectedUrl
        this
    }

    if methods[method]
      methods[method].apply(this, Array.prototype.slice.call( arguments, 1 ))