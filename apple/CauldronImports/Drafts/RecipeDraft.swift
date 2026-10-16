import CauldronKit
import Foundation
// For `move(fromOffsets:toOffset:)`, which the lists reorder with.
import SwiftUI

/// A recipe as the editor holds it while it's being changed: what the cook typed, as text. The
/// editor changes this, not the saved recipe, so cancelling changes nothing and Save writes the
/// whole of it at once (`RecipeSaver`). Plain values, so all of it runs without a view.
public struct RecipeDraft: Equatable {
  // A field the importer flagged (`review`) stops being flagged once the cook changes it.
  public var title = "" {
    didSet { if title != oldValue { review.remove(.title) } }
  }
  public var summary = "" {
    didSet { if summary != oldValue { review.remove(.description) } }
  }
  public var servings = "" {
    didSet { if servings != oldValue { review.remove(.servings) } }
  }
  public var prepMinutes = "" {
    didSet { if prepMinutes != oldValue { review.remove(.prepMinutes) } }
  }
  public var cookMinutes = "" {
    didSet { if cookMinutes != oldValue { review.remove(.cookMinutes) } }
  }
  public var totalMinutes = "" {
    didSet { if totalMinutes != oldValue { review.remove(.totalMinutes) } }
  }
  /// Per serving, as typed.
  public var calories = "" {
    didSet { if calories != oldValue { review.remove(.macros) } }
  }
  public var protein = "" {
    didSet { if protein != oldValue { review.remove(.macros) } }
  }
  public var carbs = "" {
    didSet { if carbs != oldValue { review.remove(.macros) } }
  }
  public var fat = "" {
    didSet { if fat != oldValue { review.remove(.macros) } }
  }
  /// What the model estimated into the four fields above. Save keeps those numbers marked as
  /// an estimate for as long as the fields still hold them; changing one makes it the cook's.
  public var estimatedMacros: Macros?
  /// What the imported page published, the same way: Save marks those numbers as the page's
  /// for as long as the fields still hold them.
  public var pageMacros: Macros?
  /// The AI couldn't be reached (or was too slow) when an estimate was wanted, whether the
  /// cook asked or an import did, so Save queues one for the saved recipe (if there are no
  /// numbers by then).
  public var estimateOnSave = false
  public var sourceURL = "" {
    didSet { if sourceURL != oldValue { review.remove(.sourceUrl) } }
  }
  public var notes = "" {
    didSet { if notes != oldValue { review.remove(.notes) } }
  }
  public var tags: [String] = [] {
    didSet { if tags != oldValue { review.remove(.tags) } }
  }
  public var ingredients: [IngredientRowDraft] = [.line("")]
  public var steps: [StepRowDraft] = [.blank()]
  public var photo = PhotoChange.keep
  /// The stored list holds lines this build can't read, so the editor must not save over it
  /// (see `canRewriteIngredients` in docs/native/data-model.md). The rows are for showing.
  public var ingredientsLocked = false
  public var stepsLocked = false
  /// Set when the draft came from Distill: where it came from, which Save records.
  public var imported: ImportedFrom?
  /// The fields an importer wasn't sure of, shown in the Tips colour until the cook changes them.
  public var review: Set<DraftField> = []

  /// A new, empty recipe.
  public init() {}

  /// The four macro fields as numbers; a blank or invalid field is unknown.
  public var typedMacros: Macros {
    Macros(
      calories: Self.whole(calories, in: 0...RecipeLimits.calories).number.map(Double.init),
      protein: Self.grams(protein).number,
      carbs: Self.grams(carbs).number,
      fat: Self.grams(fat).number)
  }

  /// Puts an estimate into the macro fields, to be checked before saving.
  public mutating func fill(withEstimate macros: Macros) {
    calories = Self.text(macros.calories)
    protein = Self.text(macros.protein)
    carbs = Self.text(macros.carbs)
    fat = Self.text(macros.fat)
    // Read back from the fields, so what Save compares is what the cook sees.
    estimatedMacros = typedMacros
    estimateOnSave = false
    // An estimate is for the cook to check (`divine` in the web editor flags it the same way).
    review.insert(.macros)
  }

  /// Puts the numbers an imported page published into the macro fields.
  public mutating func fill(withPage macros: Macros) {
    calories = Self.text(macros.calories)
    protein = Self.text(macros.protein)
    carbs = Self.text(macros.carbs)
    fat = Self.text(macros.fat)
    pageMacros = typedMacros
  }

  /// What the model is asked to estimate from: the ingredient lines as currently typed, with
  /// section headings and blank rows left out.
  public var ingredientLines: [String] {
    ingredients.filter { !$0.isHeading && !$0.isBlank }.map { trimmed($0.text) }
  }

  /// The ask for an estimate, or nil when there is no ingredient to estimate from. Held to the
  /// limits the web editor holds it to (`MacroEstimateInput.limited`).
  public var estimateInput: MacroEstimateInput? {
    MacroEstimateInput.limited(
      title: title, servings: Self.whole(servings, in: 1...RecipeLimits.servings).number,
      lines: ingredientLines)
  }

  /// A number as a field shows it; blank for none.
  public static func text(_ number: Int?) -> String { number.map(String.init) ?? "" }

  public static func text(_ number: Double?) -> String {
    guard let number else { return "" }
    return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
  }

  // MARK: Ingredients

  /// Sets what a line says and reads it. Pasting several lines splits them into rows, with
  /// bullets dropped and a heading like "For the sauce:" becoming a section row. A line break at
  /// the end (the Return key) starts a new blank row. Returns the row to move to when the text
  /// was split, nil when it was plain typing.
  @discardableResult
  public mutating func setIngredientText(_ id: UUID, _ text: String) -> UUID? {
    guard let index = ingredients.firstIndex(where: { $0.id == id }) else { return nil }
    guard text.contains(where: \.isNewline) else {
      ingredients[index].setText(text)
      return nil
    }
    var rows = Self.ingredientPaste(text).map { IngredientRowDraft.reading($0) }
    if rows.isEmpty || text.last?.isNewline == true { rows.append(.line("")) }
    // The row being typed in keeps its identity, so the field keeps its focus until it moves.
    rows[0].id = id
    ingredients.replaceSubrange(index...index, with: rows)
    return rows.last?.id
  }

  /// Done typing in a line: a line that reads as a heading ("To serve:") becomes a section row.
  public mutating func commitIngredient(_ id: UUID) {
    guard let index = ingredients.firstIndex(where: { $0.id == id }),
      !ingredients[index].isHeading, let heading = readHeading(ingredients[index].text)
    else { return }
    ingredients[index] = .heading(heading, id: id)
  }

  public mutating func addIngredient(after id: UUID? = nil) {
    insert(.line(""), after: id)
  }

  public mutating func addHeading(after id: UUID? = nil) {
    insert(.heading(""), after: id)
  }

  private mutating func insert(_ row: IngredientRowDraft, after id: UUID?) {
    let index = id.flatMap { id in ingredients.firstIndex { $0.id == id } }
    ingredients.insert(row, at: index.map { $0 + 1 } ?? ingredients.endIndex)
  }

  public mutating func moveIngredients(from source: IndexSet, to destination: Int) {
    ingredients.move(fromOffsets: source, toOffset: destination)
  }

  /// Removes a row. The list never goes empty: the last one is left blank.
  public mutating func removeIngredient(_ id: UUID) {
    ingredients.removeAll { $0.id == id }
    if ingredients.isEmpty { ingredients = [.line("")] }
  }

  // MARK: Fixing a reading

  /// Changes how a line was read, by hand (`onCorrect` in `IngredientRows.tsx`).
  public mutating func correctIngredient(_ id: UUID, _ change: (inout ParsedIngredient) -> Void) {
    guard let index = ingredients.firstIndex(where: { $0.id == id }) else { return }
    ingredients[index].correct(change)
  }

  /// Sets a line's amount from what the cook typed ("1 1/2", "2-3", blank for none). Returns
  /// false and changes nothing when the text isn't an amount, for the field to say so.
  @discardableResult
  public mutating func setIngredientQuantity(_ id: UUID, from text: String) -> Bool {
    switch readQuantityEntry(text) {
    case .invalid: return false
    case .blank: correctIngredient(id) { $0.quantity = nil }
    case .value(let quantity): correctIngredient(id) { $0.quantity = quantity }
    }
    return true
  }

  public mutating func setIngredientUnit(_ id: UUID, _ unit: UnitCode?) {
    correctIngredient(id) { $0.unit = unit }
  }

  public mutating func setIngredientItem(_ id: UUID, _ item: String) {
    correctIngredient(id) { $0.item = item }
  }

  /// A blank note is no note.
  public mutating func setIngredientNote(_ id: UUID, _ note: String) {
    correctIngredient(id) { $0.note = note.isEmpty ? nil : note }
  }

  public mutating func setIngredientOptional(_ id: UUID, _ optional: Bool) {
    correctIngredient(id) { $0.optional = optional }
  }

  /// Reads a line from its text again, undoing fixes made by hand.
  public mutating func resetIngredient(_ id: UUID) {
    guard let index = ingredients.firstIndex(where: { $0.id == id }) else { return }
    ingredients[index].resetReading()
  }

  private static func ingredientPaste(_ pasted: String) -> [String] {
    pasted.split(whereSeparator: \.isNewline)
      .map { line in
        String(line).replacingOccurrences(
          of: #"^\s*[-•*▢□◦‣]\s*"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }
  }

  // MARK: Steps

  /// Sets what a step says. Its timer follows the text until the cook clears it. Pasting a
  /// whole method splits it into steps, without their numbers, and a line break at the end (the
  /// Return key) starts a new step. Returns the step to move to when the text was split.
  @discardableResult
  public mutating func setStepText(_ id: UUID, _ text: String) -> UUID? {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return nil }
    guard text.contains(where: \.isNewline) else {
      steps[index].setText(text)
      return nil
    }
    var rows = Self.stepPaste(text).map { chunk -> StepRowDraft in
      var row = StepRowDraft.blank()
      row.section = steps[index].section
      row.setText(chunk)
      return row
    }
    if rows.isEmpty || text.last?.isNewline == true { rows.append(.blank()) }
    rows[0].id = id
    steps.replaceSubrange(index...index, with: rows)
    return rows.last?.id
  }

  public mutating func addStep(after id: UUID? = nil) {
    let index = id.flatMap { id in steps.firstIndex { $0.id == id } }
    steps.insert(.blank(), at: index.map { $0 + 1 } ?? steps.endIndex)
  }

  public mutating func moveSteps(from source: IndexSet, to destination: Int) {
    steps.move(fromOffsets: source, toOffset: destination)
  }

  public mutating func removeStep(_ id: UUID) {
    steps.removeAll { $0.id == id }
    if steps.isEmpty { steps = [.blank()] }
  }

  public mutating func clearTimer(_ id: UUID) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
    steps[index].timerSeconds = nil
    steps[index].timerSet = true
  }

  /// Sets a step's timer from minutes typed into its field (`Timer` in `StepRows.tsx`): blank
  /// or zero removes it, a number sets it (held to the limit), and anything else leaves it. Once
  /// set by hand the timer no longer follows the step's text.
  public mutating func setTimer(_ id: UUID, minutes text: String) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
    switch readStepTimerEntry(minutes: text) {
    case .clear:
      clearTimer(id)
    case .set(let seconds):
      steps[index].timerSeconds = seconds
      steps[index].timerSet = true
    case .unchanged:
      break
    }
  }

  private static func stepPaste(_ pasted: String) -> [String] {
    let normalized = pasted.replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let paragraphs = normalized.components(separatedBy: "\n").contains {
      $0.allSatisfy(\.isWhitespace)
    }
    let chunks =
      paragraphs
      ? normalized.replacingOccurrences(of: #"\n\s*\n"#, with: "\u{0}", options: .regularExpression)
        .components(separatedBy: "\u{0}")
      : normalized.components(separatedBy: "\n")
    return chunks.map { chunk in
      chunk.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
        .replacingOccurrences(
          of: #"^\s*(?:[-•*▢□◦‣]|\d+[.)](?=\s)|step\s+\d+[.:)]?)\s*"#, with: "",
          options: [.regularExpression, .caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
  }

  // MARK: Tags

  /// Adds a tag, trimmed. A tag that's already there, in any case, isn't added again.
  public mutating func addTag(_ name: String) {
    let name = name.trimmingCharacters(
      in: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    guard !name.isEmpty, !tags.contains(where: { $0.lowercased() == name.lowercased() }) else {
      return
    }
    tags.append(name)
  }

  public mutating func removeTag(_ name: String) {
    tags.removeAll { $0.lowercased() == name.lowercased() }
  }
}

/// Where a draft from Distill came from, and how far to trust it.
public struct ImportedFrom: Equatable {
  public var platform: SourcePlatform
  public var author: String?
  /// The site or account, for the source note. Not stored on the recipe.
  public var siteName: String?
  /// When the page was fetched; nil for pasted text.
  public var fetchedAt: Date?
  /// The on-device model read it because the AI couldn't be reached.
  public var rough: Bool
  public init(
    platform: SourcePlatform, author: String?, siteName: String?, fetchedAt: Date?, rough: Bool
  ) {
    self.platform = platform
    self.author = author
    self.siteName = siteName
    self.fetchedAt = fetchedAt
    self.rough = rough
  }
}

/// What Save does to the recipe's photo.
public enum PhotoChange: Equatable {
  case keep
  case replace(ProcessedPhoto)
  case remove
}

/// One row of the ingredient list: a line the cook typed and how it was read, or a section
/// heading.
public struct IngredientRowDraft: Equatable, Identifiable {
  public var id = UUID()
  public private(set) var isHeading: Bool
  /// What was typed, or the heading's name.
  public private(set) var text: String
  /// How the line was read; nil for a heading. A stored line keeps its stored reading until
  /// its text changes.
  public private(set) var parsed: ParsedIngredient?
  /// The importer wasn't sure it read this line right. Editing the line clears it.
  public private(set) var flagged = false
  /// The cook changed the reading by hand, or the stored one differs from what the parser
  /// makes of the text. Retyping the line reads it again and clears this.
  public private(set) var corrected = false

  public static func line(_ text: String) -> IngredientRowDraft {
    IngredientRowDraft(
      isHeading: false, text: text, parsed: text.isEmpty ? nil : parseIngredientLine(text))
  }

  /// A line from an importer, flagged when it wasn't sure of it.
  public static func imported(_ text: String, flagged: Bool) -> IngredientRowDraft {
    var row = IngredientRowDraft.line(text)
    row.flagged = flagged
    return row
  }

  public static func heading(_ text: String, id: UUID = UUID()) -> IngredientRowDraft {
    IngredientRowDraft(id: id, isHeading: true, text: text, parsed: nil)
  }

  /// A pasted line: a heading if it reads as one, otherwise a line.
  public static func reading(_ text: String) -> IngredientRowDraft {
    readHeading(text).map { .heading($0) } ?? .line(text)
  }

  /// A row kept in an unfinished draft, as it was.
  public static func restored(
    heading: Bool, text: String, parsed: ParsedIngredient?, corrected: Bool
  )
    -> IngredientRowDraft
  {
    var row = IngredientRowDraft(
      isHeading: heading, text: text,
      parsed: heading ? nil : parsed ?? (text.isEmpty ? nil : parseIngredientLine(text)))
    row.corrected = !heading && corrected
    return row
  }

  public static func stored(_ ingredient: Ingredient) -> IngredientRowDraft {
    let stored = ParsedIngredient(
      quantity: ingredient.quantity, unit: ingredient.unit, item: ingredient.item,
      note: ingredient.note, optional: ingredient.optional, alt: ingredient.alt,
      original: ingredient.original)
    var row = IngredientRowDraft(isHeading: false, text: ingredient.original, parsed: stored)
    row.corrected = !stored.sameReading(as: parseIngredientLine(ingredient.original))
    return row
  }

  public mutating func setText(_ newText: String) {
    if newText != text { flagged = false }
    text = newText
    corrected = false
    if !isHeading { parsed = newText.isEmpty ? nil : parseIngredientLine(newText) }
  }

  /// Changes how the line was read, by hand. The text stays as typed; the reading is what is
  /// saved (quantity, unit, item, note), so a fix made here is not undone by saving.
  public mutating func correct(_ change: (inout ParsedIngredient) -> Void) {
    guard !isHeading, var reading = parsed else { return }
    change(&reading)
    parsed = reading
    corrected = true
    flagged = false
  }

  /// Reads the line from its text again, undoing hand fixes.
  public mutating func resetReading() {
    guard !isHeading else { return }
    parsed = isBlank ? nil : parseIngredientLine(text)
    corrected = false
  }

  public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  /// The reading, as the editor shows it under the line: what was read, not converted, so the
  /// cook sees what a fix would change.
  public var reading: Reading? {
    guard let parsed else { return nil }
    return Reading(
      amount: parsed.quantity.map { formatQuantity($0, unit: parsed.unit) },
      unit: parsed.unit?.editorLabel, item: parsed.item,
      note: parsed.note, optional: parsed.optional,
      alt: parsed.alt.map {
        Reading.Alt(
          amount: formatQuantity($0.quantity, unit: $0.unit), unit: $0.unit.editorLabel)
      })
  }

  /// Whether the reading says more than the text does: an amount, a note, or an item that
  /// isn't just the line. A plain "salt" has nothing to add.
  public var readingAddsToText: Bool {
    guard let reading else { return false }
    return reading.amount != nil || reading.note != nil || reading.optional || reading.alt != nil
      || reading.item != text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public struct Reading: Equatable {
    public var amount: String?
    public var unit: String?
    public var item: String
    public var note: String?
    public var optional: Bool
    /// The second measure of the same amount, like the "(190g)" in "1 1/2 cups (190g) flour".
    public var alt: Alt?

    public struct Alt: Equatable {
      public var amount: String
      public var unit: String
    }

    public init(
      amount: String?, unit: String?, item: String, note: String?, optional: Bool, alt: Alt? = nil
    ) {
      self.amount = amount
      self.unit = unit
      self.item = item
      self.note = note
      self.optional = optional
      self.alt = alt
    }
  }
}

/// One step of the method.
public struct StepRowDraft: Equatable, Identifiable {
  public var id = UUID()
  public private(set) var text: String
  public var section: String?
  public var timerSeconds: Int?
  /// The cook cleared the timer, or it came with a stored recipe that doesn't follow its text,
  /// so editing the text no longer changes it.
  public var timerSet: Bool
  /// The importer wasn't sure it read this step right. Editing the step clears it.
  public private(set) var flagged = false

  /// A step from an importer, flagged when it wasn't sure of it.
  public static func imported(_ text: String, section: String?, flagged: Bool) -> StepRowDraft {
    var row = StepRowDraft.blank()
    row.section = section
    row.setText(text)
    row.flagged = flagged
    return row
  }

  /// A step kept in an unfinished draft, as it was.
  public static func restored(text: String, section: String?, timerSeconds: Int?, timerSet: Bool)
    -> StepRowDraft
  {
    StepRowDraft(text: text, section: section, timerSeconds: timerSeconds, timerSet: timerSet)
  }

  public static func blank() -> StepRowDraft {
    StepRowDraft(text: "", section: nil, timerSeconds: nil, timerSet: false)
  }

  public static func stored(_ step: Step) -> StepRowDraft {
    StepRowDraft(
      text: step.text, section: step.section, timerSeconds: step.timerSeconds,
      timerSet: step.timerSeconds != detectTimer(step.text))
  }

  public mutating func setText(_ newText: String) {
    if newText != text { flagged = false }
    text = newText
    if !timerSet { timerSeconds = detectTimer(newText) }
  }

  public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension ParsedIngredient {
  /// Whether two readings say the same thing. The original line is not part of it.
  public func sameReading(as other: ParsedIngredient) -> Bool {
    quantity == other.quantity && unit == other.unit && item == other.item && note == other.note
      && optional == other.optional && alt == other.alt
  }
}
