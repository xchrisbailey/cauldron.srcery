import Foundation

/// The recipe box prepared for searching. Build it once from the recipes' searchable text and
/// reuse it until they change: each recipe's words are split and stemmed here, not on every
/// keystroke. It is the one way into search; a query returns ranked results, each with the
/// recipe's id and a tier.
///
/// For now every result is in the exact tier and means what `RecipeSearch.Query` means: every
/// word typed starts a word (or a stem) of the recipe's document, or the title holds the whole
/// query. Results come best first: a title that starts with the query, then a title with every
/// word, then the rest, each by title.
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

  /// How well a result matched.
  public enum Tier: Sendable, Equatable {
    /// Every word matched a word of the recipe from its first letters.
    case exact
  }

  public struct Result: Sendable, Equatable {
    public let id: UUID
    public let tier: Tier

    public init(id: UUID, tier: Tier) {
      self.id = id
      self.tier = tier
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

    /// Calls `body` with the documents of every key that starts with `prefix`.
    func forEachPosting(startingWith prefix: String, _ body: (Int) -> Void) {
      var low = 0
      var high = keys.count
      while low < high {
        let middle = (low + high) / 2
        if keys[middle] < prefix { low = middle + 1 } else { high = middle }
      }
      var index = low
      while index < keys.count, keys[index].hasPrefix(prefix) {
        for document in postings[index] { body(document) }
        index += 1
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
    let keyed = entries.map { (entry: $0, title: $0.title.lowercased(), id: $0.id.uuidString) }
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
      inDocuments.add(RecipeSearch.words(item.entry.document), at: position)
      inTitles.add(RecipeSearch.words(item.entry.title), at: position)
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

  /// The recipes that match, best first. Text with no words matches every recipe, by title.
  public func search(_ text: String) -> [Result] {
    let query = RecipeSearch.Query(text)
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
    return startsWith + withEveryWord + rest
  }

  /// How many of `terms` each document has, by a word or a stem that starts with the term, and
  /// the documents that have them all. A query of only stop words has no terms, and finds
  /// nothing this way.
  private func reach(
    _ terms: [RecipeSearch.Query.Term], words: Vocabulary, stems: Vocabulary
  ) -> (reached: [Int], every: [Int]) {
    var reached = [Int](repeating: 0, count: documents.count)
    var every: [Int] = []
    guard !terms.isEmpty else { return (reached, every) }
    for (number, term) in terms.enumerated() {
      let advance = { (document: Int) in
        guard reached[document] == number else { return }
        reached[document] = number + 1
        if number + 1 == terms.count { every.append(document) }
      }
      words.forEachPosting(startingWith: term.typed, advance)
      stems.forEachPosting(startingWith: term.stem, advance)
    }
    return (reached, every)
  }
}
