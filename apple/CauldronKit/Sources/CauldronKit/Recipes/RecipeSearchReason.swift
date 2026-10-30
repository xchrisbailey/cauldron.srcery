// The line under a close or partial match says what it matched, in plain words:
//   Matched chicken
//   Matched aubergine, another name for eggplant
//   Matched spicy, peanut · no noodles
// A forgiven word shows as the word it matched. The words that matched as typed come first,
// then each other name with what it stands for. ⌘K has less room, so its row drops the other
// name's explanation.

extension RecipeSearchIndex.Reason {
  /// The one line a close or partial match shows under its title, or nil for an exact match.
  public var line: CopyString? {
    guard !matched.isEmpty else { return nil }
    var plainWords = matched
    var names: [String] = []
    for name in forgiven where name.kind == .synonym {
      if let place = plainWords.firstIndex(of: name.matched) { plainWords.remove(at: place) }
      names.append(Copy.libraryNative.anotherName(name.matched, for: name.typed).text)
    }
    return sentence(for: (plainWords + names).joined(separator: ", "))
  }

  /// The line shortened to fit a row of ⌘K.
  public var shortLine: CopyString? {
    guard !matched.isEmpty else { return nil }
    return sentence(for: matched.joined(separator: ", "))
  }

  private func sentence(for words: String) -> CopyString {
    guard let missing else { return Copy.libraryNative.matched(words) }
    return Copy.libraryNative.matchedMissing(words, missing: missing)
  }
}
