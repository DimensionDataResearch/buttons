class GitHubAPIStatus
  @low_rate_limit = false

  window.callback = (json) =>
    @rate_limit = json.data
    @low_rate_limit = @rate_limit.resources.core.remaining < 16
    return

  @update: ->
    unless window.callback.script
      new Element "script", (script) ->
        script.async = true
        script.src = "https://api.github.com/rate_limit?callback=callback"
        window.callback.script = script
        @on "readystatechange", "load", "error", ->
          if !script.readyState or /loaded|complete/.test script.readyState
            script.parentNode.removeChild script
            window.callback.script = null
          return
        head = document.getElementsByTagName("head")[0]
        head.insertBefore script, head.firstChild
        return
    return

  @update()


class Form extends Element
  on: (events..., func) ->
    if events.indexOf("change") >= 0
      callback = (event) =>
        func.call @, event || window.event
      for element in @$.elements
        new Element element
          .on "change", "input", callback
    super

  serialize: ->
    data = {}
    for node in @$.elements when node.name
      switch node.type
        when "radio", "checkbox"
          data[node.name] = node.value if node.checked
        else
          data[node.name] = node.value
    data


class PreviewAnchor extends Element
  constructor: ({href, text, data, aria}, callback) ->
    super "a", (a) ->
      a.className = CONFIG_ANCHOR_CLASS
      a.href = href
      a.appendChild document.createTextNode "#{text}"
      a.setAttribute "data-#{name}", value for name, value of data
      a.setAttribute "aria-#{name}", value for name, value of aria
      callback a if callback
      return


class PreviewFrame extends Frame
  constructor: (preview) ->
    super (iframe) ->
      preview.appendChild iframe
      iframe.src = "buttons.html"
      return
    @on "load", ->
      if callback = @$.contentWindow.callback
        script = callback.script
        if script.readyState
          new Element script
            .on "readystatechange", ->
              @resize() if /loaded|complete/.test script.readyState
              return
        else
          new Element script
            .on "load", "error", ->
              @resize()
              return
      else
        @resize()
      return

  load: (config) ->
    parentNode = @$.parentNode
    parentNode.removeChild @$
    parentNode.style.height = "#{(if config.data.style is "mega" then 28 else 20) + 2}px"

    @$.style.width = "1px"
    @$.style.height = "0"
    @$.src = "buttons.html#{Hash.encode config}"

    parentNode.appendChild @$
    return


class Code extends Element
  constructor: ->
    super
    @on "focus", ->
      @$.select()
      return
    @on "click", ->
      @$.select()
      return
    @on "mouseup", (event) ->
      event.preventDefault()
      false


class ButtonForm extends Form
  constructor: (@$, {content, preview: {button, frame, code, warning}, snippet, user_repo}) ->
    @$.setAttribute key, value for key, value of {
      autocapitalize: "none"
      autocomplete: "off"
      autocorrect: "off"
      spellcheck: "false"
    }

    snippet.$.value = \
      """
      <!-- Place this tag in your head or just before your close body tag. -->
      <script async defer src="https://dimensiondataresearch.github.io/buttons/buttons.js"></script>
      """

    callback = ({force}) =>
      options = @serialize()

      if options.type
        content.removeClass "hidden"

        for name in ["repo", "standard-icon"]
          @$.elements[name].disabled = options.type is "follow"
        for name in ["show-count"]
          @$.elements[name].disabled = options.type is "download"

        unless (!options.user or validate_user options.user) and (options.type is "follow" or !options.repo or validate_repo options.repo)
          user_repo.addClass "has-error"
        else
          user_repo.removeClass "has-error"
          if options.user is "" or (options.type isnt "follow" and options.repo is "")
            user_repo.addClass "has-warning"
          else
            user_repo.removeClass "has-warning"

        if (user_repo.hasClass "has-error") or (user_repo.hasClass "has-warning")
          options.user = "DimensionDataCBUSydney"
          options.repo = "plumbery-contrib"

        if @cache isnt (cache = Hash.encode options) or force
          @cache = cache
          new PreviewAnchor @parse(options), (a) =>
            code.$.value = \
              """
              <!-- Place this tag where you want the button to render. -->
              #{a.outerHTML}
              """

            button.addClass "hidden"
            if options["show-count"]? and options.type isnt "download"
              GitHubAPIStatus.update()
              if GitHubAPIStatus.low_rate_limit
                button.removeClass "hidden"
                reset = new Date GitHubAPIStatus.rate_limit.resources.core.reset * 1000
                if !@reset or reset > @reset
                  @reset = reset
                  warning.removeClass "hidden"
                if force
                  warning.addClass "hidden"
                else
                  a.removeAttribute "data-count-api"

            frame.load ButtonAnchor.parse a
            a = null
            return
      return

    button.on "click", (event) ->
      event.preventDefault()
      callback force: true
      false
    @on "change", callback

  parse: (options = @serialize()) ->
    {type, user, repo} = options
    config =
      className: "dimensiondata-button"
      href:
        switch type
          when "deploy"
            "https://github.com/#{user}/#{repo}"
      text:
        switch type
          "Deploy to Dimension Data Cloud"
      data:
        icon:
          "octicon-cloud-upload"
      aria:
        label:
          switch type
            "Dimension Data Cloud"
    if options["large-button"]?
      config.data.style = "mega"
    if options["show-count"]?
      switch type
        when "follow"
          config.data["count-href"] = "/#{user}/followers"
          config.data["count-api"] = "/users/#{user}#followers"
          config.data["count-aria-label"] = "# followers on GitHub"
        when "watch"
          config.data["count-href"] = "/#{user}/#{repo}/watchers"
          config.data["count-api"] = "/repos/#{user}/#{repo}#subscribers_count"
          config.data["count-aria-label"] = "# watchers on GitHub"
        when "star"
          config.data["count-href"] = "/#{user}/#{repo}/stargazers"
          config.data["count-api"] = "/repos/#{user}/#{repo}#stargazers_count"
          config.data["count-aria-label"] = "# stargazers on GitHub"
        when "fork"
          config.data["count-href"] = "/#{user}/#{repo}/network"
          config.data["count-api"] = "/repos/#{user}/#{repo}#forks_count"
          config.data["count-aria-label"] = "# forks on GitHub"
        when "issue"
          config.data["count-api"] = "/repos/#{user}/#{repo}#open_issues_count"
          config.data["count-aria-label"] = "# issues on GitHub"
    if options["standard-icon"]? or config.data.icon is "octicon-cloud-upload"
      delete config.data.icon
    config

  validate_user = (user) ->
    0 < user.length < 40 and not /[^A-Za-z0-9-]|^-|-$|--/i.test user

  validate_repo = (repo) ->
    0 < repo.length < 101 and not /[^\w-.]|\.git$|^\.\.?$/i.test repo


new Deferred ->
  new ButtonForm document.getElementById("button-config"),
    content: new Element document.getElementById "content"
    user_repo: new Element document.getElementById "user-repo"
    preview:
      button: new Element document.getElementById "preview-button"
      frame: new PreviewFrame document.getElementById "preview"
      code: new Code document.getElementById "code"
      warning: new Element document.getElementById "preview-warning"
    snippet: new Code document.getElementById "snippet"
  return

@onbeforeunload = ->
