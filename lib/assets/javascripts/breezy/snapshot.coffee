#= require breezy/component_url
#= require breezy/csrf_token
#= require breezy/utils

class Breezy.Snapshot
  constructor: (@controller, @history) ->
    @pageCache = {}
    @currentBrowserState = null
    @pageCacheSize = 10
    @currentPage = null
    @loadedAssets= null

  onHistoryChange: (event) =>
    if event.state?.breezy && event.state.url != @currentBrowserState.url
      previousUrl = new Breezy.ComponentUrl(@currentBrowserState.url)
      newUrl = new Breezy.ComponentUrl(event.state.url)

      if restorePoint = @pageCache[newUrl.absolute]
        @cacheCurrentPage()
        @currentPage = restorePoint
        @controller.restore(@currentPage)
      else
        @controller.request event.target.location.href

  constrainPageCacheTo: (limit = @pageCacheSize) =>
    pageCacheKeys = Object.keys @pageCache

    cacheTimesRecentFirst = pageCacheKeys.map (url) =>
      @pageCache[url].cachedAt
    .sort (a, b) -> b - a

    for key in pageCacheKeys when @pageCache[key].cachedAt <= cacheTimesRecentFirst[limit]
      delete @pageCache[key]

  transitionCacheFor: (url) =>
    return if url is @currentBrowserState.url
    cachedPage = @pageCache[url]
    cachedPage if cachedPage and !cachedPage.transitionCacheDisabled

  pagesCached: (size = @pageCacheSize) =>
    @pageCacheSize = parseInt(size) if /^[\d]+$/.test size

  cacheCurrentPage: =>
    return unless @currentPage
    currentUrl = new Breezy.ComponentUrl @currentBrowserState.url

    Breezy.Utils.merge @currentPage,
      cachedAt: new Date().getTime()
      positionY: window.pageYOffset
      positionX: window.pageXOffset
      url: currentUrl.relative
      pathname: currentUrl.pathname
      transition_cache: true

    @pageCache[currentUrl.absolute] = @currentPage

  rememberCurrentUrlAndState: =>
    @history.replaceState { breezy: true, url: @currentComponentUrl().href }, '', @currentComponentUrl().href
    @currentBrowserState = @history.state

  removeParamFromUrl: (url, parameter) =>
    return url
      .replace(new RegExp('^([^#]*\?)(([^#]*)&)?' + parameter + '(\=[^&#]*)?(&|#|$)' ), '$1$3$5')
      .replace(/^([^#]*)((\?)&|\?(#|$))/,'$1$3$4')

  currentComponentUrl: =>
    new Breezy.ComponentUrl

  reflectNewUrl: (url) =>
    if (url = new Breezy.ComponentUrl url).absolute != @currentComponentUrl().href
      preservedHash = if url.hasNoHash() then @currentComponentUrl().hash else ''
      fullUrl = url.absolute + preservedHash
      fullUrl = @removeParamFromUrl(fullUrl, '_breezy_filter')
      fullUrl = @removeParamFromUrl(fullUrl, '__')

      @history.pushState { breezy: true, url: url.absolute + preservedHash }, '', fullUrl

  updateCurrentBrowserState: =>
    @currentBrowserState = @history.state

  updateBrowserTitle: =>
    document.title = @currentPage.title if @currentPage.title isnt false

  refreshBrowserForNewAssets: =>
    document.location.reload()

  changePage: (nextPage, options) =>
    if @currentPage and @assetsChanged(nextPage)
      @refreshBrowserForNewAssets()
      return

    @currentPage = nextPage
    @currentPage.title = options.title ? @currentPage.title
    @updateBrowserTitle()

    Breezy.CSRFToken.update @currentPage.csrf_token if @currentPage.csrf_token?
    @updateCurrentBrowserState()

  assetsChanged: (nextPage) =>
    @loadedAssets ||= @currentPage.assets
    fetchedAssets = nextPage.assets
    fetchedAssets.length isnt @loadedAssets.length or Breezy.Utils.intersection(fetchedAssets, @loadedAssets).length isnt @loadedAssets.length

  graftByKeypath: (keypath, node, opts={})=>
    for k, v in @pageCache
      @history.pageCache[k] = Breezy.Utils.graftByKeypath(keypath, node, v, opts)

    @currentPage = Breezy.Utils.graftByKeypath(keypath, node, @currentPage, opts)
    Breezy.Utils.triggerEvent Breezy.EVENTS.LOAD, @currentPage
