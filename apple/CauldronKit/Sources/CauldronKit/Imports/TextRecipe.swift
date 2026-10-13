import Foundation

// Reads a recipe out of plain text without a model: a paste, or a caption (`textRecipe.ts`).
// Most recipes people paste are laid out with an "Ingredients" heading and a "Method" heading,
// and those read reliably here at no cost. Text without those headings gets a rougher
// reading, flagged for review, that importers only use when no model is available.
//
// The patterns are the reference's, run on ICU with `\s`, `\d`, `\w`, `\b`, `.` and `$` spelled
// the JavaScript way (see `JSRegex`). Two differences remain that no ordinary text meets: ICU
// counts a code point where JavaScript counts UTF-16 units in the `{n,m}` quantifiers of
// `inlineHeading` and `chatPrefix`, and its `/i` folds a few non-ASCII letters (the Kelvin
// sign, long s) onto ASCII ones.

enum Clarity: Sendable, Hashable {
  case clear
  case rough
}

struct TextReading: Sendable, Hashable {
  var clarity: Clarity
  var recipe: ExtractedRecipe
}

enum TextRecipe {
  private static let pictographic = #"\p{Extended_Pictographic}\x{FE0F}\x{200D}"#

  // Decoration around a heading: markdown, bullets, emoji, trailing colons.
  private static let leadingDecoration = JSRegex(
    "^[\(JS.space)#*_>•\\-–—=~|▢□◦‣\(pictographic)]+")
  private static let trailingDecoration = JSRegex(
    "[\(JS.space)#*_:：=~|\(pictographic)]+\\z")

  private static func bare(_ line: String) -> String {
    trailingDecoration.replacing(in: leadingDecoration.replacing(in: line, with: ""), with: "")
      .jsTrimmed()
  }

  private static let ingredientsHeading = JSRegex(
    "^(?:the\(JS.s)+)?(?:ingredients?(?:\(JS.s)+list)?|what\(JS.s)+you(?:'|’)?ll\(JS.s)+need"
      + "|what\(JS.s)+you\(JS.s)+need|you(?:'|’)?ll\(JS.s)+need|you\(JS.s)+will\(JS.s)+need"
      + "|shopping\(JS.s)+list|for\(JS.s)+the\(JS.s)+recipe)\\z", ignoreCase: true)
  private static let methodHeading = JSRegex(
    "^(?:the\(JS.s)+)?(?:method|directions?|instructions?|steps?|preparation"
      + "|prep(?:aration)?\(JS.s)+steps?|how\(JS.s)+to(?:\(JS.s)+(?:make|cook)"
      + "(?:\(JS.s)+(?:it|this|them))?)?|to\(JS.s)+make|recipe\(JS.s)+steps?)\\z",
    ignoreCase: true)
  private static let notesHeading = JSRegex(
    "^(?:notes?|tips?|cook(?:'|’)?s\(JS.s)+notes?|recipe\(JS.s)+notes?|storage|to\(JS.s)+store"
      + "|make\(JS.s)+ahead|substitutions?|variations?)\\z", ignoreCase: true)

  // "Ingredients: 2 eggs, flour" puts content on the heading line itself.
  private static let inlineHeading = JSRegex("^([^:：]{3,40})[:：]\(JS.s)*(\(JS.dot)+)\\z")

  private static let bullet = JSRegex(
    "^\(JS.s)*(?:[\\-•*▢□◦‣–—]|[0-9]{1,2}[.)](?=\(JS.s))|[0-9]{1,2}\\x{FE0F}?\\x{20E3}"
      + "|step\(JS.s)*[0-9]{1,2}\(JS.s)*[.:)\\-]?)\(JS.s)*", ignoreCase: true)
  private static let hashtags = JSRegex("(?:^|[\(JS.space)])#[\\p{L}\\p{N}_]+")

  private static let servings = JSRegex(
    "^(?:serves|servings?|yield|yields|makes|portions?)\(JS.s)*[:：\\-]?\(JS.s)*"
      + "(?:about\(JS.s)+)?([0-9]{1,3})(?:\(JS.s)*(?:-|–|to)\(JS.s)*[0-9]{1,3})?\(JS.endWord)",
    ignoreCase: true)
  private static let servingsAfter = JSRegex(
    "^([0-9]{1,3})(?:\(JS.s)*(?:-|–|to)\(JS.s)*[0-9]{1,3})?\(JS.s)+(?:servings?|portions?|people)"
      + JS.endWord, ignoreCase: true)
  private static let time = JSRegex(
    "^(prep(?:aration)?|cook(?:ing)?|bake|baking|total|ready\(JS.s)+in)(?:\(JS.s)+time)?"
      + "\(JS.s)*[:：\\-]?\(JS.s)*(\(JS.dot)+)\\z", ignoreCase: true)

  // What is left of a time line once the label is gone: only a duration.
  private static let duration = JSRegex(
    "^(?:about\(JS.s)+|approx\\.?\(JS.s)+)?[0-9½¼¾.,\(JS.space)\\-–]+"
      + "(?:\(JS.s)*(?:hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|and|to)\(JS.endWord)"
      + "[0-9½¼¾.,\(JS.space)\\-–]*)*\\z", ignoreCase: true)

  private static let metaSeparators = JSRegex("\(JS.s)*[|•·,;]\(JS.s)*")

  /// Minutes in a duration like "1 hr 20 mins", or nil.
  static func parseMinutes(_ text: String) -> Int? {
    detectTimer(text).map { Int(jsRound(Double($0) / 60)) }
  }

  struct Meta {
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
  }

  /// Reads a "Serves 4" or "Prep: 10 min" line into `meta`. True when it was one.
  private static func readMeta(_ line: String, _ meta: inout Meta) -> Bool {
    // "Prep 10 min | Cook 20 min" packs several on one line.
    let parts = metaSeparators.split(line).filter { !$0.isEmpty }
    var matched = 0
    for part in parts {
      let text = bare(part)
      if let found = servings.firstMatch(in: text) ?? servingsAfter.firstMatch(in: text) {
        if meta.servings == nil { meta.servings = found.group(1).flatMap { Int($0) } }
        matched += 1
        continue
      }
      // "Bake at 200C for 10 minutes." is a step; "Bake: 10 minutes" is metadata.
      guard let found = time.firstMatch(in: text), let rest = found.group(2),
        duration.test(rest), let minutes = parseMinutes(rest), let label = found.group(1)
      else { continue }
      let kind = label.lowercased()
      if kind.hasPrefix("prep") {
        if meta.prepMinutes == nil { meta.prepMinutes = minutes }
      } else if kind.hasPrefix("total") || kind.hasPrefix("ready") {
        if meta.totalMinutes == nil { meta.totalMinutes = minutes }
      } else if meta.cookMinutes == nil {
        meta.cookMinutes = minutes
      }
      matched += 1
    }
    return matched > 0 && matched == parts.count
  }

  private enum Block { case intro, ingredients, method, notes }

  private static func heading(of line: String) -> Block? {
    let text = bare(line)
    if ingredientsHeading.test(text) { return .ingredients }
    if methodHeading.test(text) { return .method }
    if notesHeading.test(text) { return .notes }
    return nil
  }

  private static let ingredientWords = JSRegex(
    "^(?:salt|pepper|oil|water|a\(JS.s)+(?:pinch|handful|splash|knob|drizzle)"
      + "|juice\(JS.s)+of|zest\(JS.s)+of|zest|pinch\(JS.s)+of)\(JS.endWord)", ignoreCase: true)

  /// A line that reads as an ingredient: it starts with an amount, or is short with no
  /// sentence in it.
  private static func looksLikeIngredient(_ line: String) -> Bool {
    if parseIngredientLine(line).quantity != nil { return true }
    return ingredientWords.test(line)
  }

  private static func clean(_ line: String) -> String {
    hashtags.replacing(in: line, with: " ").jsSpacesCollapsed().jsTrimmed()
  }

  // Sign-offs and blog calls to action after the last step.
  private static let trailer = JSRegex(
    "^(?:love\(JS.endWord)|cheers\(JS.endWord)|thanks\(JS.endWord)|regards\(JS.endWord)"
      + "|best\(JS.s)*,|xx?o?\(JS.endWord)|enjoy\(JS.endWord)|did\(JS.s)+you\(JS.s)+make"
      + "|tag\(JS.s)+me|follow\(JS.s)+me|let\(JS.s)+me\(JS.s)+know"
      + "|leave\(JS.s)+a\(JS.s)+(?:comment|review))", ignoreCase: true)

  // Calls to action that close a caption: "Save this for later!", "Follow @x for more". Each
  // needs its social tail, so "Save it in an airtight tin" stays.
  private static let callToAction = JSRegex(
    "^(?:save\(JS.s)+(?:this|it)\(JS.s)+(?:for\(JS.s)+later|recipe|post|reel)\(JS.endWord)"
      + "|follow\(JS.s)+(?:@[^\(JS.space)]+|me|us)\(JS.s)*(?:for\(JS.endWord)|[!.]|\\z)"
      + "|like\(JS.s)*(?:,|and|&)\(JS.s)*(?:save|share|follow)\(JS.endWord)"
      + "|share\(JS.s)+(?:this|it)\(JS.s)+with\(JS.s)+(?:a\(JS.s)+friend|someone|your)"
      + "\(JS.endWord)"
      + "|tag\(JS.s)+(?:a|your|someone)\(JS.endWord)\(JS.dot)*(?:friend|who|bestie)"
      + "|turn\(JS.s)+on\(JS.s)+(?:post\(JS.s)+)?notifications"
      + "|comment\(JS.s)+[\"“'‘]?[\(JS.word)]+[\"”'’]?\(JS.s)+(?:for|and)\(JS.endWord))",
    ignoreCase: true)

  private static func isCallToAction(_ line: String) -> Bool { callToAction.test(bare(line)) }

  private static let numberedStep = JSRegex(
    "^\(JS.s)*(?:[0-9]{1,2}[.)]|[0-9]{1,2}\\x{FE0F}?\\x{20E3}|step\(JS.s)*[0-9])",
    ignoreCase: true)
  private static let blankLine = JSRegex("\\n\(JS.s)*\\n")
  private static let wholeSentence = JSRegex("^[\\p{Lu}0-9]\(JS.dot)*[.!?]\\z")

  /// Splits a method block into steps: numbered steps, then blank lines, then one per line.
  private static func splitSteps(_ lines: [String]) -> [String] {
    let numbered = lines.filter { numberedStep.test($0) }.count
    if numbered >= 2 {
      var steps: [String] = []
      for line in lines {
        if line.jsTrimmed().isEmpty { continue }
        if numberedStep.test(line) || steps.isEmpty {
          steps.append(bullet.replacingFirst(in: line, with: "").jsTrimmed())
        } else {
          steps[steps.count - 1] = "\(steps[steps.count - 1]) \(line.jsTrimmed())"
        }
      }
      return steps.filter { !$0.isEmpty }
    }
    let joined = lines.joined(separator: "\n").jsTrimmed()
    let chunks =
      blankLine.test(joined) ? blankLine.split(joined) : joined.components(separatedBy: "\n")
    return chunks.flatMap { chunk -> [String] in
      let parts = chunk.components(separatedBy: "\n").map {
        bullet.replacingFirst(in: $0, with: "").jsTrimmed()
      }
      // A paragraph of whole sentences, one per line, is several steps; a line that continues
      // in lower case is a hard-wrapped one.
      let sentences = parts.count > 1 && parts.allSatisfy { wholeSentence.test($0) }
      return sentences ? parts : [parts.joined(separator: " ").jsTrimmed()]
    }.filter { !$0.isEmpty }
  }

  private static let ingredientBullets = JSRegex(
    "^[\(JS.space)\\-•*▢□◦‣–—\(pictographic)]+")

  private static func ingredients(_ lines: [String], unsure: Bool) -> [ExtractedLine] {
    // Bullets, and the emoji captions use as bullets (✨ ▪️ ✔️).
    readIngredientBlock(lines.map { ingredientBullets.replacing(in: $0, with: "") }).map {
      ExtractedLine(line: $0.parsed.original, section: $0.section, unsure: unsure)
    }
  }

  private static let endsInPunctuation = JSRegex("[.!?]\\z")

  private static func steps(_ lines: [String], unsure: Bool) -> [ExtractedStep] {
    var out: [ExtractedStep] = []
    var groups: [(section: String?, lines: [String])] = [(nil, [])]
    for line in lines {
      let text = line.jsTrimmed()
      if !text.isEmpty, isSectionHeading(text), !endsInPunctuation.test(text),
        text.jsLength < 40
      {
        var name = bare(text)
        if name.hasSuffix(":") { name.removeLast() }
        name = name.jsTrimmed()
        groups.append((name.isEmpty ? nil : name, []))
        continue
      }
      groups[groups.count - 1].lines.append(line)
    }
    for group in groups {
      for text in splitSteps(group.lines) {
        out.append(ExtractedStep(text: text, section: group.section, unsure: unsure))
      }
    }
    return out
  }

  // Lines above the recipe that aren't part of it: email headers, page chrome.
  private static let headerLine = JSRegex(
    "^(?:from|to|cc|bcc|date|sent)\(JS.s)*:", ignoreCase: true)
  // Page chrome is a whole short line ("Home » Recipes", "Home Recipes About Shop", "Print",
  // "Posted on May 3"), never the start of a real title like "Home-style chili".
  private static let pageJunk = JSRegex(
    "^(?:(?:home|menu|print|share|pin|save|subscribe|advertisement|sponsored)"
      + "(?:\(JS.s)*[»>›/|]\(JS.dot)*)?|home(?:\(JS.s)+\\p{Lu}[\\p{L}&]*){3,}"
      + "|skip\(JS.s)+to\(JS.endWord)\(JS.dot)*|jump\(JS.s)+to\(JS.endWord)\(JS.dot)*"
      + "|posted\(JS.s)+(?:on|by)\(JS.endWord)\(JS.dot)*|sign\(JS.s)+up\(JS.endWord)\(JS.dot)*"
      + "|[0-9]+\(JS.s)+comments?)\\z", ignoreCase: true)
  // Chat exports start each message with "[12:41, 3/9/2026] Sam:". Chatter around the recipe
  // ("ok here is the recipe") is never its title.
  private static let chatPrefix = JSRegex("^\\[[^\\]]{4,40}\\]\(JS.s)*[^:]{1,30}:\(JS.s)*")
  // Only when the line reads as talk (ends in punctuation or mentions the recipe), so "So easy
  // lemon cake" stays a title.
  private static let chatter = JSRegex(
    "^(?:ok(?:ay)?|hi|hey|hello|here(?:'|’)?s|here\(JS.s)+is|so|thanks|sure)\(JS.endWord)"
      + "(?=\(JS.dot)*(?:[:.!?,]\\z|\(JS.startWord)recipe\(JS.endWord)))", ignoreCase: true)
  private static let subject = JSRegex("^subject\(JS.s)*:\(JS.s)*", ignoreCase: true)
  private static let notATitle = JSRegex(
    "^(?:recipe|by\(JS.s)|from\(JS.s)|https?:)", ignoreCase: true)
  private static let recipePrefix = JSRegex("^recipe\(JS.s)*[:：\\-]\(JS.s)*", ignoreCase: true)

  /// A title is a short first line that isn't metadata or a heading.
  private static func pickTitle(_ intro: [String], _ meta: inout Meta) -> (
    title: String?, description: String?
  ) {
    let lines = intro.map {
      subject.replacingFirst(in: chatPrefix.replacingFirst(in: clean($0), with: ""), with: "")
    }.filter {
      !$0.isEmpty && !headerLine.test($0) && !pageJunk.test($0) && !chatter.test($0)
    }
    var title: String?
    var rest: [String] = []
    for line in lines {
      if readMeta(line, &meta) { continue }
      let text = bare(line)
      if title == nil, !text.isEmpty, text.jsLength <= 120, !endsInPunctuation.test(text),
        !notATitle.test(text)
      {
        title = recipePrefix.replacingFirst(in: text, with: "")
        continue
      }
      rest.append(line)
    }
    return (title, rest.isEmpty ? nil : rest.joined(separator: " ").jsPrefix(2000))
  }

  private static let runTogether = JSRegex(",\(JS.dot)*,")

  /// Reads text that has an ingredients heading.
  private static func readSections(_ lines: [String]) -> TextReading? {
    var blocks: [Block: [String]] = [.intro: [], .ingredients: [], .method: [], .notes: []]
    var meta = Meta()
    var block = Block.intro
    var sawIngredients = false
    var sawMethod = false
    for raw in lines {
      let line = clean(raw)
      if isCallToAction(line) { continue }
      if let found = heading(of: line) {
        block = found
        sawIngredients = sawIngredients || found == .ingredients
        sawMethod = sawMethod || found == .method
        continue
      }
      // "Ingredients: 2 eggs" or "Method: Mix everything."
      if let inline = inlineHeading.firstMatch(in: line), let name = inline.group(1),
        let found = heading(of: name)
      {
        block = found
        sawIngredients = sawIngredients || found == .ingredients
        sawMethod = sawMethod || found == .method
        blocks[block, default: []].append(inline.group(2) ?? "")
        continue
      }
      // "Serves 4" and "Prep: 10 min" sit above the method. In the method, "Cook the onions
      // for 10 minutes" is a step.
      if block == .intro || block == .ingredients, !line.isEmpty, readMeta(line, &meta) {
        continue
      }
      blocks[block, default: []].append(line)
    }
    if !sawIngredients { return nil }
    var ingredientLines = blocks[.ingredients] ?? []
    var methodLines = blocks[.method] ?? []
    if !sawMethod {
      // No method heading: the method starts at the first line that reads as a sentence
      // rather than an ingredient.
      guard
        let start = ingredientLines.enumerated().first(where: { index, line in
          index > 0 && !line.jsTrimmed().isEmpty && !looksLikeIngredient(line)
            && line.jsTrimmed().jsLength > 50
        })?.offset
      else { return nil }
      methodLines = Array(ingredientLines[start...])
      ingredientLines = Array(ingredientLines[..<start])
    }
    let (title, description) = pickTitle(blocks[.intro] ?? [], &meta)
    let ingredients = ingredients(ingredientLines, unsure: false)
    let steps = steps(methodLines.filter { !trailer.test($0.jsTrimmed()) }, unsure: false)
    if ingredients.isEmpty || steps.isEmpty { return nil }
    let notes = (blocks[.notes] ?? []).joined(separator: "\n").jsTrimmed()
    // One long comma-separated "ingredient" is a list run together, not a line.
    let clear =
      sawMethod && title != nil
      && !(ingredients.count == 1 && runTogether.test(ingredients[0].line))
    return TextReading(
      clarity: clear ? .clear : .rough,
      recipe: ExtractedRecipe(
        title: title, description: description, servings: meta.servings,
        prepMinutes: meta.prepMinutes, cookMinutes: meta.cookMinutes,
        totalMinutes: meta.totalMinutes, notes: notes.isEmpty ? nil : notes,
        ingredients: ingredients, steps: steps, unsure: title == nil ? [.title] : []))
  }

  /// Text with no headings: the first run of ingredient-looking lines is the ingredients, what
  /// follows is the method, and what comes before is the title.
  private static func readLoose(_ lines: [String]) -> TextReading? {
    let cleaned = lines.map(clean)
    let isIngredient = cleaned.map { !$0.isEmpty && looksLikeIngredient($0) && $0.jsLength <= 160 }
    var start = -1
    var end = -1
    for i in cleaned.indices where isIngredient[i] {
      var j = i
      var count = 0
      while j < cleaned.count, isIngredient[j] || cleaned[j].isEmpty {
        if isIngredient[j] { count += 1 }
        j += 1
      }
      if count >= 2 {
        start = i
        end = j
        break
      }
    }
    if start == -1 { return nil }
    var meta = Meta()
    let method = cleaned[end...].filter { line in
      !(!line.isEmpty && readMeta(line, &meta))
    }
    let ingredients = ingredients(Array(cleaned[start..<end]), unsure: true)
    let steps = steps(Array(method), unsure: true)
    if steps.isEmpty { return nil }
    let (title, description) = pickTitle(Array(cleaned[..<start]), &meta)
    return TextReading(
      clarity: .rough,
      recipe: ExtractedRecipe(
        title: title, description: description, servings: meta.servings,
        prepMinutes: meta.prepMinutes, cookMinutes: meta.cookMinutes,
        totalMinutes: meta.totalMinutes, ingredients: ingredients, steps: steps,
        unsure: [.title, .description]))
  }

  private static let carriageReturns = JSRegex("\\r\\n?")
  private static let oddSpaces = JSRegex("[\\u00A0\\u2007\\u202F]")

  /// Reads a recipe from plain text, or nil when there's no recipe it can find
  /// (`readRecipeText`).
  static func read(_ text: String) -> TextReading? {
    let lines = oddSpaces.replacing(in: carriageReturns.replacing(in: text, with: "\n"), with: " ")
      .components(separatedBy: "\n")
    return readSections(lines) ?? readLoose(lines)
  }
}
