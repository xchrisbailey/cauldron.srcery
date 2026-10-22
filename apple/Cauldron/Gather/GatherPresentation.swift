import CauldronKit
import Foundation

// What the Gather screens print, worked out apart from the views so it can be tested.

/// The aisles that hold something, in store order.
struct GatherSection: Identifiable, Equatable {
  let aisle: Aisle
  let items: [GatherItem]

  var id: Aisle { aisle }
  var title: CopyString { Copy.gather.aisles[aisle] }
}

/// A week's list as the screens read it: one line per item, in store order (by aisle, then by
/// item), with pantry marks applied.
struct GatherSnapshot {
  let start: LocalDate
  let items: [GatherItem]

  init(start: LocalDate, records: [GatherItemRecord], pantry: [PantryItemRecord]) {
    self.start = start
    let atHome = Set(pantry.map(\.itemKey))
    let ticked = GatherPlan.tickedKeys(records, week: start)
    items = sortRows(
      GatherPlan.shown(records, week: start).map { record in
        GatherItem(
          id: record.id, item: record.item, itemKey: record.itemKey, quantity: record.quantity,
          unit: record.unit, aisle: record.aisle ?? aisleFor(record.itemKey),
          checked: GatherPlan.isChecked(record, ticked: ticked), manual: record.manual,
          inPantry: atHome.contains(record.itemKey), sources: Self.sources(of: record))
      })
  }

  /// The recipes behind a line, by title. A source whose recipe hasn't arrived (or is gone) is
  /// left out, as the reference's join leaves it out.
  private static func sources(of record: GatherItemRecord) -> [GatherSource] {
    (record.sources ?? [])
      .compactMap { source in
        source.recipe.map {
          (
            id: source.id,
            GatherSource(
              recipeId: $0.id, title: $0.title, quantity: source.quantity, unit: source.unit)
          )
        }
      }
      .sorted { a, b in
        (a.1.title.lowercased(), a.id.uuidString) < (b.1.title.lowercased(), b.id.uuidString)
      }
      .map(\.1)
  }

  var isEmpty: Bool { items.isEmpty }
  var checkedCount: Int { items.filter(\.checked).count }
  var allChecked: Bool { !items.isEmpty && checkedCount == items.count }

  /// "3 of 12 gathered", or the line that says the shop is done.
  var progress: CopyString {
    allChecked ? Copy.gather.allChecked : Copy.gather.checked(checkedCount, items.count)
  }

  /// The aisles that hold something, in store order; `hidingChecked` leaves out items already
  /// ticked off.
  func sections(hidingChecked: Bool) -> [GatherSection] {
    let shown = hidingChecked ? items.filter { !$0.checked } : items
    return Aisle.allCases.compactMap { aisle in
      let here = shown.filter { $0.aisle == aisle }
      return here.isEmpty ? nil : GatherSection(aisle: aisle, items: here)
    }
  }
}

/// What one line of the list says.
struct GatherRowText: Equatable {
  /// The amount in Geist Mono and its unit beside it; nil for an item with no amount.
  let amount: String?
  let unit: String?
  let name: String
  /// "For Soup, Tacos", or that the cook added it.
  let detail: String
  /// Everything above as one phrase, for VoiceOver.
  let spoken: String

  init(_ item: GatherItem) {
    let measure = item.quantity.map { measureParts($0, unit: item.unit) }
    amount = measure?.amount
    unit = measure?.unit
    name = item.item
    detail =
      item.manual
      ? Copy.gather.addedByHand.text
      : Copy.gather.forRecipes(item.sources.map(\.title).joined(separator: ", ")).text
    spoken = [amount, unit, name, detail].compactMap { $0 }.joined(separator: ", ")
  }
}

/// What makes the list need rebuilding: the week and everything in its plan that the list is
/// built from. Two equal signatures need the same rows.
struct GatherSignature: Hashable {
  struct Part: Hashable {
    let entry: UUID
    let recipe: UUID?
    let servings: Int?
    let recipeServings: Int?
    let batchId: UUID?
    let ingredientYield: Int?
    let banished: Bool
    /// The stored ingredients, so an edit to a recipe's lines is seen.
    let ingredients: Int
  }

  let week: LocalDate
  let parts: [Part]

  init(week: LocalDate, entries: [PlanEntryRecord]) {
    self.week = week
    parts = WeekPlan.ordered(entries).map { entry in
      Part(
        entry: entry.id, recipe: entry.recipe?.id, servings: entry.servings,
        recipeServings: entry.recipe?.servings, batchId: entry.batch?.id,
        ingredientYield: entry.batch?.ingredientYield, banished: entry.recipe?.isBanished ?? false,
        ingredients: entry.recipe?.ingredientsData.hashValue ?? 0)
    }
  }
}
