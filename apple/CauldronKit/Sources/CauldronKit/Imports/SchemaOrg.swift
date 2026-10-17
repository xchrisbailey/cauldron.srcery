import Foundation

// schema.org Recipe data, which most recipe sites publish for search engines: JSON-LD first,
// microdata second. Mapped straight to an `ExtractedRecipe`, no model (`schemaOrg.ts`).

enum SchemaOrg {
  // MARK: JSON values

  private static func list(_ value: JSONValue?) -> [JSONValue] {
    switch value {
    case nil, .some(.null): []
    case .some(.array(let items)): items
    case .some(let item): [item]
    }
  }

  /// `a ?? b` over JSON: a missing key and `null` both fall through.
  private static func firstPresent(_ values: JSONValue?...) -> JSONValue? {
    for value in values {
      if let value, value != .null { return value }
    }
    return nil
  }

  private static let typePrefix = JSRegex("^\(JS.dot)*[/:]")

  private static func types(of node: [String: JSONValue]) -> [String] {
    list(node["@type"]).map { typePrefix.replacingFirst(in: $0.jsString, with: "") }
  }

  /// A text value: a string, a number, or a node's name or text.
  static func text(_ value: JSONValue?) -> String? {
    switch value {
    case .some(.string(let string)):
      let text = PageText.plain(string)
      return text.isEmpty ? nil : text
    case .some(.number(let number)): return jsString(number)
    case .some(.array(let items)): return text(items.first)
    case .some(.object(let node)):
      return text(firstPresent(node["name"], node["text"], node["@value"]))
    default: return nil
    }
  }

  /// A whole number from a JavaScript number, held at the largest value anything downstream
  /// accepts anyway, so a hostile "99999999999999999999 servings" can't overflow an `Int`.
  static func saturating(_ x: Double) -> Int {
    guard x.isFinite else { return x < 0 ? 0 : Int(1 << 53) }
    return Int(Swift.min(Swift.max(x, -Double(1 << 53)), Double(1 << 53)))
  }

  // MARK: Durations, servings, nutrition

  private static let number = "[0-9]+(?:\\.[0-9]+)?"
  private static let isoDuration = JSRegex(
    "^P(?:(\(number))Y)?(?:(\(number))M)?(?:(\(number))W)?(?:(\(number))D)?"
      + "(?:T(?:(\(number))H)?(?:(\(number))M)?(?:(\(number))S)?)?\\z", ignoreCase: true)
  private static let hoursText = JSRegex(
    "(?<![0-9])([0-9]{1,3}(?:\\.[0-9]{1,2})?)\(JS.s)*(?:h|hr|hrs|hours?)\(JS.endWord)",
    ignoreCase: true)
  private static let minutesText = JSRegex(
    "(?<![0-9])([0-9]{1,4})\(JS.s)*(?:m|min|mins|minutes?)\(JS.endWord)", ignoreCase: true)

  /// Minutes in an ISO 8601 duration ("PT1H20M", "P0DT45M") or a plain "45 minutes".
  static func isoMinutes(_ value: JSONValue?) -> Int? {
    guard let text = text(value) else { return nil }
    // Durations are short; a long string is junk, and bounds the regexes below.
    if text.jsLength > 64 { return nil }
    if let iso = isoDuration.firstMatch(in: text.jsTrimmed()) {
      func part(_ index: Int) -> Double { iso.group(index).flatMap(Double.init) ?? 0 }
      let total = (part(3) * 7 + part(4)) * 1440 + part(5) * 60 + part(6) + part(7) / 60
      return total.isFinite && total > 0 ? saturating(jsRound(total)) : nil
    }
    let hours = hoursText.firstMatch(in: text)
    let minutes = minutesText.firstMatch(in: text)
    if hours == nil && minutes == nil { return nil }
    let total = jsRound(
      (hours?.group(1).flatMap(Double.init) ?? 0) * 60
        + (minutes?.group(1).flatMap(Double.init) ?? 0))
    return total == 0 ? nil : saturating(total)
  }

  private static let firstDigits = JSRegex("([0-9]+)")

  /// "4 servings", ["4", "4 servings"], 6 or "Makes 12" → the first whole number.
  static func servings(_ value: JSONValue?) -> Int? {
    for item in list(value) {
      if let text = text(item), let digits = firstDigits.firstMatch(in: text)?.group(1) {
        return saturating(Double(digits) ?? .infinity)
      }
    }
    return nil
  }

  private static let thousandsComma = JSRegex("([0-9]),(?=[0-9]{3}(?![0-9]))")
  private static let amountDigits = JSRegex("([0-9]+(?:[.,][0-9]+)?)")

  /// "240 calories", "12 g", 12 → the number. Anything else is unknown.
  static func amount(_ value: JSONValue?) -> Double? {
    guard let text = text(value), text.jsLength <= 64 else { return nil }
    // "1,200 kcal" has a thousands comma; "12,5 g" has a decimal one.
    let withoutThousands = thousandsComma.replacing(in: text) { $0.group(1) ?? "" }
    guard let digits = amountDigits.firstMatch(in: withoutThousands)?.group(1) else { return nil }
    guard let amount = Double(digits.replacingOccurrences(of: ",", with: ".")), amount.isFinite
    else { return nil }
    return amount
  }

  /// schema.org NutritionInformation, which is per serving (`macrosOf`).
  static func macros(_ value: JSONValue?) -> Macros? {
    guard let node = list(value).compactMap(\.object).first else { return nil }
    let macros = Macros(
      calories: amount(node["calories"]), protein: amount(node["proteinContent"]),
      carbs: amount(node["carbohydrateContent"]), fat: amount(node["fatContent"]))
    let known = [macros.calories, macros.protein, macros.carbs, macros.fat].contains { $0 != nil }
    return known ? macros : nil
  }

  // MARK: JSON-LD

  private static func names(_ value: JSONValue?) -> String? {
    let names = list(value).compactMap(text).filter { !$0.isEmpty }
    return names.isEmpty ? nil : names.joined(separator: ", ")
  }

  private static func image(_ value: JSONValue?, base: String) -> String? {
    for item in list(value) {
      let url: JSONValue?
      switch item {
      case .string: url = item
      case .object(let node): url = firstPresent(node["url"], node["contentUrl"])
      default: url = nil
      }
      if let link = url?.string, let resolved = PageText.imageLink(link, base: base) {
        return resolved
      }
    }
    return nil
  }

  private static let stepBreaks = JSRegex(
    "\\n+|<br\(JS.s)*/?>|</p>\(JS.s)*<p>", ignoreCase: true)
  private static let stepNumber = JSRegex("^[0-9]{1,2}[.)]\(JS.s)+")

  /// Steps from a string, a list of strings, HowToSteps, or HowToSections of them.
  private static func steps(_ value: JSONValue?, section: String? = nil) -> [ExtractedStep] {
    var out: [ExtractedStep] = []
    for item in list(value) {
      if case .string(let string) = item {
        // One string can hold the whole method, one step per line.
        for part in stepBreaks.split(string) {
          let text = stepNumber.replacingFirst(in: PageText.plain(part), with: "")
          if !text.isEmpty {
            out.append(ExtractedStep(text: text, section: section, unsure: false))
          }
        }
        continue
      }
      guard case .object(let node) = item else { continue }
      if types(of: node).contains("HowToSection") || node["itemListElement"] != nil {
        let name = text(node["name"])
        out.append(contentsOf: steps(node["itemListElement"], section: name ?? section))
        continue
      }
      if let step = text(node["text"]) ?? text(node["name"]) ?? text(node["description"]) {
        out.append(ExtractedStep(text: step, section: section, unsure: false))
      }
    }
    return out
  }

  private static let doubledNotes = JSRegex("\\(\\(([^()]*)\\)\\)")

  private static func recipe(from node: [String: JSONValue], base: String) -> ExtractedRecipe {
    // WP Recipe Maker wraps notes twice: "4 thighs ((Note 1))".
    let ingredients: [ExtractedLine] = list(
      firstPresent(node["recipeIngredient"], node["ingredients"])
    )
    .compactMap(text).filter { !$0.isEmpty }
    .map { line in
      ExtractedLine(
        line: doubledNotes.replacing(in: line) { "(\($0.group(1) ?? ""))" }, section: nil,
        unsure: false)
    }
    let tags = ["recipeCuisine", "recipeCategory"].flatMap { field in
      list(node[field]).flatMap { value in
        (text(value) ?? "").components(separatedBy: ",").map { $0.jsTrimmed() }
          .filter { !$0.isEmpty }
      }
    }
    return ExtractedRecipe(
      title: text(node["name"]) ?? text(node["headline"]),
      description: text(node["description"]),
      servings: servings(firstPresent(node["recipeYield"], node["yield"])),
      prepMinutes: isoMinutes(node["prepTime"]),
      cookMinutes: isoMinutes(node["cookTime"]),
      totalMinutes: isoMinutes(node["totalTime"]),
      macros: macros(node["nutrition"]),
      author: names(node["author"]),
      siteName: names(node["publisher"]),
      canonicalUrl: node["url"]?.string.flatMap { PageText.absolute($0, base: base) },
      imageUrl: image(firstPresent(node["image"], node["thumbnailUrl"]), base: base),
      tags: tags,
      ingredients: ingredients,
      steps: steps(node["recipeInstructions"]))
  }

  /// Every node in a JSON-LD value: top level, arrays, @graph and nested values.
  private static func nodes(_ value: JSONValue?, depth: Int = 0) -> [[String: JSONValue]] {
    guard depth <= 6 else { return [] }
    var out: [[String: JSONValue]] = []
    for item in list(value) {
      guard case .object(let node) = item else { continue }
      out.append(node)
      for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"]
      where node[key] != nil {
        out.append(contentsOf: nodes(node[key], depth: depth + 1))
      }
    }
    return out
  }

  /// No recipe's JSON-LD comes near this; anything bigger isn't parsed.
  private static let jsonLDMax = 1024 * 1024
  private static let cdata = JSRegex("^\(JS.s)*<!\\[CDATA\\[|\\]\\]>\(JS.s)*\\z")
  private static let comments = JSRegex(
    "(?<![^\(JS.lineBreaks)])[ \\t]*//\(JS.dot)*")

  private static func parseJSON(_ text: String) -> JSONValue? {
    if text.jsLength > jsonLDMax { return nil }
    // [ \t], not \s: \s also matches newlines, which makes this quadratic.
    let cleaned = comments.replacing(in: cdata.replacing(in: text, with: "")) { _ in "" }
      .jsTrimmed()
    if let value = JSONValue.parse(cleaned) { return value }
    // Some sites put raw line breaks inside strings.
    let flattened = JSRegex("[\\n\\r\\t]+").replacing(in: cleaned, with: " ")
    return JSONValue.parse(flattened)
  }

  /// The page's JSON-LD Recipe, or nil. When there are several, the one with the most
  /// ingredients (`jsonLdRecipe`).
  static func jsonLDRecipe(_ document: HTMLDocument, base: String) -> ExtractedRecipe? {
    var best: ExtractedRecipe?
    for script in document.elements
    where script.tagName == "script"
      && script.attribute("type")?.lowercased() == "application/ld+json"
    {
      for node in nodes(parseJSON(script.textContent)) where types(of: node).contains("Recipe") {
        let recipe = recipe(from: node, base: base)
        if best == nil || recipe.ingredients.count > (best?.ingredients.count ?? 0) {
          best = recipe
        }
      }
    }
    return best
  }

  // MARK: Microdata

  /// What a microdata item's properties are, found in one pass over the item: the elements
  /// that carry each `itemprop` word, in document order, not counting those inside a nested
  /// item. (An element belongs to the nearest enclosing `itemscope` above it, so the pass
  /// carries that down instead of walking back up from every element.)
  struct MicrodataItem {
    let scope: HTMLElement
    private(set) var props: [String: [HTMLElement]] = [:]

    init(_ scope: HTMLElement) {
      self.scope = scope
      var stack: [(element: HTMLElement, direct: Bool)] =
        scope.childElements.reversed().map { ($0, true) }
      while let (element, direct) = stack.popLast() {
        if direct, let words = element.attribute("itemprop") {
          var seen: [String] = []
          for word in words.utf8.split(whereSeparator: { Self.isSpace($0) }) {
            let name = String(decoding: word, as: UTF8.self)
            if !seen.contains(name) {
              seen.append(name)
              props[name, default: []].append(element)
            }
          }
        }
        // The children of an element with its own itemscope belong to that item, not this one.
        let childrenDirect = direct && !element.hasAttribute("itemscope")
        for child in element.childElements.reversed() { stack.append((child, childrenDirect)) }
      }
    }

    func props(_ name: String) -> [HTMLElement] { props[name] ?? [] }

    /// The white space that separates the words of an attribute (not a Unicode test).
    private static func isSpace(_ byte: UInt8) -> Bool {
      byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0C || byte == 0x0D
    }
  }

  /// Work a page may cost in node visits across all the text it reads for one item: a real
  /// recipe uses a few thousand, so this is about fifty times what one needs, and a page of
  /// thousands of nested properties (each of which would otherwise read everything below it)
  /// can't make the reading quadratic.
  private static let microdataBudget = 150_000

  private static func value(of element: HTMLElement, work: inout Int) -> String? {
    let raw =
      element.attribute("content") ?? element.attribute("datetime")
      ?? (element.tagName == "meta" ? nil : element.textContent(budget: &work))
    guard let raw, !raw.isEmpty else { return nil }
    let text = PageText.plain(raw)
    return text.isEmpty ? nil : text
  }

  private static func first(_ item: MicrodataItem, _ name: String, work: inout Int) -> String? {
    for element in item.props(name) {
      if let value = value(of: element, work: &work) { return value }
    }
    return nil
  }

  private static let recipeType = JSRegex(
    "schema\\.org/Recipe\(JS.endWord)", ignoreCase: true)
  private static let instructionBreaks = JSRegex("<br\(JS.s)*/?>|</p>|</div>", ignoreCase: true)

  static func microdataRecipe(_ document: HTMLDocument, base: String) -> ExtractedRecipe? {
    guard
      let scope = document.elements.first(where: {
        $0.hasAttribute("itemscope")
          && recipeType.test($0.attribute("itemtype") ?? "")
      })
    else { return nil }
    let item = MicrodataItem(scope)
    var work = microdataBudget
    // Only the first `RecipeLimits.ingredients` ingredients and `RecipeLimits.steps` steps can
    // reach a draft, so reading more would only cost time (a departure from the reference,
    // which read them all and cut later; nothing below those limits differs).
    var ingredients: [ExtractedLine] = []
    for element in item.props("recipeIngredient") + item.props("ingredients") {
      if ingredients.count >= RecipeLimits.ingredients || work <= 0 { break }
      if let line = value(of: element, work: &work) {
        ingredients.append(ExtractedLine(line: line, section: nil, unsure: false))
      }
    }
    var steps: [ExtractedStep] = []
    for element in item.props("recipeInstructions") {
      if steps.count >= RecipeLimits.steps || work <= 0 { break }
      let below = element.descendants(budget: &work)
      let items = below.filter { $0.tagName == "li" }
      if !items.isEmpty {
        for item in items {
          let text = PageText.plain(item.textContent(budget: &work))
          if !text.isEmpty { steps.append(ExtractedStep(text: text, section: nil, unsure: false)) }
        }
      } else {
        // Paragraphs and line breaks split steps; source newlines are just pretty-printing.
        // Writing the markup out costs several times what walking it did.
        work -= below.count * 10
        if work < 0 { break }
        for part in instructionBreaks.split(element.innerHTML) {
          let text = PageText.plain(part)
          if !text.isEmpty { steps.append(ExtractedStep(text: text, section: nil, unsure: false)) }
        }
      }
    }
    let image = item.props("image").first
    let author = item.props("author").first
    var authorName: String?
    if let author {
      authorName =
        author.hasAttribute("itemscope")
        ? first(MicrodataItem(author), "name", work: &work) : value(of: author, work: &work)
    }
    return ExtractedRecipe(
      title: first(item, "name", work: &work),
      description: first(item, "description", work: &work),
      servings: servings(first(item, "recipeYield", work: &work).map(JSONValue.string)),
      prepMinutes: isoMinutes(first(item, "prepTime", work: &work).map(JSONValue.string)),
      cookMinutes: isoMinutes(first(item, "cookTime", work: &work).map(JSONValue.string)),
      totalMinutes: isoMinutes(first(item, "totalTime", work: &work).map(JSONValue.string)),
      author: authorName,
      imageUrl: image.flatMap {
        PageText.imageLink(
          $0.attribute("src") ?? $0.attribute("content") ?? $0.attribute("href"), base: base)
      },
      tags: [
        first(item, "recipeCuisine", work: &work), first(item, "recipeCategory", work: &work),
      ].compactMap { $0 },
      ingredients: ingredients,
      steps: steps)
  }
}
