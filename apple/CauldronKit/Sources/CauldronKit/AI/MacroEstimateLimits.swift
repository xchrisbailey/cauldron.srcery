// The limits an estimate's input is held to, as the reference holds it: the web editor sends
// only what its schema accepts (`MacroEstimateInput` in `Recipe.ts`), and an import cuts its
// lines the same way before it asks (`withMacros` in `distill.ts`). Every way of asking for an
// estimate builds its input here, so a queued one can't be refused for being too long.

extension MacroEstimateInput {
  /// The ask for a recipe with this title, yield and ingredient lines, or nil when no line has
  /// anything in it. Lines are trimmed, blank ones dropped, each cut to `RecipeLimits.line`,
  /// and no more than `RecipeLimits.ingredients` are kept. A title is trimmed and cut to
  /// `RecipeLimits.title` (nil when blank). A yield outside 1 to `RecipeLimits.servings` is
  /// left out, so the estimate is for the recipe as it stands.
  public static func limited(title: String?, servings: Int?, lines: [String])
    -> MacroEstimateInput?
  {
    let kept = lines.map { $0.jsTrimmed().jsPrefix(RecipeLimits.line) }
      .filter { !$0.isEmpty }.prefix(RecipeLimits.ingredients)
    guard !kept.isEmpty else { return nil }
    let name = title?.jsTrimmed().jsPrefix(RecipeLimits.title)
    return MacroEstimateInput(
      title: name.flatMap { $0.isEmpty ? nil : $0 },
      servings: servings.flatMap { (1...RecipeLimits.servings).contains($0) ? $0 : nil },
      ingredients: Array(kept))
  }
}
