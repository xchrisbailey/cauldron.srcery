import CauldronKit
import Foundation
import Testing

/// A `RecipeAI` that answers from closures, for the fallback and queue rules.
private struct FakeAI: RecipeAI {
  var onExtract: @Sendable (ExtractInput) throws(RecipeAIError) -> Extraction = {
    _ throws(RecipeAIError) in
    throw .unreachable
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    try onExtract(input)
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}

private func found(_ title: String) -> Extraction {
  Extraction(outcome: .found, recipe: ExtractedRecipe(title: title), usage: nil)
}

private func failing(_ error: RecipeAIError) -> FakeAI {
  FakeAI(onExtract: { _ throws(RecipeAIError) in throw error })
}

private func answering(_ title: String) -> FakeAI {
  FakeAI(onExtract: { _ throws(RecipeAIError) in found(title) })
}

private let input = ExtractInput(text: "2 eggs. Fry them.", kind: .text)

@Suite("Extraction fallback")
struct FallbackExtractorTests {
  @Test func geminiAnswersWhenItCan() async throws {
    let extractor = FallbackExtractor(primary: answering("Gemini"), onDevice: answering("Device"))
    let extraction = try await extractor.extract(input)
    #expect(extraction.recipe.title == "Gemini")
    #expect(!extraction.rough)
  }

  @Test func aCancelledRequestDoesntFallBack() async {
    let extractor = FallbackExtractor(primary: failing(.cancelled), onDevice: answering("Device"))
    await #expect(throws: RecipeAIError.cancelled) { try await extractor.extract(input) }
  }

  @Test(arguments: [
    RecipeAIError.missingKey, .invalidKey, .rateLimited, .invalidModel, .unreachable,
  ])
  func theDeviceReadsItWhenGeminiCantBeReachedAndTheResultIsRough(error: RecipeAIError)
    async throws
  {
    let extractor = FallbackExtractor(primary: failing(error), onDevice: answering("Device"))
    let extraction = try await extractor.extract(input)
    #expect(extraction.recipe.title == "Device")
    #expect(extraction.rough)
  }

  @Test func aBadAnswerFromGeminiIsAFailureNotAFallback() async {
    let extractor = FallbackExtractor(
      primary: failing(.failed(detail: "bad output")), onDevice: answering("Device"))
    await #expect(throws: RecipeAIError.failed(detail: "bad output")) {
      try await extractor.extract(input)
    }
  }

  @Test func withoutAnOnDeviceModelTheReasonComesThrough() async {
    let extractor = FallbackExtractor(primary: failing(.rateLimited), onDevice: nil)
    await #expect(throws: RecipeAIError.rateLimited) { try await extractor.extract(input) }
  }

  @Test func whenBothFailTheCookHearsWhyGeminiWasntUsed() async {
    let extractor = FallbackExtractor(
      primary: failing(.missingKey), onDevice: failing(.failed(detail: "too long")))
    await #expect(throws: RecipeAIError.missingKey) { try await extractor.extract(input) }
  }

  @Test func aMissingRecipeFromTheDeviceIsStillMarkedRough() async throws {
    let device = FakeAI(onExtract: { _ throws(RecipeAIError) in
      Extraction(outcome: .missing, recipe: .empty, usage: nil)
    })
    let extraction = try await FallbackExtractor(primary: failing(.unreachable), onDevice: device)
      .extract(input)
    #expect(extraction.outcome == .missing)
    #expect(extraction.rough)
  }
}

@Suite("Queued job rules")
struct AIJobRulesTests {
  @Test(arguments: [
    RecipeAIError.missingKey, .invalidKey, .rateLimited, .invalidModel, .unreachable, .cancelled,
  ])
  func aJobWaitsHoweverLongTheModelIsOutOfReach(error: RecipeAIError) {
    for attempts in [0, 1, 2, 50] {
      #expect(AIJobRules.decide(after: error, attempts: attempts) == .wait)
    }
  }

  @Test func aBadAnswerUsesUpAnAttemptAndTheThirdGivesUp() {
    let bad = RecipeAIError.failed(detail: "bad output")
    #expect(AIJobRules.decide(after: bad, attempts: 0) == .retry)
    #expect(AIJobRules.decide(after: bad, attempts: 1) == .retry)
    #expect(AIJobRules.decide(after: bad, attempts: 2) == .fail)
    #expect(AIJobRules.decide(after: bad, attempts: 9) == .fail)
  }

  @Test func onlyLastingProblemsLeaveAStatus() {
    #expect(RecipeAIStatus(after: .missingKey) == .missingKey)
    #expect(RecipeAIStatus(after: .invalidKey) == .invalidKey)
    #expect(RecipeAIStatus(after: .rateLimited) == .rateLimited)
    #expect(RecipeAIStatus(after: .invalidModel) == .invalidModel)
    #expect(RecipeAIStatus(after: .cancelled) == nil)
    #expect(RecipeAIStatus(after: .unreachable) == nil)
    #expect(RecipeAIStatus(after: .failed(detail: "x")) == nil)
  }
}
