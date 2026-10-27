import Foundation

/// The recipe box prepared for searching. Build it once from the recipes' searchable text and
/// reuse it until they change: each recipe's words are split and stemmed here, not on every
/// keystroke. It is the one way into search; a query returns ranked results, each with the
/// recipe's id and a tier.
///
/// An exact result means what `RecipeSearch.Query` means: every word typed starts a word (or a
/// stem) of the recipe's document, or the title holds the whole query. Results come best first:
/// a title that starts with the query, then a title with every word, then the rest, each by
/// title.
///
/// A search of three or more words that lacks exactly one of them still finds a recipe that has
/// the rest, in the partial tier after the close ones. Shorter searches must match every word.
///
/// A word typed that starts no word anywhere in the box is forgiven a typo, by its length: none
/// up to four letters, one from five and two from nine, never in the first letter and never
/// for a word with a digit. A recipe that needed that comes after every exact one, in the close
/// tier, with a reason that says which words were forgiven as what. Accents are folded away on
/// both sides, so they are never a typo.
public struct RecipeSearchIndex: Sendable {
  /// What the index needs to know about one recipe.
  public struct Entry: Sendable, Equatable {
    public let id: UUID
    public let title: String
    /// All the text that can match: the title, tags, ingredient items and description.
    public let document: String

    public init(id: UUID, title: String, document: String) {
      self.id = id
      self.title = title
      self.document = document
    }
  }

  /// How well a result matched, best first.
  public enum Tier: Int, Sendable, Equatable, Comparable {
    /// Every word matched a word of the recipe from its first letters.
    case exact
    /// Every word matched, but at least one needed a typo or another name.
    case close
    /// All but one of the words matched.
    case partial

    public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
  }

  /// Why a recipe matched, for the one line a close match shows. An exact match has no reason
  /// to give, so its reason is empty.
  public struct Reason: Sendable, Equatable {
    /// How a typed word was forgiven.
    public enum Kind: Sendable, Equatable {
      case typo
      case synonym
    }

    /// A typed word that matched a different word of the recipe.
    public struct Forgiven: Sendable, Equatable {
      /// The word as typed, lowercase and without accents.
      public let typed: String
      /// The word it matched in the recipe (or the other name's words).
      public let matched: String
      public let kind: Kind

      public init(typed: String, matched: String, kind: Kind) {
        self.typed = typed
        self.matched = matched
        self.kind = kind
      }
    }

    /// The words matched, in the order typed: a word as typed when it matched as it was, or the
    /// word it matched when it was forgiven.
    public let matched: [String]
    /// The typed words that needed forgiving.
    public let forgiven: [Forgiven]
    /// The one typed word a partial match lacks.
    public let missing: String?

    public init(matched: [String] = [], forgiven: [Forgiven] = [], missing: String? = nil) {
      self.matched = matched
      self.forgiven = forgiven
      self.missing = missing
    }

    /// The reason of an exact match: nothing to say.
    public static let exact = Reason()
  }

  public struct Result: Sendable, Equatable {
    public let id: UUID
    public let tier: Tier
    public let reason: Reason

    public init(id: UUID, tier: Tier, reason: Reason = .exact) {
      self.id = id
      self.tier = tier
      self.reason = reason
    }
  }

  /// The entries the index was built from, in the order given. An index is current while the
  /// recipes' entries equal these.
  public let entries: [Entry]

  /// The box's distinct words, lowercase and sorted.
  public var words: [String] { documentWords.keys }

  /// A recipe, in title order (the order ⌘K breaks ties in).
  private struct Document: Sendable {
    let id: UUID
    /// The title lowercased, for the whole-query match and the starts-with rank.
    let title: String
  }

  /// Words (or stems) in sorted order, each with the documents that hold it. A document is a
  /// position in `documents`, so a list is ascending.
  private struct Vocabulary: Sendable {
    private(set) var keys: [String]
    private var postings: [[Int]] = []

    init(_ found: [String: [Int]]) {
      let sorted = found.keys.sorted()
      keys = sorted
      postings = sorted.map { found[$0] ?? [] }
    }

    /// Calls `body` with each key that starts with `prefix` and the documents that hold it.
    func forEachKey(startingWith prefix: String, _ body: (String, [Int]) -> Void) {
      var low = 0
      var high = keys.count
      while low < high {
        let middle = (low + high) / 2
        if keys[middle] < prefix { low = middle + 1 } else { high = middle }
      }
      var index = low
      while index < keys.count, keys[index].hasPrefix(prefix) {
        body(keys[index], postings[index])
        index += 1
      }
    }

    /// Calls `body` with the documents of every key that starts with `prefix`.
    func forEachPosting(startingWith prefix: String, _ body: (Int) -> Void) {
      forEachKey(startingWith: prefix) { _, documents in
        for document in documents { body(document) }
      }
    }
  }

  /// Some titles joined into one string, so a title holding the whole query can be ruled out
  /// for the whole group with one search. A phrase that spans two titles can only cause a
  /// wasted look at each, never a missed title.
  private struct TitleGroup: Sendable {
    static let size = 8
    let text: String
    let documents: Range<Int>
  }

  private let documents: [Document]
  private let titleGroups: [TitleGroup]
  private let documentWords: Vocabulary
  private let documentStems: Vocabulary
  private let titleWords: Vocabulary
  private let titleStems: Vocabulary

  public init(_ entries: [Entry]) {
    self.entries = entries
    let keyed = entries.map {
      (entry: $0, title: RecipeSearch.folded($0.title).lowercased(), id: $0.id.uuidString)
    }
    let ordered = keyed.sorted { a, b in
      a.title != b.title ? a.title < b.title : a.id < b.id
    }
    let sorted = ordered.map { Document(id: $0.entry.id, title: $0.title) }
    documents = sorted
    titleGroups = stride(from: 0, to: sorted.count, by: TitleGroup.size).map { start in
      let range = start..<min(start + TitleGroup.size, sorted.count)
      return TitleGroup(text: sorted[range].map(\.title).joined(separator: "\n"), documents: range)
    }

    var inDocuments = Postings()
    var inTitles = Postings()
    for (position, item) in ordered.enumerated() {
      inDocuments.add(RecipeSearch.words(RecipeSearch.folded(item.entry.document)), at: position)
      inTitles.add(RecipeSearch.words(item.title), at: position)
    }
    documentWords = Vocabulary(inDocuments.words.found)
    documentStems = Vocabulary(inDocuments.stems.found)
    titleWords = Vocabulary(inTitles.words.found)
    titleStems = Vocabulary(inTitles.stems.found)
  }

  /// Collects words and stems while an index is built. Each distinct word is looked up once per
  /// use and stemmed once, however many recipes use it.
  private struct Postings {
    /// The documents that hold each key, found by the key's number.
    struct Keyed {
      private var numbers: [String: Int] = [:]
      private var keys: [String] = []
      private var documents: [[Int]] = []
      private var latest: [Int] = []

      var found: [String: [Int]] { Dictionary(uniqueKeysWithValues: zip(keys, documents)) }

      mutating func number(of key: String) -> Int {
        if let known = numbers[key] { return known }
        numbers[key] = keys.count
        keys.append(key)
        documents.append([])
        latest.append(-1)
        return keys.count - 1
      }

      mutating func note(_ document: Int, under number: Int) {
        guard latest[number] != document else { return }
        latest[number] = document
        documents[number].append(document)
      }
    }

    var words = Keyed()
    var stems = Keyed()
    /// The number of each word's stem in `stems`, by the word's number in `words`.
    private var stemNumbers: [Int] = []

    mutating func add(_ found: [String], at document: Int) {
      for word in found {
        let number = words.number(of: word)
        if number == stemNumbers.count {
          stemNumbers.append(stems.number(of: RecipeSearch.stem(word)))
        }
        words.note(document, under: number)
        stems.note(document, under: stemNumbers[number])
      }
    }
  }

  /// Whether a search has any words to look for. Blank text, or only punctuation, has none, and
  /// matches every recipe.
  public static func hasWords(_ text: String) -> Bool {
    RecipeSearch.Query(text).hasWords
  }

  /// The recipes that match, best first: the exact ones, then the close ones. Text with no words
  /// matches every recipe, by title.
  public func search(_ text: String) -> [Result] {
    let query = RecipeSearch.Query(RecipeSearch.folded(text))
    guard query.hasWords else { return documents.map { Result(id: $0.id, tier: .exact) } }

    var inDocument = reach(query.terms, words: documentWords, stems: documentStems)
    var found = [Bool](repeating: false, count: 0)
    for group in titleGroups where group.text.contains(query.phrase) {
      if found.isEmpty {
        found = [Bool](repeating: false, count: documents.count)
        for position in inDocument.every { found[position] = true }
      }
      for position in group.documents where !found[position] {
        if documents[position].title.contains(query.phrase) {
          found[position] = true
          inDocument.every.append(position)
        }
      }
    }
    // A recipe is found by words in its document or by the whole query in its title.
    let inTitle = reach(query.terms, words: titleWords, stems: titleStems)

    var startsWith: [Result] = []
    var withEveryWord: [Result] = []
    var rest: [Result] = []
    for position in inDocument.every.sorted() {
      let document = documents[position]
      let result = Result(id: document.id, tier: .exact)
      if document.title.hasPrefix(query.phrase) {
        startsWith.append(result)
      } else if inTitle.reached[position] == query.terms.count {
        withEveryWord.append(result)
      } else {
        rest.append(result)
      }
    }
    let exact = startsWith + withEveryWord + rest
    // Words that start no word anywhere in the box are the only ones forgiven.
    let taken = Set(inDocument.every)
    let close =
      inDocument.hit.contains(false)
      ? forgiving(query.terms, hit: inDocument.hit, skipping: taken) : []
    guard query.terms.count >= Self.partialWords else { return exact + close }
    return exact + close + partial(query.terms, hit: inDocument.hit, skipping: taken)
  }

  /// A search of this many words or more may lack one of them.
  static let partialWords = 3

  /// How many of `terms` each document has, by a word or a stem that starts with the term, the
  /// documents that have them all, and whether anything in the box starts with each term. A
  /// query of only stop words has no terms, and finds nothing this way.
  private func reach(
    _ terms: [RecipeSearch.Query.Term], words: Vocabulary, stems: Vocabulary
  ) -> (reached: [Int], every: [Int], hit: [Bool]) {
    var reached = [Int](repeating: 0, count: documents.count)
    var every: [Int] = []
    var hit = [Bool](repeating: false, count: terms.count)
    guard !terms.isEmpty else { return (reached, every, hit) }
    for (number, term) in terms.enumerated() {
      let advance = { (document: Int) in
        hit[number] = true
        guard reached[document] == number else { return }
        reached[document] = number + 1
        if number + 1 == terms.count { every.append(document) }
      }
      words.forEachPosting(startingWith: term.typed, advance)
      stems.forEachPosting(startingWith: term.stem, advance)
    }
    return (reached, every, hit)
  }

  /// A word of the box that a typed word is a few mistakes from.
  private struct Candidate {
    let word: String
    let edits: Int
    let documents: [Int]
  }

  /// The recipes every word of which is found, where the words that started nothing (`hit` is
  /// false) are matched by a typo and the others as they are. Fewest mistakes first, then by
  /// title. Recipes in `taken` were already found exactly.
  private func forgiving(
    _ terms: [RecipeSearch.Query.Term], hit: [Bool], skipping taken: Set<Int>
  ) -> [Result] {
    // For each word typed, the way each recipe has it: nil for none, else the word it matched
    // (a typed word that matched as it was keeps its own place, at -1).
    var ways: [[Int32]] = []
    var candidates: [[Candidate]] = []
    for (number, term) in terms.enumerated() {
      var way = [Int32](repeating: -2, count: documents.count)
      var options: [Candidate] = []
      if hit[number] {
        documentWords.forEachPosting(startingWith: term.typed) { way[$0] = -1 }
        documentStems.forEachPosting(startingWith: term.stem) { way[$0] = -1 }
      } else {
        options = typoCandidates(for: term.typed)
        guard !options.isEmpty else { return [] }
        for (choice, option) in options.enumerated() {
          for document in option.documents where way[document] == -2 {
            way[document] = Int32(choice)
          }
        }
      }
      ways.append(way)
      candidates.append(options)
    }

    var found: [(position: Int, edits: Int)] = []
    for position in 0..<documents.count where !taken.contains(position) {
      var edits = 0
      var complete = true
      for number in 0..<terms.count {
        let way = ways[number][position]
        if way == -2 {
          complete = false
          break
        }
        if way >= 0 { edits += candidates[number][Int(way)].edits }
      }
      if complete { found.append((position, edits)) }
    }
    // Positions are in title order, and the sort keeps them so within the same mistakes.
    return
      found
      .enumerated()
      .sorted { a, b in
        a.element.edits != b.element.edits ? a.element.edits < b.element.edits : a.offset < b.offset
      }
      .map { _, item in
        var matched: [String] = []
        var forgiven: [Reason.Forgiven] = []
        for (number, term) in terms.enumerated() {
          let way = ways[number][item.position]
          if way < 0 {
            matched.append(term.typed)
          } else {
            let word = candidates[number][Int(way)].word
            matched.append(word)
            forgiven.append(Reason.Forgiven(typed: term.typed, matched: word, kind: .typo))
          }
        }
        return Result(
          id: documents[item.position].id, tier: .close,
          reason: Reason(matched: matched, forgiven: forgiven))
      }
  }

  /// The recipes that have every word but one, fewest mistakes first, then by title. Words are
  /// matched as `forgiving` matches them, so a recipe with every word is never here: those are
  /// exact or close. Recipes in `taken` were already found exactly, by their title.
  private func partial(
    _ terms: [RecipeSearch.Query.Term], hit: [Bool], skipping taken: Set<Int>
  ) -> [Result] {
    var ways: [[Int32]] = []
    var candidates: [[Candidate]] = []
    for (number, term) in terms.enumerated() {
      var way = [Int32](repeating: -2, count: documents.count)
      var options: [Candidate] = []
      if hit[number] {
        documentWords.forEachPosting(startingWith: term.typed) { way[$0] = -1 }
        documentStems.forEachPosting(startingWith: term.stem) { way[$0] = -1 }
      } else {
        options = typoCandidates(for: term.typed)
        for (choice, option) in options.enumerated() {
          for document in option.documents where way[document] == -2 {
            way[document] = Int32(choice)
          }
        }
      }
      ways.append(way)
      candidates.append(options)
    }

    var found: [(position: Int, missing: Int, edits: Int)] = []
    for position in 0..<documents.count where !taken.contains(position) {
      var missing: Int?
      var edits = 0
      var tooMany = false
      for number in 0..<terms.count {
        let way = ways[number][position]
        if way == -2 {
          if missing != nil {
            tooMany = true
            break
          }
          missing = number
        } else if way >= 0 {
          edits += candidates[number][Int(way)].edits
        }
      }
      if !tooMany, let missing { found.append((position, missing, edits)) }
    }
    return
      found
      .enumerated()
      .sorted { a, b in
        a.element.edits != b.element.edits ? a.element.edits < b.element.edits : a.offset < b.offset
      }
      .map { _, item in
        var matched: [String] = []
        var forgiven: [Reason.Forgiven] = []
        for (number, term) in terms.enumerated() where number != item.missing {
          let way = ways[number][item.position]
          if way < 0 {
            matched.append(term.typed)
          } else {
            let word = candidates[number][Int(way)].word
            matched.append(word)
            forgiven.append(Reason.Forgiven(typed: term.typed, matched: word, kind: .typo))
          }
        }
        return Result(
          id: documents[item.position].id, tier: .partial,
          reason: Reason(
            matched: matched, forgiven: forgiven, missing: terms[item.missing].typed))
      }
  }

  /// The words of the box a typed word is within its allowance of, fewest mistakes first, then
  /// A to Z. Only words with the same first letter are looked at, and none with a digit.
  private func typoCandidates(for typed: String) -> [Candidate] {
    let limit = RecipeSearchTypo.allowedEdits(for: typed)
    guard limit > 0, let first = typed.first else { return [] }
    var measure = RecipeSearchTypo.Measure(typed, limit: limit)
    var found: [Candidate] = []
    documentWords.forEachKey(startingWith: String(first)) { word, documents in
      guard !word.contains(where: \.isNumber) else { return }
      if let edits = measure.edits(toStartOf: word) {
        found.append(Candidate(word: word, edits: edits, documents: documents))
      }
    }
    return found.sorted { a, b in
      a.edits != b.edits ? a.edits < b.edits : a.word < b.word
    }
  }
}
