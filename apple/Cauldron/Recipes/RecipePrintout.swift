import CauldronKit
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What a printed recipe says, worked out apart from the paper so it can be tested: the title,
/// the servings at the scale on screen, the ingredients in the unit system chosen, the method
/// and the source. Nothing interactive survives onto paper.
struct RecipePrintout: Sendable, Equatable {
  var title: String
  var summary: String?
  /// "serves 4", "25 min total", "10 min prep" and so on, in the order the page shows them.
  var facts: [String]
  var ingredients: [IngredientRow]
  var steps: [StepRow]
  var notes: String?
  /// "From example.com · by Ada", or nil when the recipe has no source.
  var source: String?

  @MainActor
  init(_ recipe: RecipeRecord, scale: Scale, units: UnitSystemChoice) {
    let times = RecipeTimes(recipe)
    title = recipe.title
    summary = Self.text(recipe.summary)
    facts = [
      RecipeScale.label(scale),
      times.total,
      times.prep.map { "\($0) \(Copy.recipeView.prep.text)" },
      times.cook.map { "\($0) \(Copy.recipeView.cook.text)" },
    ].compactMap { $0 }
    ingredients = IngredientRow.rows(
      recipe.ingredients, factor: scale.factor(recipeServings: recipe.servings), system: units)
    steps = StepRow.rows(recipe.steps)
    notes = Self.text(recipe.notes)
    var source: [String] = []
    if let link = Self.text(recipe.sourceURL) {
      source.append(Copy.recipeView.from(RecipeSource.host(link)).text)
    }
    if let author = Self.text(recipe.sourceAuthor) {
      source.append(Copy.recipeView.by(author).text)
    }
    self.source = source.isEmpty ? nil : source.joined(separator: " · ")
  }

  private static func text(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  /// A name for the file when it is shared or saved.
  var fileName: String {
    let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
    let name = title.components(separatedBy: forbidden).joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
    return (name.isEmpty ? Copy.pageTitles.recipe.text : name) + ".pdf"
  }
}

extension RecipePrintout: Transferable {
  /// Shared as a PDF, drawn only when the cook picks where it goes, so the share sheet can
  /// offer Print, Save to Files and the rest.
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .pdf) { printout in
      RecipePDF.render(printout)
    }
    .suggestedFileName { $0.fileName }
  }
}
