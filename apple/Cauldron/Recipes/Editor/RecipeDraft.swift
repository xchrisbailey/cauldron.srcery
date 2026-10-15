import CauldronKit
import Foundation

/// A recipe as the editor holds it while it's being changed: what the cook typed, as text. The
/// editor changes this, not the saved recipe, so cancelling changes nothing and Save writes the
/// whole of it at once (`RecipeSaver`). Plain values, so all of it runs without a view.
struct RecipeDraft: Equatable {
  // A field the importer flagged (`review`) stops being flagged once the cook changes it.
  var title = "" {
    didSet { if title != oldValue { review.remove(.title) } }
  }
  var summary = "" {
    didSet { if summary != oldValue { review.remove(.description) } }
  }
  var servings = "" {
    didSet { if servings != oldValue { review.remove(.servings) } }
  }
  var prepMinutes = "" {
    didSet { if prepMinutes != oldValue { review.remove(.prepMinutes) } }
  }
  var cookMinutes = "" {
    didSet { if cookMinutes != oldValue { review.remove(.cookMinutes) } }
  }
  var totalMinutes = "" {
    didSet { if totalMinutes != oldValue { review.remove(.totalMinutes) } }
  }
  /// Per serving, as typed.
  var calories = "" {
    didSet { if calories != oldValue { review.remove(.macros) } }
  }
  var protein = "" {
    didSet { if protein != oldValue { review.remove(.macros) } }
  }
  var carbs = "" {
    didSet { if carbs != oldValue { review.remove(.macros) } }
  }
  var fat = "" {
    didSet { if fat != oldValue { review.remove(.macros) } }
  }
  /// What the model estimated into the four fields above. Save keeps those numbers marked as
  /// an estimate for as long as the fields still hold them; changing one makes it the cook's.
  var estimatedMacros: Macros?
  /// What the imported page published, the same way: Save marks those numbers as the page's
  /// for as long as the fields still hold them.
  var pageMacros: Macros?
  /// The AI couldn't be reached (or was too slow) when an estimate was wanted, whether the
  /// cook asked or an import did, so Save queues one for the saved recipe (if there are no
  /// numbers by then).
  var estimateOnSave = false
  var sourceURL = "" {
    didSet { if sourceURL != oldValue { review.remove(.sourceUrl) } }
  }
  var notes = "" {
    didSet { if notes != oldValue { review.remove(.notes) } }
  }
  var tags: [String] = [] {
    didSet { if tags != oldValue { review.remove(.tags) } }
  }
  var ingredients: [IngredientRowDraft] = [.line("")]
  var steps: [StepRowDraft] = [.blank()]
  var photo = PhotoChange.keep
  /// The stored list holds lines this build can't read, so the editor must not save over it
  /// (see `canRewriteIngredients` in docs/native/data-model.md). The rows are for showing.
  var ingredientsLocked = false
  var stepsLocked = false
  /// Set when the draft came from Distill: where it came from, which Save records.
  var imported: ImportedFrom?
  /// The fields an importer wasn't sure of, shown in the Tips colour until the cook changes them.
  var review: Set<DraftField> = []

  /// A new, empty recipe.
  init() {}

  init(_ recipe: RecipeRecord) {
    title = recipe.title
    summary = recipe.summary ?? ""
    servings = Self.text(recipe.servings)
    prepMinutes = Self.text(recipe.prepMinutes)
    cookMinutes = Self.text(recipe.cookMinutes)
    totalMinutes = Self.text(recipe.totalMinutes)
    let macros = recipe.macros
    calories = Self.text(macros.calories)
    protein = Self.text(macros.protein)
    carbs = Self.text(macros.carbs)
    fat = Self.text(macros.fat)
    sourceURL = recipe.sourceURL ?? ""
    notes = recipe.notes ?? ""
    tags = (recipe.tags ?? []).map(\.name).sorted()
    ingredientsLocked = !recipe.canRewriteIngredients
    stepsLocked = !recipe.canRewriteSteps

    let rows = withHeadings(recipe.ingredients).map { row -> IngredientRowDraft in
      switch row {
      case .heading(let name): .heading(name)
      case .line(let ingredient): .stored(ingredient)
      }
    }
    ingredients = rows.isEmpty ? [.line("")] : rows
    let stored = recipe.steps.map(StepRowDraft.stored)
    steps = stored.isEmpty ? [.blank()] : stored
  }

  /// The four macro fields as numbers; a blank or invalid field is unknown.
  var typedMacros: Macros {
    Macros(
      calories: Self.whole(calories, in: 0...RecipeLimits.calories).number.map(Double.init),
      protein: Self.grams(protein).number,
      carbs: Self.grams(carbs).number,
      fat: Self.grams(fat).number)
  }

  /// Puts an estimate into the macro fields, to be checked before saving.
  mutating func fill(withEstimate macros: Macros) {
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
  mutating func fill(withPage macros: Macros) {
    calories = Self.text(macros.calories)
    protein = Self.text(macros.protein)
    carbs = Self.text(macros.carbs)
    fat = Self.text(macros.fat)
    pageMacros = typedMacros
  }

  /// What the model is asked to estimate from: the ingredient lines as currently typed, with
  /// section headings and blank rows left out.
  var ingredientLines: [String] {
    ingredients.filter { !$0.isHeading && !$0.isBlank }.map { trimmed($0.text) }
  }

  /// The ask for an estimate, or nil when there is no ingredient to estimate from. Held to the
  /// limits the web editor holds it to (`MacroEstimateInput.limited`).
  var estimateInput: MacroEstimateInput? {
    MacroEstimateInput.limited(
      title: title, servings: Self.whole(servings, in: 1...RecipeLimits.servings).number,
      lines: ingredientLines)
  }

  private static func text(_ number: Int?) -> String { number.map(String.init) ?? "" }

  private static func text(_ number: Double?) -> String {
    guard let number else { return "" }
    return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
  }

  // MARK: Ingredients

  /// Sets what a line says and reads it. Pasting several lines splits them into rows, with
  /// bullets dropped and a heading like "For the sauce:" becoming a section row. A line break at
  /// the end (the Return key) starts a new blank row. Returns the row to move to when the text
  /// was split, nil when it was plain typing.
  @discardableResult
  mutating func setIngredientText(_ id: UUID, _ text: String) -> UUID? {
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
  mutating func commitIngredient(_ id: UUID) {
    guard let index = ingredients.firstIndex(where: { $0.id == id }),
      !ingredients[index].isHeading, let heading = readHeading(ingredients[index].text)
    else { return }
    ingredients[index] = .heading(heading, id: id)
  }

  mutating func addIngredient(after id: UUID? = nil) {
    insert(.line(""), after: id)
  }

  mutating func addHeading(after id: UUID? = nil) {
    insert(.heading(""), after: id)
  }

  private mutating func insert(_ row: IngredientRowDraft, after id: UUID?) {
    let index = id.flatMap { id in ingredients.firstIndex { $0.id == id } }
    ingredients.insert(row, at: index.map { $0 + 1 } ?? ingredients.endIndex)
  }

  mutating func moveIngredients(from source: IndexSet, to destination: Int) {
    ingredients.move(fromOffsets: source, toOffset: destination)
  }

  /// Removes a row. The list never goes empty: the last one is left blank.
  mutating func removeIngredient(_ id: UUID) {
    ingredients.removeAll { $0.id == id }
    if ingredients.isEmpty { ingredients = [.line("")] }
  }

  // MARK: Fixing a reading

  /// Changes how a line was read, by hand (`onCorrect` in `IngredientRows.tsx`).
  mutating func correctIngredient(_ id: UUID, _ change: (inout ParsedIngredient) -> Void) {
    guard let index = ingredients.firstIndex(where: { $0.id == id }) else { return }
    ingredients[index].correct(change)
  }

  /// Sets a line's amount from what the cook typed ("1 1/2", "2-3", blank for none). Returns
  /// false and changes nothing when the text isn't an amount, for the field to say so.
  @discardableResult
  mutating func setIngredientQuantity(_ id: UUID, from text: String) -> Bool {
    switch readQuantityEntry(text) {
    case .invalid: return false
    case .blank: correctIngredient(id) { $0.quantity = nil }
    case .value(let quantity): correctIngredient(id) { $0.quantity = quantity }
    }
    return true
  }

  mutating func setIngredientUnit(_ id: UUID, _ unit: UnitCode?) {
    correctIngredient(id) { $0.unit = unit }
  }

  mutating func setIngredientItem(_ id: UUID, _ item: String) {
    correctIngredient(id) { $0.item = item }
  }

  /// A blank note is no note.
  mutating func setIngredientNote(_ id: UUID, _ note: String) {
    correctIngredient(id) { $0.note = note.isEmpty ? nil : note }
  }

  mutating func setIngredientOptional(_ id: UUID, _ optional: Bool) {
    correctIngredient(id) { $0.optional = optional }
  }

  /// Reads a line from its text again, undoing fixes made by hand.
  mutating func resetIngredient(_ id: UUID) {
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
  mutating func setStepText(_ id: UUID, _ text: String) -> UUID? {
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

  mutating func addStep(after id: UUID? = nil) {
    let index = id.flatMap { id in steps.firstIndex { $0.id == id } }
    steps.insert(.blank(), at: index.map { $0 + 1 } ?? steps.endIndex)
  }

  mutating func moveSteps(from source: IndexSet, to destination: Int) {
    steps.move(fromOffsets: source, toOffset: destination)
  }

  mutating func removeStep(_ id: UUID) {
    steps.removeAll { $0.id == id }
    if steps.isEmpty { steps = [.blank()] }
  }

  mutating func clearTimer(_ id: UUID) {
    guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
    steps[index].timerSeconds = nil
    steps[index].timerSet = true
  }

  /// Sets a step's timer from minutes typed into its field (`Timer` in `StepRows.tsx`): blank
  /// or zero removes it, a number sets it (held to the limit), and anything else leaves it. Once
  /// set by hand the timer no longer follows the step's text.
  mutating func setTimer(_ id: UUID, minutes text: String) {
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
  mutating func addTag(_ name: String) {
    let name = name.trimmingCharacters(
      in: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
    guard !name.isEmpty, !tags.contains(where: { $0.lowercased() == name.lowercased() }) else {
      return
    }
    tags.append(name)
  }

  mutating func removeTag(_ name: String) {
    tags.removeAll { $0.lowercased() == name.lowercased() }
  }
}

/// Where a draft from Distill came from, and how far to trust it.
struct ImportedFrom: Equatable {
  var platform: SourcePlatform
  var author: String?
  /// The site or account, for the source note. Not stored on the recipe.
  var siteName: String?
  /// When the page was fetched; nil for pasted text.
  var fetchedAt: Date?
  /// The on-device model read it because the AI couldn't be reached.
  var rough: Bool
}

/// What Save does to the recipe's photo.
enum PhotoChange: Equatable {
  case keep
  case replace(ProcessedPhoto)
  case remove
}

/// One row of the ingredient list: a line the cook typed and how it was read, or a section
/// heading.
struct IngredientRowDraft: Equatable, Identifiable {
  var id = UUID()
  private(set) var isHeading: Bool
  /// What was typed, or the heading's name.
  private(set) var text: String
  /// How the line was read; nil for a heading. A stored line keeps its stored reading until
  /// its text changes.
  private(set) var parsed: ParsedIngredient?
  /// The importer wasn't sure it read this line right. Editing the line clears it.
  private(set) var flagged = false
  /// The cook changed the reading by hand, or the stored one differs from what the parser
  /// makes of the text. Retyping the line reads it again and clears this.
  private(set) var corrected = false

  static func line(_ text: String) -> IngredientRowDraft {
    IngredientRowDraft(
      isHeading: false, text: text, parsed: text.isEmpty ? nil : parseIngredientLine(text))
  }

  /// A line from an importer, flagged when it wasn't sure of it.
  static func imported(_ text: String, flagged: Bool) -> IngredientRowDraft {
    var row = IngredientRowDraft.line(text)
    row.flagged = flagged
    return row
  }

  static func heading(_ text: String, id: UUID = UUID()) -> IngredientRowDraft {
    IngredientRowDraft(id: id, isHeading: true, text: text, parsed: nil)
  }

  /// A pasted line: a heading if it reads as one, otherwise a line.
  static func reading(_ text: String) -> IngredientRowDraft {
    readHeading(text).map { .heading($0) } ?? .line(text)
  }

  /// A row kept in an unfinished draft, as it was.
  static func restored(heading: Bool, text: String, parsed: ParsedIngredient?, corrected: Bool)
    -> IngredientRowDraft
  {
    var row = IngredientRowDraft(
      isHeading: heading, text: text,
      parsed: heading ? nil : parsed ?? (text.isEmpty ? nil : parseIngredientLine(text)))
    row.corrected = !heading && corrected
    return row
  }

  static func stored(_ ingredient: Ingredient) -> IngredientRowDraft {
    let stored = ParsedIngredient(
      quantity: ingredient.quantity, unit: ingredient.unit, item: ingredient.item,
      note: ingredient.note, optional: ingredient.optional, alt: ingredient.alt,
      original: ingredient.original)
    var row = IngredientRowDraft(isHeading: false, text: ingredient.original, parsed: stored)
    row.corrected = !stored.sameReading(as: parseIngredientLine(ingredient.original))
    return row
  }

  mutating func setText(_ newText: String) {
    if newText != text { flagged = false }
    text = newText
    corrected = false
    if !isHeading { parsed = newText.isEmpty ? nil : parseIngredientLine(newText) }
  }

  /// Changes how the line was read, by hand. The text stays as typed; the reading is what is
  /// saved (quantity, unit, item, note), so a fix made here is not undone by saving.
  mutating func correct(_ change: (inout ParsedIngredient) -> Void) {
    guard !isHeading, var reading = parsed else { return }
    change(&reading)
    parsed = reading
    corrected = true
    flagged = false
  }

  /// Reads the line from its text again, undoing hand fixes.
  mutating func resetReading() {
    guard !isHeading else { return }
    parsed = isBlank ? nil : parseIngredientLine(text)
    corrected = false
  }

  var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  /// The reading, as the editor shows it under the line: what was read, not converted, so the
  /// cook sees what a fix would change.
  var reading: Reading? {
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
  var readingAddsToText: Bool {
    guard let reading else { return false }
    return reading.amount != nil || reading.note != nil || reading.optional || reading.alt != nil
      || reading.item != text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  struct Reading: Equatable {
    var amount: String?
    var unit: String?
    var item: String
    var note: String?
    var optional: Bool
    /// The second measure of the same amount, like the "(190g)" in "1 1/2 cups (190g) flour".
    var alt: Alt?

    struct Alt: Equatable {
      var amount: String
      var unit: String
    }

    init(
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
struct StepRowDraft: Equatable, Identifiable {
  var id = UUID()
  private(set) var text: String
  var section: String?
  var timerSeconds: Int?
  /// The cook cleared the timer, or it came with a stored recipe that doesn't follow its text,
  /// so editing the text no longer changes it.
  var timerSet: Bool
  /// The importer wasn't sure it read this step right. Editing the step clears it.
  private(set) var flagged = false

  /// A step from an importer, flagged when it wasn't sure of it.
  static func imported(_ text: String, section: String?, flagged: Bool) -> StepRowDraft {
    var row = StepRowDraft.blank()
    row.section = section
    row.setText(text)
    row.flagged = flagged
    return row
  }

  /// A step kept in an unfinished draft, as it was.
  static func restored(text: String, section: String?, timerSeconds: Int?, timerSet: Bool)
    -> StepRowDraft
  {
    StepRowDraft(text: text, section: section, timerSeconds: timerSeconds, timerSet: timerSet)
  }

  static func blank() -> StepRowDraft {
    StepRowDraft(text: "", section: nil, timerSeconds: nil, timerSet: false)
  }

  static func stored(_ step: Step) -> StepRowDraft {
    StepRowDraft(
      text: step.text, section: step.section, timerSeconds: step.timerSeconds,
      timerSet: step.timerSeconds != detectTimer(step.text))
  }

  mutating func setText(_ newText: String) {
    if newText != text { flagged = false }
    text = newText
    if !timerSet { timerSeconds = detectTimer(newText) }
  }

  var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

extension ParsedIngredient {
  /// Whether two readings say the same thing. The original line is not part of it.
  func sameReading(as other: ParsedIngredient) -> Bool {
    quantity == other.quantity && unit == other.unit && item == other.item && note == other.note
      && optional == other.optional && alt == other.alt
  }
}
