import Foundation

// From a link or pasted text to a draft: which kind of source it is, the importer for that
// kind, and the draft to review (`distill.ts`, `web.ts`, `social.ts`). Each importer tries its
// readers cheapest first, and fails with a typed reason that has plain copy
// (`Copy.imports.failure`).
//
// Left to the app, because they need the device or belong to the app's data: fetching the cover
// photo at `Distilled.imageUrl`, estimating macros (`Distilled.macroEstimate` is the queue job's
// input), and the duplicate check against the recipes already saved.

/// A recipe ready to open in the editor, and what the app does next with it.
public struct Distilled: Sendable, Hashable {
  public var draft: ImportDraft
  /// Which reader read it.
  public var extractor: DistillExtractor
  /// What was read (page text, caption).
  public var raw: String?
  /// The model call it made, if any.
  public var usage: AIUsage?
  /// True when the on-device model read it because Gemini couldn't be reached. The cook is
  /// told to check it more carefully.
  public var rough: Bool
  /// The cover photo's link, for the app to fetch. The draft's `photoKey` is nil until it has.
  public var imageUrl: String?
  /// What to queue a macro estimate from. Nil when the source gave macros or there is nothing
  /// to estimate from. The app flags `macros` as unsure when it applies the estimate.
  public var macroEstimate: MacroEstimateInput?
}

extension Distill {
  // MARK: Entry points

  /// Reads the recipe at a link: a web page, or an Instagram or TikTok post.
  public static func url(
    _ link: String, fetcher: some PageFetcher, extractor: (any RecipeExtracting)?,
    options: DistillOptions = DistillOptions()
  ) async throws(DistillError) -> Distilled {
    let link = try checkedLink(link)
    return try await withDeadline(options.timeout) { () async throws(DistillError) -> Distilled in
      let source = classify(link)
      let imported: ImportedRecipe
      if source == .web {
        imported = try await fromWeb(link, fetcher, extractor, options)
      } else {
        imported = try await fromSocial(source, link, fetcher, extractor, options)
      }
      return finish(imported, source: source, link: imported.sourceUrl ?? link)
    }
  }

  /// Reads the recipe in pasted text.
  public static func text(
    _ pasted: String, extractor: (any RecipeExtracting)?,
    options: DistillOptions = DistillOptions()
  ) async throws(DistillError) -> Distilled {
    let text = pasted.jsTrimmed()
    if text.isEmpty { throw .failed(.noRecipe) }
    if text.jsLength > textMax { throw .failed(.tooLarge) }
    return try await withDeadline(options.timeout) { () async throws(DistillError) -> Distilled in
      let read = try await fromText(text, kind: .text, extractor: extractor)
      let imported = ImportedRecipe(
        recipe: read.recipe, extractor: read.extractor, raw: nil, usage: read.usage,
        rough: read.rough)
      return finish(imported, source: .text, link: nil)
    }
  }

  private static func finish(_ imported: ImportedRecipe, source: ImportSource, link: String?)
    -> Distilled
  {
    Distilled(
      draft: ImportDraft(
        reading: imported.recipe,
        from: DraftSource(source: source, sourceUrl: link.map(normalizeURL))),
      extractor: imported.extractor, raw: imported.raw, usage: imported.usage,
      rough: imported.rough,
      // Whatever route the link took here, the app is only handed one it may fetch.
      imageUrl: PageText.imageLink(imported.recipe.imageUrl, base: nil),
      macroEstimate: macroEstimateInput(for: imported.recipe))
  }

  // MARK: Deadline

  /// Runs `work`, or fails it as timed out when it takes longer than `timeout`.
  private static func withDeadline<T: Sendable>(
    _ timeout: Duration, _ work: @escaping @Sendable () async throws(DistillError) -> T
  ) async throws(DistillError) -> T {
    let result = await withTaskGroup(of: Result<T, DistillError>.self) { group in
      group.addTask {
        do throws(DistillError) { return .success(try await work()) } catch {
          return .failure(error)
        }
      }
      group.addTask {
        do {
          try await Task.sleep(for: timeout)
          return .failure(.failed(.timeout))
        } catch {
          return .failure(.cancelled)
        }
      }
      let first = await group.next()
      group.cancelAll()
      return first ?? .failure(.cancelled)
    }
    return try result.get()
  }

  // MARK: Text

  /// Reads a recipe from text: asks the model when the text isn't clearly laid out, and falls
  /// back to the text reader's rough reading when the model can't answer (`fromText`).
  static func fromText(
    _ text: String, kind: ExtractKind, extractor: (any RecipeExtracting)?
  ) async throws(DistillError) -> TextRead {
    switch try await readText(planText(text, kind: kind), extractor: extractor) {
    case .success(let read): return read
    case .failure(let failure): throw .failed(failure.code)
    }
  }

  private static func readText(_ plan: TextPlan, extractor: (any RecipeExtracting)?)
    async throws(DistillError) -> Result<TextRead, TextFailure>
  {
    guard case .needsModel(let input, _) = plan else {
      return resolveText(plan, answer: .unavailable)
    }
    guard let extractor else { return resolveText(plan, answer: .unavailable) }
    let answer: ModelAnswer
    do throws(RecipeAIError) {
      answer = .answered(try await extractor.extract(input))
    } catch {
      if error == .cancelled || Task.isCancelled { throw .cancelled }
      answer = ModelAnswer(error)
    }
    return resolveText(plan, answer: answer)
  }

  // MARK: Fetching

  private static let htmlTypes = JSRegex(
    "^(?:text/html|application/xhtml\\+xml|text/plain|application/xml|text/xml)\(JS.endWord)",
    ignoreCase: true)

  /// Where a fetch failure ends up (`fetchFailure`).
  static func failure(_ error: FetchError) -> DistillError {
    switch error {
    case .blocked: .failed(.blocked)
    case .tooLarge: .failed(.tooLarge)
    case .timeout: .failed(.timeout)
    case .cancelled: .cancelled
    case .unreachable, .status: .failed(.couldntRead)
    }
  }

  private static func fetchWithRetries(
    _ request: FetchRequest, _ fetcher: some PageFetcher, _ options: DistillOptions
  ) async throws(DistillError) -> FetchedPage {
    var attempt = 0
    while true {
      do throws(FetchError) {
        return try await fetcher.fetch(request)
      } catch {
        guard error.isTransient, attempt < 2, !Task.isCancelled else { throw failure(error) }
        do {
          try await Task.sleep(for: options.retryDelay * Double(1 << attempt))
        } catch {
          throw .cancelled
        }
        attempt += 1
      }
    }
  }

  /// Fetches a page, retrying twice on errors that may pass. A response that isn't a page, or
  /// that came from somewhere that isn't an http(s) link, is refused (`fetchPage`).
  static func fetchPage(
    _ url: String, _ fetcher: some PageFetcher, _ options: DistillOptions
  ) async throws(DistillError) -> (html: String, url: String) {
    let request = FetchRequest(
      url: url, maxBytes: options.maxPageBytes,
      accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5")
    let page = try await fetchWithRetries(request, fetcher, options)
    if page.bytes.count > options.maxPageBytes { throw .failed(.tooLarge) }
    // Where the page came from becomes the recipe's source link, so it has to be an http(s)
    // link with no credentials in it; anything else a fetcher reports is refused.
    guard let finalURL = WebURL.parse(page.url), finalURL.username.isEmpty,
      finalURL.password.isEmpty
    else { throw .failed(.blocked) }
    if let contentType = page.contentType, !htmlTypes.test(contentType) {
      throw .failed(.couldntRead)
    }
    return (Charset.decodeHTML(page.bytes, contentType: page.contentType), page.url)
  }

  // MARK: Web

  static func fromWeb(
    _ url: String, _ fetcher: some PageFetcher, _ extractor: (any RecipeExtracting)?,
    _ options: DistillOptions
  ) async throws(DistillError) -> ImportedRecipe {
    let page = try await fetchPage(url, fetcher, options)
    var read = try await fromHTML(page.html, url: page.url, extractor: extractor)
    read.sourceUrl = read.recipe.canonicalUrl ?? page.url
    return read
  }

  /// Reads a recipe from a page's HTML. Exposed for the fixture tests, which have no network
  /// (`fromHtml`).
  static func fromHTML(_ html: String, url: String, extractor: (any RecipeExtracting)?)
    async throws(DistillError) -> ImportedRecipe
  {
    switch readPage(html: html, url: url) {
    case .complete(let imported):
      return imported
    case .needsText(let request):
      switch try await readText(request.plan, extractor: extractor) {
      case .success(let text):
        return request.merging(text)
      case .failure(let failure):
        // Ingredients without a method are still worth reviewing.
        if let fallback = request.fallback(after: failure.code) { return fallback }
        throw .failed(failure.code)
      }
    }
  }

  // MARK: Social

  private static let siteNames: [ImportSource: String] = [
    .instagram: "Instagram", .tiktok: "TikTok",
  ]

  /// Finds the post behind a link (share links redirect) and reads its caption (`capturePost`).
  static func capturePost(
    _ source: ImportSource, _ url: String, _ fetcher: some PageFetcher, _ options: DistillOptions
  ) async throws(DistillError) -> (post: String, capture: SocialCapture) {
    var page: (html: String, url: String)?
    var post = Social.canonicalPost(source, url)
    if post == nil {
      // A share link ("vm.tiktok.com/…", "instagram.com/share/…"): follow it.
      let followed = try await fetchPage(url, fetcher, options)
      page = followed
      // A logged-out visit can land on "/accounts/login/?next=/reel/ID/".
      guard let landed = WebURL.parse(followed.url) else { throw .failed(.couldntRead) }
      post = Social.canonicalPost(source, followed.url)
      if post == nil, let next = landed.searchParam("next"), !next.isEmpty,
        let target = WebURL.parse(next, base: landed)
      {
        post = Social.canonicalPost(source, target.string)
      }
      if post == nil { throw .failed(.couldntRead) }
    }
    guard let post else { throw .failed(.couldntRead) }
    var embedded: SocialCapture?
    if let endpoint = Social.oEmbedURL(source, post: post) {
      do throws(FetchError) {
        let response = try await fetcher.fetch(
          FetchRequest(url: endpoint, maxBytes: 512 * 1024, accept: "application/json"))
        embedded = Social.fromOEmbed(
          Charset.decode(response.bytes, label: "utf-8") ?? "", base: post)
      } catch {
        // A missing or private post fails here too; the page may still say more.
        if case .blocked = error { throw failure(error) }
        if case .cancelled = error { throw .cancelled }
      }
    }
    if let embedded, let caption = embedded.caption, !caption.isEmpty { return (post, embedded) }
    let loaded: (html: String, url: String)
    if let page { loaded = page } else { loaded = try await fetchPage(post, fetcher, options) }
    let graph = Social.fromOpenGraph(loaded.html, source: source, base: post)
    return (
      post,
      SocialCapture(
        caption: graph?.caption, author: embedded?.author ?? graph?.author,
        imageUrl: embedded?.imageUrl ?? graph?.imageUrl)
    )
  }

  static func fromSocial(
    _ source: ImportSource, _ url: String, _ fetcher: some PageFetcher,
    _ extractor: (any RecipeExtracting)?, _ options: DistillOptions
  ) async throws(DistillError) -> ImportedRecipe {
    let (post, capture) = try await capturePost(source, url, fetcher, options)
    // No caption at all: whatever the recipe is, it's in the video.
    guard let caption = capture.caption, !caption.isEmpty else { throw .failed(.spokenOnly) }
    let plan = planText(caption, kind: .caption)
    let answered = try await readText(plan, extractor: extractor)
    let read: TextRead
    switch answered {
    case .success(let value):
      read = value
    case .failure(let failure):
      // Only a model can tell a caption without a recipe from one it can't lay out; without
      // one, it's "no recipe found", not "spoken in the video".
      let code: ImportFailureCode =
        failure.code == .noRecipe && failure.modelAnswered ? .spokenOnly : failure.code
      throw .failed(code, raw: caption)
    }
    var recipe = read.recipe
    recipe.author = capture.author ?? recipe.author
    recipe.siteName = siteNames[source]
    recipe.imageUrl = capture.imageUrl
    recipe.canonicalUrl = post
    return ImportedRecipe(
      recipe: recipe, extractor: read.extractor, raw: caption, usage: read.usage,
      sourceUrl: post, rough: read.rough)
  }
}
