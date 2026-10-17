import CauldronKit
import Testing

/// Every enum's raw values are the TypeScript string literals, in the same order, so data
/// written by the web app, and the JSON contract of a future export, read the same.
struct EnumCase: Sendable {
  let name: String
  let rawValues: [String]
  let expected: [String]

  init<E: RawRepresentable & CaseIterable>(_ type: E.Type, _ expected: [String])
  where E.RawValue == String {
    self.name = String(describing: type)
    self.rawValues = E.allCases.map(\.rawValue)
    self.expected = expected
  }
}

@Suite("Enum raw values match the TypeScript literals")
struct EnumRawValueTests {
  static let cases: [EnumCase] = [
    .init(
      UnitCode.self,
      [
        "tsp", "tbsp", "cup", "fl_oz", "pint", "quart", "gallon", "ml", "l", "g", "kg", "oz", "lb",
        "pinch", "dash", "clove", "can", "slice", "bunch", "sprig", "stick", "piece", "package",
      ]),
    .init(MealSlot.self, ["breakfast", "lunch", "dinner", "snack"]),
    .init(
      Aisle.self,
      ["produce", "meat", "dairy", "bakery", "pantry", "spices", "frozen", "drinks", "other"]),
    .init(SourcePlatform.self, ["web", "instagram", "tiktok", "manual", "text"]),
    .init(TagKind.self, ["cuisine", "meal", "diet", "other"]),
    .init(MacroKey.self, ["calories", "protein", "carbs", "fat"]),
    .init(DiarySource.self, ["described", "recipe", "manual"]),
    .init(Sex.self, ["female", "male", "unspecified"]),
    .init(ActivityLevel.self, ["sedentary", "light", "moderate", "active", "veryActive"]),
    .init(Goal.self, ["lose", "maintain", "gain"]),
    .init(WeightUnit.self, ["kg", "lb"]),
    .init(HeightUnit.self, ["cm", "ftin"]),
    .init(ImportSource.self, ["web", "instagram", "tiktok", "text"]),
    .init(ImportStatus.self, ["queued", "running", "done", "failed", "cancelled", "saved"]),
    .init(
      ImportFailureCode.self,
      ["couldntRead", "noRecipe", "spokenOnly", "tooLarge", "blocked", "timeout", "unavailable"]),
    .init(
      DraftField.self,
      [
        "title", "description", "servings", "prepMinutes", "cookMinutes", "totalMinutes", "macros",
        "sourceUrl", "tags", "notes",
      ]),
  ]

  @Test("has exactly the literals, in order", arguments: cases)
  func rawValues(_ c: EnumCase) {
    #expect(c.rawValues == c.expected, "\(c.name)")
  }

  @Test func unknownRawValuesAreRejected() {
    #expect(UnitCode(rawValue: "furlong") == nil)
    #expect(Aisle(rawValue: "Produce") == nil)
    #expect(MealSlot(rawValue: "brunch") == nil)
  }
}
