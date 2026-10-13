import CauldronKit
import Foundation
import FoundationModels

/// Apple's on-device model, which reads a recipe when Gemini can't be reached. Its results
/// are rougher, and the caller marks them so. It never estimates macros: those wait for
/// Gemini.
struct OnDeviceRecipeAI: RecipeAI {
  /// Nil where the device has no model, or it isn't ready.
  static func make() -> OnDeviceRecipeAI? {
    SystemLanguageModel.default.availability == .available ? OnDeviceRecipeAI() : nil
  }

  /// Roughly how many characters of recipe text fit beside the instructions and the answer.
  /// The model's context is counted in tokens; three characters to a token is a cautious
  /// figure for English, and half the context is left for the instructions and the answer.
  static func inputBudget(contextSize: Int) -> Int {
    max(1_000, contextSize / 2 * 3)
  }

  func extract(_ input: ExtractInput) async throws(RecipeAIError) -> Extraction {
    let prompt = AIPrompts.extract(input)
    var budget = Self.inputBudget(contextSize: SystemLanguageModel.default.contextSize)
    // One retry at half the length, for text that is denser than the estimate allowed.
    for _ in 0..<2 {
      let session = LanguageModelSession(instructions: prompt.system)
      do {
        let response = try await session.respond(
          to: String(prompt.user.prefix(budget)), generating: OnDeviceRecipe.self)
        return Extraction(
          outcome: response.content.outcome, recipe: response.content.extracted, usage: nil)
      } catch {
        if Task.isCancelled { throw .cancelled }
        budget /= 2
      }
    }
    throw .failed(detail: "on-device model")
  }

  func estimateMacros(_ input: MacroEstimateInput) async throws(RecipeAIError) -> Macros {
    throw .unreachable
  }

  func estimateMeal(_ text: String) async throws(RecipeAIError) -> [DescribedItem] {
    throw .unreachable
  }
}

/// The recipe as the on-device model is asked for it: the same fields as Gemini's answer, in
/// the plain types guided generation takes.
@Generable
struct OnDeviceRecipe {
  @Generable
  struct Line {
    @Guide(description: "The ingredient line exactly as written, quantity and unit included.")
    var line: String
    @Guide(description: "The heading it sits under, like \"For the sauce\", or empty.")
    var section: String
  }

  @Generable
  struct Step {
    @Guide(description: "One step of the method, as written.")
    var text: String
  }

  @Guide(
    description:
      "\"found\" when the text has a recipe (ingredients and method). \"inVideo\" when it only points to a recipe shown or spoken in a video. \"missing\" otherwise.",
    .anyOf(["found", "missing", "inVideo"]))
  var recipe: String
  @Guide(description: "The recipe's title, or empty.")
  var title: String
  @Guide(description: "How many it serves, or 0 when the text doesn't say.")
  var servings: Int
  @Guide(description: "Whole minutes of preparation, or 0 when the text doesn't say.")
  var prepMinutes: Int
  @Guide(description: "Whole minutes of cooking, or 0 when the text doesn't say.")
  var cookMinutes: Int
  var ingredients: [Line]
  var steps: [Step]

  var outcome: ExtractOutcome {
    ExtractOutcome(rawValue: recipe) ?? .missing
  }

  private static func some(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func some(_ number: Int) -> Int? {
    number > 0 ? number : nil
  }

  /// Everything from this model is a guess to check, so every line and step is unsure.
  var extracted: ExtractedRecipe {
    ExtractedRecipe(
      title: Self.some(title), servings: Self.some(servings),
      prepMinutes: Self.some(prepMinutes), cookMinutes: Self.some(cookMinutes),
      ingredients: ingredients.compactMap { line in
        Self.some(line.line).map {
          ExtractedLine(line: $0, section: Self.some(line.section), unsure: true)
        }
      },
      steps: steps.compactMap { step in
        Self.some(step.text).map { ExtractedStep(text: $0, section: nil, unsure: true) }
      },
      unsure: [.title, .servings, .prepMinutes, .cookMinutes])
  }
}
