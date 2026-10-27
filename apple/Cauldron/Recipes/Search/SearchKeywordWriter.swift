import CauldronKit

/// What a writer came back with.
enum SearchKeywordOutcome: Sendable, Equatable {
  /// The keywords, flattened to text. The runner treats text with no words as a failure.
  case written(String)
  /// The model can't run now. Not the recipe's fault, so it doesn't count against it.
  case unavailable(SearchKeywordUnavailability)
  /// The model ran and its answer was no use.
  case failed
}

/// Whatever writes search keywords for a recipe. The live one is Apple's on-device model and
/// nothing else: it never reaches `RecipeAI`, the cloud providers or the cook's key.
protocol SearchKeywordWriting: Sendable {
  func write(_ inputs: SearchKeywordInputs) async -> SearchKeywordOutcome
}
