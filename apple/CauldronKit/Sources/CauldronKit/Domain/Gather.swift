/// Store aisles for the Gather list, in store order (`AISLES` in `gather/aisles.ts`). The
/// item-to-aisle lookup is a separate port.
public enum Aisle: String, Sendable, Hashable, Codable, CaseIterable {
  case produce
  case meat
  case dairy
  case bakery
  case pantry
  case spices
  case frozen
  case drinks
  case other
}

/// One recipe that needs a Gather item, and how much of it.
public struct GatherSource: Sendable, Hashable, Codable {
  public var recipeId: RecipeId
  public var title: String
  public var quantity: Quantity?
  public var unit: UnitCode?

  public init(recipeId: RecipeId, title: String, quantity: Quantity?, unit: UnitCode?) {
    self.recipeId = recipeId
    self.title = title
    self.quantity = quantity
    self.unit = unit
  }
}

public struct GatherItem: Sendable, Hashable, Codable {
  public var id: GatherItemId
  public var item: String
  public var itemKey: String
  public var quantity: Quantity?
  public var unit: UnitCode?
  public var aisle: Aisle
  public var checked: Bool
  /// Added by hand rather than gathered from the week.
  public var manual: Bool
  /// Marked as already in the pantry; remembered for this item in every week.
  public var inPantry: Bool
  public var sources: [GatherSource]

  public init(
    id: GatherItemId, item: String, itemKey: String, quantity: Quantity?, unit: UnitCode?,
    aisle: Aisle, checked: Bool, manual: Bool, inPantry: Bool, sources: [GatherSource]
  ) {
    self.id = id
    self.item = item
    self.itemKey = itemKey
    self.quantity = quantity
    self.unit = unit
    self.aisle = aisle
    self.checked = checked
    self.manual = manual
    self.inPantry = inPantry
    self.sources = sources
  }
}

/// A week's shopping list, built from the planned recipes and kept in step with the week,
/// plus items added by hand.
public struct GatherList: Sendable, Hashable, Codable {
  /// The first day of the week; the list covers it and the six days after.
  public var weekStart: LocalDate
  /// Planned recipes the list was gathered from.
  public var recipeCount: Int
  /// In store order: by aisle, then by item.
  public var items: [GatherItem]

  public init(weekStart: LocalDate, recipeCount: Int, items: [GatherItem]) {
    self.weekStart = weekStart
    self.recipeCount = recipeCount
    self.items = items
  }
}
