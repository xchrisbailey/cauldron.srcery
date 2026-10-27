import Foundation

// Search keywords: the hidden words the on-device model writes for a recipe so search can find
// it by other names and descriptions ("leftover rice" finds Kimchi fried rice). Everything here
// is plain Swift so it builds and tests on Linux; the model itself lives in the app.

/// What the keywords are written from: the recipe's title, ingredient items, tag names and
/// description. Nothing else feeds the model, so nothing else makes keywords stale.
public struct SearchKeywordInputs: Sendable, Equatable {
  public var title: String
  /// The ingredient items in recipe order, without quantities.
  public var ingredients: [String]
  public var tags: [String]
  public var description: String?

  public init(title: String, ingredients: [String], tags: [String], description: String? = nil) {
    self.title = title
    self.ingredients = ingredients
    self.tags = tags
    self.description = description
  }

  /// A stable digest of the inputs, as 16 hex digits. Keywords store the one they were written
  /// from, and a different digest later means they are stale. It is the same on every device
  /// and every launch, so a device skips keywords another device wrote: `Hasher` and
  /// `hashValue` are seeded per process and must not be used here.
  public var fingerprint: String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in canonical.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    let digits = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - digits.count) + digits
  }

  /// A version prefix, then the title, the ingredient items in order, the tag names sorted and
  /// the description. Each part is trimmed, NFC-normalised and lowercased, so a change of case,
  /// spacing, accent form or tag order doesn't count as an edit. Change the layout and you must
  /// bump the version, which makes every stored fingerprint stale.
  var canonical: String {
    let record = "\u{1E}"
    let unit = "\u{1F}"
    let parts = [
      Self.normalised(title),
      ingredients.map(Self.normalised).filter { !$0.isEmpty }.joined(separator: unit),
      tags.map(Self.normalised).filter { !$0.isEmpty }.sorted().joined(separator: unit),
      Self.normalised(description ?? ""),
    ]
    return "v1" + record + parts.joined(separator: record)
  }

  private static func normalised(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
      .lowercased()
  }
}

/// The words the model is asked for.
public enum SearchKeywordPrompt {
  public static var system: String {
    let kinds = SearchKeywordAnswer.Field.allCases.map { "- \($0.name): \($0.guide)" }
    return """
      You write hidden search keywords for a recipe so a cook can find it by other names and \
      descriptions. You are given the recipe's title, ingredients, tags and description. \
      Answer with short lists of lowercase words and phrases of these kinds:
      \(kinds.joined(separator: "\n"))
      Leave a list empty rather than guess. Do not repeat words already in the recipe. Use at \
      most \(SearchKeywordAnswer.wordLimit) words in all. Never write a sentence.
      """
  }

  /// The recipe's inputs as text, leaving out any part that is empty.
  public static func user(for inputs: SearchKeywordInputs) -> String {
    func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var lines = ["Title: \(clean(inputs.title))"]
    let ingredients = inputs.ingredients.map(clean).filter { !$0.isEmpty }
    if !ingredients.isEmpty {
      lines.append("Ingredients:")
      lines += ingredients.map { "- \($0)" }
    }
    let tags = inputs.tags.map(clean).filter { !$0.isEmpty }
    if !tags.isEmpty { lines.append("Tags: " + tags.joined(separator: ", ")) }
    let description = clean(inputs.description ?? "")
    if !description.isEmpty { lines.append("Description: \(description)") }
    return lines.joined(separator: "\n")
  }
}

/// Why the model can't write keywords right now. None of them is the recipe's fault, so none
/// counts as a failed attempt.
public enum SearchKeywordUnavailability: Sendable, Equatable {
  /// No model on this device, or Apple Intelligence is off.
  case unavailable
  /// The device can't run the model.
  case notEligible
  /// The model is still downloading.
  case downloading
}

/// The model's answer: a list for each kind of keyword.
public struct SearchKeywordAnswer: Sendable, Equatable {
  /// The kinds of keyword, in the order they are flattened.
  public enum Field: CaseIterable, Sendable {
    case dish, cuisine, otherIngredients, flavour, method, occasion, usesUp

    /// What the prompt calls it.
    public var name: String {
      switch self {
      case .dish: "dish"
      case .cuisine: "cuisine"
      case .otherIngredients: "other ingredient names"
      case .flavour: "flavour"
      case .method: "method"
      case .occasion: "occasion"
      case .usesUp: "uses-up"
      }
    }

    /// What the model is told to put in it.
    public var guide: String {
      switch self {
      case .dish: "what the dish is called elsewhere, like \"fried rice\" or \"noodle salad\""
      case .cuisine: "the cuisine or region, like \"korean\""
      case .otherIngredients:
        "other names for the ingredients, like \"scallion\" for spring onion"
      case .flavour: "how it tastes, like \"spicy\" or \"creamy\""
      case .method: "how it is cooked, like \"stir-fry\" or \"one pot\""
      case .occasion: "when a cook would want it, like \"weeknight\" or \"meal prep\""
      case .usesUp: "leftovers or pantry items it uses up, like \"leftover rice\""
      }
    }
  }

  /// The most words the flattened text holds.
  public static let wordLimit = 30

  public var otherIngredients: [String]
  public var dish: [String]
  public var cuisine: [String]
  public var flavour: [String]
  public var method: [String]
  public var occasion: [String]
  public var usesUp: [String]

  public init(
    otherIngredients: [String] = [], dish: [String] = [], cuisine: [String] = [],
    flavour: [String] = [], method: [String] = [], occasion: [String] = [], usesUp: [String] = []
  ) {
    self.otherIngredients = otherIngredients
    self.dish = dish
    self.cuisine = cuisine
    self.flavour = flavour
    self.method = method
    self.occasion = occasion
    self.usesUp = usesUp
  }

  private func entries(_ field: Field) -> [String] {
    switch field {
    case .dish: dish
    case .cuisine: cuisine
    case .otherIngredients: otherIngredients
    case .flavour: flavour
    case .method: method
    case .occasion: occasion
    case .usesUp: usesUp
    }
  }

  /// The answer as one line of text, at most `wordLimit` words. Entries are lowercased, have
  /// their whitespace collapsed and are not repeated. They are taken a round at a time, the
  /// first of each list, then the second of each, so one long list can't crowd out the rest. An
  /// entry that would pass the limit is left out whole.
  public var keywords: String {
    let lists = Field.allCases.map { field in
      entries(field).map(Self.clean).filter { !$0.isEmpty }
    }
    var kept: [String] = []
    var seen: Set<String> = []
    var words = 0
    for round in 0..<(lists.map(\.count).max() ?? 0) {
      for list in lists where round < list.count {
        let entry = list[round]
        let count = entry.split(separator: " ").count
        guard words + count <= Self.wordLimit, seen.insert(entry).inserted else { continue }
        kept.append(entry)
        words += count
      }
    }
    return kept.joined(separator: ", ")
  }

  private static func clean(_ entry: String) -> String {
    entry.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }
}
