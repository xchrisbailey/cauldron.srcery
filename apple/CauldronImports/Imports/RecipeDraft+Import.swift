import CauldronKit
import Foundation

extension RecipeDraft {
  /// A draft from Distill, ready for the editor (`fromDraft` in the web app's `recipe-form.ts`).
  /// Every field the pipeline read is carried over as text, ingredient lines are read by the
  /// line parser as typed ones are, the lines and steps it wasn't sure of are flagged, and so
  /// are the fields in `unsure`. Nothing is stored: the cook reviews it and saves.
  ///
  /// - Parameters:
  ///   - distilled: what the pipeline read.
  ///   - photo: the cover photo the app fetched, if any.
  ///   - link: a link to keep as the source when the text was pasted after the link couldn't be
  ///     read.
  ///   - fetchedAt: when the page was fetched; nil for pasted text.
  public init(
    importing distilled: Distilled, photo: ProcessedPhoto?, link: String?, fetchedAt: Date?
  ) {
    self.init()
    let draft = distilled.draft
    let kept = link.map { (platform: Distill.classify($0), url: Distill.normalizeURL($0)) }

    title = draft.title
    summary = draft.description ?? ""
    servings = Self.number(draft.servings)
    prepMinutes = Self.number(draft.prepMinutes)
    cookMinutes = Self.number(draft.cookMinutes)
    totalMinutes = Self.number(draft.totalMinutes)
    if let macros = draft.macros, macros != .none { fill(withPage: macros) }
    // No numbers from the page: the app asks for an estimate, and if that can't be had Save
    // queues it (`ImportModel`).
    estimateOnSave = distilled.macroEstimate != nil
    sourceURL = kept?.url ?? draft.sourceUrl ?? ""
    notes = draft.notes ?? ""
    tags = draft.tags

    var rows: [IngredientRowDraft] = []
    var section: String?
    for ingredient in draft.ingredients {
      if ingredient.section != section {
        section = ingredient.section
        if let section { rows.append(.heading(section)) }
      }
      rows.append(.imported(ingredient.line, flagged: ingredient.unsure))
    }
    ingredients = rows.isEmpty ? [.line("")] : rows
    let methods = draft.steps.map {
      StepRowDraft.imported($0.text, section: $0.section, flagged: $0.unsure)
    }
    steps = methods.isEmpty ? [.blank()] : methods

    if let photo { self.photo = .replace(photo) }
    imported = ImportedFrom(
      platform: kept?.platform.sourcePlatform ?? draft.sourcePlatform.sourcePlatform,
      author: draft.sourceAuthor, siteName: draft.siteName, fetchedAt: fetchedAt,
      rough: distilled.rough)
    // Last, so putting the values in above doesn't count as the cook changing them.
    review = Set(draft.unsure)
  }

  /// Whether anything in the draft is flagged for a second look.
  public var needsReview: Bool {
    !review.isEmpty || ingredients.contains(where: \.flagged) || steps.contains(where: \.flagged)
  }

  private static func number(_ value: Int?) -> String { value.map(String.init) ?? "" }
}

extension ImportSource {
  /// The same place, as a recipe records it.
  public var sourcePlatform: SourcePlatform { SourcePlatform(rawValue: rawValue) ?? .manual }
}
