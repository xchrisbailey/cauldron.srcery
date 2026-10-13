import Foundation

// The decisions the import pipeline makes, as pure functions: which links are accepted, what
// kind of source a link is, what was read without a model and whether a model is needed, how
// a model's answer is combined with what the page already gave, and which failure code a
// failed read ends as (`distill.ts`, `fromText.ts`, `web.ts`). The async entry points in
// `Distill.swift` only fetch and ask, and apply these.

/// Which reader read a recipe.
public enum DistillExtractor: String, Sendable, Hashable, Codable, CaseIterable {
  case jsonLD = "json-ld"
  case microdata
  /// The text reader, no model.
  case text
  case model
}

/// A recipe as an importer read it, with where it came from (`Imported` in the reference).
public struct ImportedRecipe: Sendable, Hashable {
  public var recipe: ExtractedRecipe
  public var extractor: DistillExtractor
  /// What was read (page text, caption), for a "show what was read" detail. Nil when the page's
  /// own data was enough, or the text was pasted.
  public var raw: String?
  public var usage: AIUsage?
  /// The link to record on the recipe: the page's canonical link when it has one.
  public var sourceUrl: String?
  /// True when the on-device model read it because Gemini couldn't be reached, so the cook
  /// should check it more carefully.
  public var rough: Bool

  public init(
    recipe: ExtractedRecipe, extractor: DistillExtractor, raw: String? = nil,
    usage: AIUsage? = nil, sourceUrl: String? = nil, rough: Bool = false
  ) {
    self.recipe = recipe
    self.extractor = extractor
    self.raw = raw
    self.usage = usage
    self.sourceUrl = sourceUrl
    self.rough = rough
  }
}

extension ExtractedRecipe {
  /// Enough of a recipe to be worth opening in the editor: some ingredients and some method
  /// (`hasRecipe`).
  public var hasRecipe: Bool { !ingredients.isEmpty && !steps.isEmpty }
}

public enum Distill {
  // MARK: Links

  /// Pasted text: about 20 pages, far more than any recipe (`IMPORT_TEXT_MAX`).
  public static let textMax = 50_000

  private static let sourceLink = JSRegex(
    "^https?://[^\(JS.space)/]+[^\(JS.space)]*\\z", ignoreCase: true)

  /// The link to read, or the failure for one that isn't: http or https only, no credentials
  /// in it, at most `RecipeLimits.url` long. A link the field's own check let through can't
  /// fail here; the rest are `blocked`.
  static func checkedLink(_ raw: String) throws(DistillError) -> String {
    let link = raw.jsTrimmed()
    guard link.jsLength <= RecipeLimits.url, sourceLink.test(link),
      let url = WebURL.parse(link), url.username.isEmpty, url.password.isEmpty
    else { throw .failed(.blocked) }
    return link
  }

  /// Whether `raw` is a link the importers will open.
  public static func isAcceptedLink(_ raw: String) -> Bool {
    (try? checkedLink(raw)) != nil
  }

  /// The platform a host belongs to, or nil for any other site (`socialHost`).
  static func socialPlatform(host: String) -> ImportSource? {
    let host = host.lowercased()
    func isHost(_ name: String) -> Bool { host == name || host.hasSuffix("." + name) }
    if isHost("instagram.com") || isHost("instagr.am") { return .instagram }
    if isHost("tiktok.com") { return .tiktok }
    return nil
  }

  /// What kind of source a link is, from its host: `.web`, `.instagram` or `.tiktok`
  /// (`classify`).
  public static func classify(_ url: String) -> ImportSource {
    guard let host = WebURL.parse(url)?.host else { return .web }
    return socialPlatform(host: host) ?? .web
  }

  private static func isTrackingName(_ name: String) -> Bool {
    let lowered = name.lowercased()
    if lowered.hasPrefix("utm_") {
      return !name.unicodeScalars.dropFirst(4).contains { JS.lineBreakScalars.contains($0) }
    }
    return ["fbclid", "gclid", "igshid", "igsh", "mc_cid", "mc_eid", "ref", "ref_src", "si", "s"]
      .contains(lowered)
  }

  /// A link without the parts that don't change the page (fragment, tracking parameters, a
  /// trailing slash, the host's case), so the same recipe is recognised however it was shared
  /// (`normalizeUrl`).
  public static func normalizeURL(_ raw: String) -> String {
    guard let url = WebURL.parse(raw) else { return raw }
    return url.withoutFragment().removingParams(where: isTrackingName).withoutTrailingSlashes()
      .string
  }

  // MARK: Text

  /// What the text reader makes of a text, and whether a model is needed.
  public enum TextPlan: Sendable, Hashable {
    /// Clearly laid out: read without a model.
    case clear(ExtractedRecipe)
    /// Ask a model with `input`. If there is none, or it fails, `rough` is the fallback: a
    /// reading of text with no clear layout, flagged for review (nil when there isn't one).
    case needsModel(ExtractInput, rough: ExtractedRecipe?)
  }

  /// Reads a recipe from text: a paste, a page's readable text or a caption. A page's text
  /// carries navigation and comments, so it goes to the model even when it reads cleanly
  /// (`fromText`).
  public static func planText(_ text: String, kind: ExtractKind) -> TextPlan {
    let reading = TextRecipe.read(text)
    if let reading, reading.clarity == .clear, kind != .page { return .clear(reading.recipe) }
    let rough = reading.flatMap { $0.recipe.hasRecipe ? $0.recipe : nil }
    return .needsModel(ExtractInput(text: text, kind: kind), rough: rough)
  }

  /// What a model said to a text.
  public enum ModelAnswer: Sendable, Hashable {
    /// There is no model to ask.
    case unavailable
    /// The model was asked and failed. A cancelled request is not an answer; the caller stops
    /// instead of resolving it.
    case failed(RecipeAIError)
    case answered(Extraction)

    /// Sorts the outcome of a model call: no key means no model.
    public init(_ error: RecipeAIError) {
      self = error == .missingKey ? .unavailable : .failed(error)
    }
  }

  /// A text read: what, and by which reader.
  public struct TextRead: Sendable, Hashable {
    public var recipe: ExtractedRecipe
    public var extractor: DistillExtractor
    public var usage: AIUsage?
    public var rough: Bool
  }

  /// A text that gave no recipe, and whether a model looked at it (for a caption, a model
  /// that found nothing means the recipe is in the video).
  public struct TextFailure: Error, Sendable, Hashable {
    public var code: ImportFailureCode
    public var modelAnswered: Bool
  }

  /// The plan for a text, once the model has answered (or there was none to ask)
  /// (`fromText`, after the model call).
  public static func resolveText(_ plan: TextPlan, answer: ModelAnswer) -> Result<
    TextRead, TextFailure
  > {
    let rough: ExtractedRecipe?
    switch plan {
    case .clear(let recipe):
      return .success(TextRead(recipe: recipe, extractor: .text, usage: nil, rough: false))
    case .needsModel(_, let reading):
      rough = reading
    }
    // The text reader's rough reading is better than nothing when the model is out of reach.
    let roughRead = rough.map { TextRead(recipe: $0, extractor: .text, usage: nil, rough: false) }
    switch answer {
    case .unavailable:
      if let roughRead { return .success(roughRead) }
      return .failure(TextFailure(code: .noRecipe, modelAnswered: false))
    case .failed:
      if let roughRead { return .success(roughRead) }
      return .failure(TextFailure(code: .unavailable, modelAnswered: false))
    case .answered(let extraction):
      if extraction.outcome == .inVideo {
        return .failure(TextFailure(code: .spokenOnly, modelAnswered: true))
      }
      if extraction.outcome == .missing || !extraction.recipe.hasRecipe {
        return .failure(TextFailure(code: .noRecipe, modelAnswered: true))
      }
      return .success(
        TextRead(
          recipe: extraction.recipe, extractor: .model, usage: extraction.usage,
          rough: extraction.rough))
    }
  }

  // MARK: Pages

  /// A page's readable text is cut to this before it reaches the model (`MODEL_INPUT_MAX`).
  static let modelInputMax = AIPrompts.modelInputMax

  /// What reading a page without a model came to.
  public enum PageReading: Sendable, Hashable {
    /// The page's own recipe data was complete: no model.
    case complete(ImportedRecipe)
    /// Its recipe data is missing or thin. Read the page's text instead.
    case needsText(PageTextRequest)
  }

  /// A page whose recipe data is missing or thin: the text to read, and what the page did give.
  public struct PageTextRequest: Sendable, Hashable {
    /// The readable text, without scripts, navigation and comments, cut to what a model takes.
    public let text: String
    let structured: ExtractedRecipe?
    let structuredExtractor: DistillExtractor
    let meta: PageMeta
    let url: String

    /// The plan for the text: always `ExtractKind.page`, so it goes to a model.
    public var plan: TextPlan { planText(text, kind: .page) }

    /// Combines what was read from the text with what the page already gave. The model reads
    /// the method; the titles and photos from the page's own data win.
    public func merging(_ read: TextRead) -> ImportedRecipe {
      var recipe = read.recipe
      if let structured {
        recipe.title = structured.title ?? recipe.title
        recipe.description = structured.description ?? recipe.description
        recipe.servings = structured.servings ?? recipe.servings
        recipe.prepMinutes = structured.prepMinutes ?? recipe.prepMinutes
        recipe.cookMinutes = structured.cookMinutes ?? recipe.cookMinutes
        recipe.totalMinutes = structured.totalMinutes ?? recipe.totalMinutes
        recipe.macros = structured.macros ?? recipe.macros
        recipe.author = structured.author ?? recipe.author
        recipe.siteName = structured.siteName ?? recipe.siteName
        recipe.canonicalUrl = structured.canonicalUrl ?? recipe.canonicalUrl
        recipe.imageUrl = structured.imageUrl ?? recipe.imageUrl
        recipe.notes = structured.notes ?? recipe.notes
        if !structured.tags.isEmpty { recipe.tags = structured.tags }
      }
      return ImportedRecipe(
        recipe: Distill.withMeta(recipe, meta, url: url), extractor: read.extractor, raw: text,
        usage: read.usage, rough: read.rough)
    }

    /// What to open when the text couldn't be read: ingredients without a method are still
    /// worth reviewing. Nil when the page gave none, or the failure was a timeout.
    public func fallback(after failure: ImportFailureCode) -> ImportedRecipe? {
      guard let structured, !structured.ingredients.isEmpty, failure != .timeout else {
        return nil
      }
      var recipe = structured
      recipe.unsure = [.title]
      return ImportedRecipe(
        recipe: Distill.withMeta(recipe, meta, url: url), extractor: structuredExtractor,
        raw: text)
    }
  }

  private static func site(_ href: String) -> String? {
    guard var host = WebURL.parse(href)?.host else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host
  }

  /// A canonical link only counts when it's on the page's own site (or one of its
  /// subdomains), so a page can't make its recipe credit somewhere else (`sameSite`).
  static func sameSite(_ canonical: String?, _ page: String) -> String? {
    guard let canonical, !canonical.isEmpty, let a = site(canonical), let b = site(page)
    else { return nil }
    return a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a) ? canonical : nil
  }

  /// Fills what the recipe data left out from the page's own metadata (`withMeta`).
  static func withMeta(_ recipe: ExtractedRecipe, _ meta: PageMeta, url: String) -> ExtractedRecipe
  {
    var out = recipe
    out.title = recipe.title ?? meta.title
    out.description = recipe.description ?? meta.description
    out.author = recipe.author ?? meta.author
    out.siteName = recipe.siteName ?? meta.siteName ?? site(url) ?? ""
    out.imageUrl = recipe.imageUrl ?? meta.imageUrl
    out.canonicalUrl = sameSite(meta.canonicalUrl, url) ?? sameSite(recipe.canonicalUrl, url)
    return out
  }

  /// Reads a page's HTML: schema.org recipe data first (JSON-LD, then microdata), with no
  /// model. A page without it, or with a thin version (no ingredients or no method), has its
  /// readable text handed back to be read as text (`fromHtml`).
  public static func readPage(html: String, url: String) -> PageReading {
    let document = HTMLDocument(html)
    let meta = PageText.pageMeta(document, base: url)
    // A stub JSON-LD Recipe (a name and a photo) doesn't hide full microdata.
    let jsonLD = SchemaOrg.jsonLDRecipe(document, base: url)
    let microdata =
      (jsonLD?.hasRecipe ?? false) ? nil : SchemaOrg.microdataRecipe(document, base: url)
    let useMicrodata = microdata != nil && ((microdata?.hasRecipe ?? false) || jsonLD == nil)
    let structured = useMicrodata ? microdata : jsonLD
    let extractor: DistillExtractor = useMicrodata ? .microdata : .jsonLD
    if let structured, structured.hasRecipe {
      return .complete(
        ImportedRecipe(recipe: withMeta(structured, meta, url: url), extractor: extractor))
    }
    return .needsText(
      PageTextRequest(
        text: PageText.readable(document, max: modelInputMax), structured: structured,
        structuredExtractor: extractor, meta: meta, url: url))
  }

  // MARK: Macros

  /// What to estimate macros from, for a recipe whose source gave no nutrition: its ingredient
  /// lines and yield. Nil when the source gave macros or there are no ingredient lines. The
  /// reference estimated inline; on the device the estimate is queued until the model can be
  /// reached (`withMacros`).
  public static func macroEstimateInput(for recipe: ExtractedRecipe) -> MacroEstimateInput? {
    let lines = recipe.ingredients.map { $0.line.jsTrimmed().jsPrefix(RecipeLimits.line) }
      .filter { !$0.isEmpty }.prefix(RecipeLimits.ingredients)
    if recipe.macros != nil || lines.isEmpty { return nil }
    let servings = recipe.servings.flatMap { (1...RecipeLimits.servings).contains($0) ? $0 : nil }
    return MacroEstimateInput(
      title: recipe.title?.jsPrefix(RecipeLimits.title), servings: servings,
      ingredients: Array(lines))
  }
}
