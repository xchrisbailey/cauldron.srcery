import CauldronKit
import Foundation

extension RecipeDraft {
  /// Where a problem is: a field, or a row of the ingredient list or the method.
  enum Field: Hashable {
    case title, summary, servings, prepMinutes, cookMinutes, totalMinutes
    case calories, protein, carbs, fat
    case sourceURL, notes, tags
    case ingredientList, stepList
    case ingredient(UUID)
    case step(UUID)
  }

  /// What's wrong with a draft, by field, in the copy module's plain words. It checks what the
  /// web editor checks (the limits in `RecipeLimits`), so a recipe is valid on every device.
  struct Errors {
    fileprivate(set) var byField: [Field: CopyString] = [:]

    subscript(field: Field) -> CopyString? { byField[field] }
    var isEmpty: Bool { byField.isEmpty }

    /// The first problem found for a field wins, as in the web editor.
    fileprivate mutating func add(_ field: Field, _ message: CopyString) {
      if byField[field] == nil { byField[field] = message }
    }
  }

  func validate() -> Errors {
    var errors = Errors()
    let validation = Copy.validation

    func tooLong(_ field: Field, _ value: String, _ max: Int) {
      if value.count > max { errors.add(field, validation.tooLong(max)) }
    }

    let title = trimmed(title)
    if title.isEmpty { errors.add(.title, validation.required) }
    tooLong(.title, title, RecipeLimits.title)
    tooLong(.summary, trimmed(summary), RecipeLimits.description)
    tooLong(.notes, trimmed(notes), RecipeLimits.notes)

    if Self.whole(servings, in: 1...RecipeLimits.servings) == .invalid {
      errors.add(.servings, validation.wholeNumber(1, RecipeLimits.servings))
    }
    for (field, value) in [
      (Field.prepMinutes, prepMinutes), (.cookMinutes, cookMinutes), (.totalMinutes, totalMinutes),
    ] where Self.whole(value, in: 0...RecipeLimits.minutes) == .invalid {
      errors.add(field, validation.wholeNumber(0, RecipeLimits.minutes))
    }

    if Self.whole(calories, in: 0...RecipeLimits.calories) == .invalid {
      errors.add(.calories, validation.wholeNumber(0, RecipeLimits.calories))
    }
    for (field, value) in [(Field.protein, protein), (.carbs, carbs), (.fat, fat)]
    where Self.grams(value) == .invalid {
      errors.add(field, validation.numberBetween(0, Double(RecipeLimits.grams)))
    }

    let link = trimmed(sourceURL)
    if !link.isEmpty {
      tooLong(.sourceURL, link, RecipeLimits.url)
      if link.range(of: #"^https?://[^\s/]+\S*$"#, options: [.regularExpression, .caseInsensitive])
        == nil
      {
        errors.add(.sourceURL, validation.link)
      }
    }

    for tag in tags {
      let name = trimmed(tag)
      if name.isEmpty { errors.add(.tags, validation.required) }
      tooLong(.tags, name, RecipeLimits.tag)
    }
    if tags.count > RecipeLimits.tags { errors.add(.tags, validation.tooMany(RecipeLimits.tags)) }

    if !ingredientsLocked { validateIngredients(into: &errors) }
    if !stepsLocked { validateSteps(into: &errors) }
    return errors
  }

  private func validateIngredients(into errors: inout Errors) {
    let validation = Copy.validation
    var lines = 0
    for row in ingredients where !row.isBlank || row.isHeading {
      if row.isHeading {
        if trimmed(row.text).count > RecipeLimits.section {
          errors.add(.ingredient(row.id), validation.tooLong(RecipeLimits.section))
        }
        continue
      }
      lines += 1
      guard let parsed = row.parsed else { continue }
      let field = Field.ingredient(row.id)
      if trimmed(parsed.item).isEmpty { errors.add(field, validation.required) }
      if trimmed(row.text).count > RecipeLimits.line {
        errors.add(field, validation.tooLong(RecipeLimits.line))
      }
      if parsed.item.count > RecipeLimits.item {
        errors.add(field, validation.tooLong(RecipeLimits.item))
      }
      if (parsed.note?.count ?? 0) > RecipeLimits.note {
        errors.add(field, validation.tooLong(RecipeLimits.note))
      }
      if !parsed.isValid {
        let range = parsed.quantity.map { ($0.max ?? $0.min) < $0.min } ?? false
        errors.add(field, range ? validation.range : validation.quantity)
      }
    }
    if lines > RecipeLimits.ingredients {
      errors.add(.ingredientList, validation.tooMany(RecipeLimits.ingredients))
    }
  }

  private func validateSteps(into errors: inout Errors) {
    let validation = Copy.validation
    var count = 0
    for step in steps where !step.isBlank {
      count += 1
      if trimmed(step.text).count > RecipeLimits.step {
        errors.add(.step(step.id), validation.tooLong(RecipeLimits.step))
      }
      if let seconds = step.timerSeconds, !(1...RecipeLimits.timerSeconds).contains(seconds) {
        errors.add(.step(step.id), validation.wholeNumber(1, RecipeLimits.timerSeconds))
      }
    }
    if count > RecipeLimits.steps { errors.add(.stepList, validation.tooMany(RecipeLimits.steps)) }
  }

  // MARK: Reading what was typed

  func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  enum Reading<Value: Equatable>: Equatable {
    case blank
    case value(Value)
    case invalid
  }

  /// A whole number in `range`, nil when blank, invalid when anything else.
  static func whole(_ text: String, in range: ClosedRange<Int>) -> Reading<Int> {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .blank }
    guard let number = Double(text), number.isFinite, number == number.rounded(),
      let whole = Int(exactly: number), range.contains(whole)
    else { return .invalid }
    return .value(whole)
  }

  /// A finite number from 0 to the grams limit.
  static func grams(_ text: String) -> Reading<Double> {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .blank }
    guard let number = Double(text), number.isFinite,
      (0...Double(RecipeLimits.grams)).contains(number)
    else { return .invalid }
    return .value(number)
  }
}
