import CauldronKit
import Foundation

/// What the editor keeps of a new recipe's draft, as stored. Row ids are not kept: they are only
/// for the list in front of the cook.
public struct KeptDraft: Codable, Equatable {
  /// Bump when the shape changes; a draft with another version is dropped.
  public static let currentVersion = 1

  public struct Line: Codable, Equatable {
    public var heading: Bool
    public var text: String
    public var parsed: ParsedIngredient?
    public var corrected: Bool
  }

  public struct Step: Codable, Equatable {
    public var text: String
    public var section: String?
    public var timerSeconds: Int?
    public var timerSet: Bool
  }

  public struct Photo: Codable, Equatable {
    public var data: Data
    public var width: Int
    public var height: Int
  }

  public var version = KeptDraft.currentVersion
  public var title: String
  public var summary: String
  public var servings: String
  public var prepMinutes: String
  public var cookMinutes: String
  public var totalMinutes: String
  public var calories: String
  public var protein: String
  public var carbs: String
  public var fat: String
  public var estimatedMacros: Macros?
  public var estimateOnSave: Bool
  public var sourceURL: String
  public var notes: String
  public var tags: [String]
  public var ingredients: [Line]
  public var steps: [Step]
  public var photo: Photo?

  public init(_ draft: RecipeDraft) {
    title = draft.title
    summary = draft.summary
    servings = draft.servings
    prepMinutes = draft.prepMinutes
    cookMinutes = draft.cookMinutes
    totalMinutes = draft.totalMinutes
    calories = draft.calories
    protein = draft.protein
    carbs = draft.carbs
    fat = draft.fat
    estimatedMacros = draft.estimatedMacros
    estimateOnSave = draft.estimateOnSave
    sourceURL = draft.sourceURL
    notes = draft.notes
    tags = draft.tags
    ingredients = draft.ingredients.map {
      Line(heading: $0.isHeading, text: $0.text, parsed: $0.parsed, corrected: $0.corrected)
    }
    steps = draft.steps.map {
      Step(
        text: $0.text, section: $0.section, timerSeconds: $0.timerSeconds, timerSet: $0.timerSet)
    }
    if case .replace(let processed) = draft.photo {
      photo = Photo(data: processed.data, width: processed.width, height: processed.height)
    }
  }

  /// Nothing worth keeping: no text anywhere (blank lines and spaces don't count), no tag, no
  /// number and no photo. An empty draft is cleared rather than kept.
  public var isEmpty: Bool {
    let texts = [
      title, summary, servings, prepMinutes, cookMinutes, totalMinutes, calories, protein, carbs,
      fat, sourceURL, notes,
    ]
    return texts.allSatisfy(Self.isBlank) && tags.isEmpty && photo == nil
      && ingredients.allSatisfy { Self.isBlank($0.text) }
      && steps.allSatisfy { Self.isBlank($0.text) }
  }

  private static func isBlank(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The draft to open the editor on, with a blank row where a list has none.
  public var draft: RecipeDraft {
    var draft = RecipeDraft()
    draft.title = title
    draft.summary = summary
    draft.servings = servings
    draft.prepMinutes = prepMinutes
    draft.cookMinutes = cookMinutes
    draft.totalMinutes = totalMinutes
    draft.calories = calories
    draft.protein = protein
    draft.carbs = carbs
    draft.fat = fat
    draft.estimatedMacros = estimatedMacros
    draft.estimateOnSave = estimateOnSave
    draft.sourceURL = sourceURL
    draft.notes = notes
    draft.tags = tags
    let lines = ingredients.map {
      IngredientRowDraft.restored(
        heading: $0.heading, text: $0.text, parsed: $0.parsed, corrected: $0.corrected)
    }
    draft.ingredients = lines.isEmpty ? [.line("")] : lines
    let methods = steps.map {
      StepRowDraft.restored(
        text: $0.text, section: $0.section, timerSeconds: $0.timerSeconds, timerSet: $0.timerSet)
    }
    draft.steps = methods.isEmpty ? [.blank()] : methods
    if let photo {
      draft.photo = .replace(
        ProcessedPhoto(data: photo.data, width: photo.width, height: photo.height))
    }
    return draft
  }
}
