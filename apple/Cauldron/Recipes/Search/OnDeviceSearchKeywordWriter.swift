import CauldronKit
import FoundationModels

/// Apple's on-device model, writing search keywords by guided generation. It is the only
/// writer the app has: a recipe's words never leave the device for this, and the cook's key is
/// never read.
struct OnDeviceSearchKeywordWriter: SearchKeywordWriting {
  func write(_ inputs: SearchKeywordInputs) async -> SearchKeywordOutcome {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
      break
    case .unavailable(.deviceNotEligible):
      return .unavailable(.notEligible)
    case .unavailable(.modelNotReady):
      return .unavailable(.downloading)
    case .unavailable:
      return .unavailable(.unavailable)
    }
    let session = LanguageModelSession(instructions: SearchKeywordPrompt.system)
    do {
      let response = try await session.respond(
        to: SearchKeywordPrompt.user(for: inputs), generating: GeneratedSearchKeywords.self)
      return .written(response.content.answer.keywords)
    } catch {
      return .failed
    }
  }
}

/// The answer as the model is asked for it: a list for each kind of keyword.
@Generable
struct GeneratedSearchKeywords {
  @Guide(description: SearchKeywordAnswer.Field.otherIngredients.guide)
  var otherIngredients: [String]
  @Guide(description: SearchKeywordAnswer.Field.dish.guide)
  var dish: [String]
  @Guide(description: SearchKeywordAnswer.Field.cuisine.guide)
  var cuisine: [String]
  @Guide(description: SearchKeywordAnswer.Field.flavour.guide)
  var flavour: [String]
  @Guide(description: SearchKeywordAnswer.Field.method.guide)
  var method: [String]
  @Guide(description: SearchKeywordAnswer.Field.occasion.guide)
  var occasion: [String]
  @Guide(description: SearchKeywordAnswer.Field.usesUp.guide)
  var usesUp: [String]

  var answer: SearchKeywordAnswer {
    SearchKeywordAnswer(
      otherIngredients: otherIngredients, dish: dish, cuisine: cuisine, flavour: flavour,
      method: method, occasion: occasion, usesUp: usesUp)
  }
}

/// The writer for a run with no model: under test and in previews, where nothing should run.
struct NoSearchKeywordWriter: SearchKeywordWriting {
  func write(_ inputs: SearchKeywordInputs) async -> SearchKeywordOutcome {
    .unavailable(.unavailable)
  }
}
