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
      if let link = url?.string, let resolved = PageText.absolute(link, base: base) {
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

  private static func hasItemprop(_ element: HTMLElement, _ name: String) -> Bool {
    (element.attribute("itemprop") ?? "")
      .split(whereSeparator: { " \t\n\u{0C}\r".contains($0) }).contains { $0 == name }
  }

  private static func nearestScope(_ element: HTMLElement?) -> HTMLElement? {
    element?.inclusiveAncestors.first { $0.hasAttribute("itemscope") }
  }

  /// Elements with an itemprop inside `scope`, not inside a nested item.
  private static func props(_ scope: HTMLElement, _ name: String) -> [HTMLElement] {
    scope.descendants.filter { element in
      hasItemprop(element, name)
        && (nearestScope(element.parent) == scope || nearestScope(element) == scope)
    }
  }

  private static func value(of element: HTMLElement) -> String? {
    let raw =
      element.attribute("content") ?? element.attribute("datetime")
      ?? (element.tagName == "meta" ? nil : element.textContent)
    guard let raw, !raw.isEmpty else { return nil }
    let text = PageText.plain(raw)
    return text.isEmpty ? nil : text
  }

  private static func first(_ scope: HTMLElement, _ name: String) -> String? {
    for element in props(scope, name) {
      if let value = value(of: element) { return value }
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
    let ingredients = (props(scope, "recipeIngredient") + props(scope, "ingredients"))
      .compactMap(value(of:)).map { ExtractedLine(line: $0, section: nil, unsure: false) }
    var steps: [ExtractedStep] = []
    for element in props(scope, "recipeInstructions") {
      let items = element.descendants.filter { $0.tagName == "li" }
      if !items.isEmpty {
        for item in items {
          let text = PageText.plain(item.textContent)
          if !text.isEmpty { steps.append(ExtractedStep(text: text, section: nil, unsure: false)) }
        }
      } else {
        // Paragraphs and line breaks split steps; source newlines are just pretty-printing.
        for part in instructionBreaks.split(element.innerHTML) {
          let text = PageText.plain(part)
          if !text.isEmpty { steps.append(ExtractedStep(text: text, section: nil, unsure: false)) }
        }
      }
    }
    let image = props(scope, "image").first
    let author = props(scope, "author").first
    return ExtractedRecipe(
      title: first(scope, "name"),
      description: first(scope, "description"),
      servings: servings(first(scope, "recipeYield").map(JSONValue.string)),
      prepMinutes: isoMinutes(first(scope, "prepTime").map(JSONValue.string)),
      cookMinutes: isoMinutes(first(scope, "cookTime").map(JSONValue.string)),
      totalMinutes: isoMinutes(first(scope, "totalTime").map(JSONValue.string)),
      author: author.flatMap { $0.hasAttribute("itemscope") ? first($0, "name") : value(of: $0) },
      imageUrl: image.flatMap {
        PageText.absolute(
          $0.attribute("src") ?? $0.attribute("content") ?? $0.attribute("href"), base: base)
      },
      tags: [first(scope, "recipeCuisine"), first(scope, "recipeCategory")].compactMap { $0 },
      ingredients: ingredients,
      steps: steps)
  }
}
