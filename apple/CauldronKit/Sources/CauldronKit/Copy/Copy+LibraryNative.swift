extension Copy {
  /// What the recipe library says that the web copy doesn't: renaming a tag, which the web
  /// has an API for but no screen, and why a close match in search was found. These strings
  /// have no counterpart in the web copy, so the reference fixture leaves them out. All of it is
  /// a control, a form or a reason, so all of it is plain.
  public struct LibraryNative: Sendable {
    /// The tag menu's item that renames the tag being filtered on.
    public let renameTag = plain("Rename tag…")
    public let renameTagField = plain("Tag name")
    public let renameTagSave = plain("Rename")

    /// The heading over the results that needed a typo, another name or a missing word. On
    /// ⌘K it is the section label.
    public let closeMatches = plain("Close matches")

    public init() {}

    /// The line under a close match: the words it matched, as the recipe has them.
    public func matched(_ words: String) -> CopyString { plain("Matched \(words)") }

    /// A matched word that is another name for what was typed: "aubergine, another name for
    /// eggplant".
    public func anotherName(_ word: String, for typed: String) -> CopyString {
      plain("\(word), another name for \(typed)")
    }

    /// The line under a partial match: what it matched and the one word it lacks.
    public func matchedMissing(_ words: String, missing: String) -> CopyString {
      plain("Matched \(words) · no \(missing)")
    }

    /// The line that ends a search's results while recipes saved before keywords existed are
    /// still being read for search.
    public func stillReading(_ count: Int) -> CopyString {
      plain(
        "Still reading \(count) \(count == 1 ? "recipe" : "recipes") for search. Results may grow."
      )
    }

    public func renameTagTitle(_ name: String) -> CopyString { plain("Rename \(name)") }
  }
}
