public enum MealSlot: String, Sendable, Hashable, Codable, CaseIterable {
  case breakfast
  case lunch
  case dinner
  case snack
}

/// The recipe behind a plan entry, while it's live.
public struct PlanRecipe: Sendable, Hashable, Codable {
  public var id: RecipeId
  public var title: String
  public var servings: Int?
  /// Total time, or prep plus cook when the total isn't set.
  public var totalMinutes: Int?
  public var photoKey: String?
  /// Per serving.
  public var macros: Macros

  public init(
    id: RecipeId, title: String, servings: Int?, totalMinutes: Int?, photoKey: String?,
    macros: Macros
  ) {
    self.id = id
    self.title = title
    self.servings = servings
    self.totalMinutes = totalMinutes
    self.photoKey = photoKey
    self.macros = macros
  }
}

/// What's planned for one meal of one day: a recipe (with its own servings) or a free-text
/// meal like "Leftovers".
public struct PlanEntry: Sendable, Hashable, Codable {
  public var id: PlanEntryId
  public var date: LocalDate
  public var slot: MealSlot
  /// What the entry says: the free text, or the recipe's title when it was stirred in. Shown
  /// when the recipe has since been banished.
  public var title: String
  /// Nil for free text, and while the recipe is banished.
  public var recipe: PlanRecipe?
  /// Servings to cook; nil means the recipe's own.
  public var servings: Int?
  /// Order within the day's slot, from 0.
  public var position: Int
  /// The recipe was marked cooked on this entry's day.
  public var brewed: Bool

  public init(
    id: PlanEntryId, date: LocalDate, slot: MealSlot, title: String, recipe: PlanRecipe?,
    servings: Int?, position: Int, brewed: Bool
  ) {
    self.id = id
    self.date = date
    self.slot = slot
    self.title = title
    self.recipe = recipe
    self.servings = servings
    self.position = position
    self.brewed = brewed
  }
}
