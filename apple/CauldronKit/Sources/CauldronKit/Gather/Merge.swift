import Foundation

// Merging the week's ingredient lines into a shopping list (`gather/merge.ts`).
//
// Lines merge when they share an item key (`ingredientKey`) and can be added up: volumes with
// volumes and masses with masses (converted through ml or g), bare counts with bare counts
// ("2 onions" + "1 onion"), and count units only with the same unit ("3 cloves" + "4 cloves",
// never cloves + heads). Cups and grams of the same thing stay as two rows, since there's no
// density to convert between them. A line with no amount ("salt, to taste") joins an
// amount-carrying row for the same item when there is one, and is its own row otherwise.

/// One ingredient line from a planned recipe, already scaled by the entry's servings.
public struct GatherLine: Sendable, Hashable {
  public var recipeId: RecipeId
  public var item: String
  public var itemKey: String
  public var quantity: Quantity?
  public var unit: UnitCode?

  public init(
    recipeId: RecipeId, item: String, itemKey: String, quantity: Quantity?, unit: UnitCode?
  ) {
    self.recipeId = recipeId
    self.item = item
    self.itemKey = itemKey
    self.quantity = quantity
    self.unit = unit
  }
}

/// How much one recipe contributes to a row.
public struct GatherContribution: Sendable, Hashable {
  public var recipeId: RecipeId
  public var quantity: Quantity?
  public var unit: UnitCode?

  public init(recipeId: RecipeId, quantity: Quantity?, unit: UnitCode?) {
    self.recipeId = recipeId
    self.quantity = quantity
    self.unit = unit
  }
}

public struct GatheredRow: Sendable, Hashable {
  /// Item key plus how it adds up; stable across regenerations.
  public var mergeKey: String
  public var itemKey: String
  /// The item as most of the recipes write it.
  public var item: String
  public var quantity: Quantity?
  public var unit: UnitCode?
  public var aisle: Aisle
  public var sources: [GatherContribution]

  public init(
    mergeKey: String, itemKey: String, item: String, quantity: Quantity?, unit: UnitCode?,
    aisle: Aisle, sources: [GatherContribution]
  ) {
    self.mergeKey = mergeKey
    self.itemKey = itemKey
    self.item = item
    self.quantity = quantity
    self.unit = unit
    self.aisle = aisle
    self.sources = sources
  }
}

/// How a measure adds up: "volume", "mass", "count" (bare), "unit:clove", or "none".
public func measureGroup(_ quantity: Quantity?, _ unit: UnitCode?) -> String {
  // A unit with no amount adds nothing, the same as no unit.
  guard quantity != nil else { return "none" }
  guard let unit else { return "count" }
  switch unit.dimension {
  case .count: return "unit:\(unit.rawValue)"
  case .volume: return "volume"
  case .mass: return "mass"
  }
}

public func mergeKeyOf(_ itemKey: String, _ quantity: Quantity?, _ unit: UnitCode?) -> String {
  "\(itemKey)|\(measureGroup(quantity, unit))"
}

/// A line's amount in the group's base unit (ml, g, or the count itself).
private func toBase(_ q: Quantity, _ unit: UnitCode?) -> Quantity {
  let factor = unit?.factor ?? 1
  return Quantity(min: q.min * factor, max: q.max.map { $0 * factor })
}

private func sum(_ quantities: [Quantity]) -> Quantity {
  let ranged = quantities.contains { $0.max != nil }
  return Quantity(
    min: quantities.reduce(0) { $0 + $1.min },
    max: ranged ? quantities.reduce(0) { $0 + ($1.max ?? $1.min) } : nil)
}

private struct Total {
  var quantity: Quantity?
  var unit: UnitCode?
}

/// The total for a group of lines, in the unit they share, or a sensible one when they differ.
private func total(_ lines: [GatherLine]) -> Total {
  let measured = lines.compactMap { line in line.quantity.map { (quantity: $0, unit: line.unit) } }
  guard let first = measured.first else { return Total(quantity: nil, unit: nil) }
  if measured.allSatisfy({ $0.unit == first.unit }) {
    return Total(quantity: sum(measured.map(\.quantity)), unit: first.unit)
  }
  // Mixed volume or mass units: add in ml or g, then show in the cook's system (US if any line
  // used US units), in the unit a shopper reads best.
  let base = sum(measured.map { toBase($0.quantity, $0.unit) })
  guard let firstUnit = first.unit else {
    return Total(quantity: sum(measured.map(\.quantity)), unit: nil)
  }
  let volume = firstUnit.dimension == .volume
  let us = measured.contains { $0.unit?.system == .us }
  let shown = shoppingUnit(base.max ?? base.min, volume: volume, us: us)
  let per = shown.factor
  return Total(
    quantity: Quantity(min: base.min / per, max: base.max.map { $0 / per }), unit: shown)
}

/// The unit for a merged total, from its amount in ml or g: litres and kilograms from 1000,
/// pounds from 1 lb, and cups for US volumes from a quarter cup (a list reads "4 ¼ cups", not
/// "1.06 quarts").
private func shoppingUnit(_ amount: Double, volume: Bool, us: Bool) -> UnitCode {
  if !us { return amount >= 1000 ? (volume ? .l : .kg) : (volume ? .ml : .g) }
  if !volume { return amount >= UnitCode.lb.factor ? .lb : .oz }
  if amount >= UnitCode.cup.factor / 4 { return .cup }
  return convertForDisplay(amount, unit: .ml, target: .us).unit
}

/// The most common way the item is written, first seen winning a tie.
private func commonName(_ lines: [GatherLine]) -> String {
  var order: [String] = []
  var counts: [String: Int] = [:]
  for line in lines {
    if counts[line.item] == nil { order.append(line.item) }
    counts[line.item, default: 0] += 1
  }
  var best = lines[0].item
  for name in order where counts[name, default: 0] > counts[best, default: 0] { best = name }
  return best
}

/// Merges lines into rows, grouped by aisle in store order and then by item.
public func gatherLines(_ lines: [GatherLine]) -> [GatheredRow] {
  // Insertion-ordered groups, as a JavaScript `Map` keeps them.
  var keys: [String] = []
  var groups: [String: [GatherLine]] = [:]
  for line in lines {
    let key = mergeKeyOf(line.itemKey, line.quantity, line.unit)
    if groups[key] == nil { keys.append(key) }
    groups[key, default: []].append(line)
  }
  // Amount-less lines join a measured row for the same item, if any.
  for key in keys where key.hasSuffix("|none") {
    guard let list = groups[key] else { continue }
    let itemKey = String(key.dropLast("|none".count))
    if let host = keys.first(where: {
      $0 != key && groups[$0] != nil && $0.hasPrefix("\(itemKey)|")
    }) {
      groups[host, default: []].append(contentsOf: list)
      groups[key] = nil
    }
  }
  var rows: [GatheredRow] = []
  for mergeKey in keys {
    guard let list = groups[mergeKey], let first = list.first else { continue }
    var recipeOrder: [RecipeId] = []
    var byRecipe: [RecipeId: [GatherLine]] = [:]
    for line in list {
      if byRecipe[line.recipeId] == nil { recipeOrder.append(line.recipeId) }
      byRecipe[line.recipeId, default: []].append(line)
    }
    let all = total(list)
    rows.append(
      GatheredRow(
        mergeKey: mergeKey, itemKey: first.itemKey, item: commonName(list),
        quantity: all.quantity, unit: all.unit, aisle: aisleFor(first.itemKey),
        sources: recipeOrder.map { recipeId in
          let own = total(byRecipe[recipeId] ?? [])
          return GatherContribution(recipeId: recipeId, quantity: own.quantity, unit: own.unit)
        }))
  }
  return sortRows(rows)
}

/// An ingredient line of a planned recipe, as written.
public struct PlannedIngredient: Sendable, Hashable {
  public var item: String
  public var itemKey: String
  public var quantity: Quantity?
  public var unit: UnitCode?

  public init(item: String, itemKey: String, quantity: Quantity?, unit: UnitCode?) {
    self.item = item
    self.itemKey = itemKey
    self.quantity = quantity
    self.unit = unit
  }
}

/// A recipe planned on a day of the week, with its ingredients as written.
public struct PlannedEntry: Sendable, Hashable {
  public var recipeId: RecipeId
  /// What the recipe makes, and what the entry asks for; either may be unset.
  public var recipeServings: Int?
  public var servings: Int?
  public var ingredients: [PlannedIngredient]

  public init(
    recipeId: RecipeId, recipeServings: Int?, servings: Int?, ingredients: [PlannedIngredient]
  ) {
    self.recipeId = recipeId
    self.recipeServings = recipeServings
    self.servings = servings
    self.ingredients = ingredients
  }
}

/// The week's rows: every entry's lines scaled by its servings, then merged.
public func gatherWeek(_ entries: [PlannedEntry]) -> [GatheredRow] {
  gatherLines(
    entries.flatMap { entry in
      let factor = servingFactor(recipeServings: entry.recipeServings, wanted: entry.servings)
      return entry.ingredients.map { ingredient in
        GatherLine(
          recipeId: entry.recipeId, item: ingredient.item, itemKey: ingredient.itemKey,
          quantity: ingredient.quantity.map { scaleQuantity($0, by: factor) },
          unit: ingredient.unit)
      }
    })
}

/// A gathered row as the list holds it now.
public struct ExistingGatherRow: Sendable, Hashable {
  public var id: GatherItemId
  public var item: String
  public var itemKey: String
  public var quantity: Quantity?
  public var unit: UnitCode?
  public var aisle: Aisle?
  public var checked: Bool
  public var sources: [GatherContribution]

  public init(
    id: GatherItemId, item: String, itemKey: String, quantity: Quantity?, unit: UnitCode?,
    aisle: Aisle?, checked: Bool, sources: [GatherContribution]
  ) {
    self.id = id
    self.item = item
    self.itemKey = itemKey
    self.quantity = quantity
    self.unit = unit
    self.aisle = aisle
    self.checked = checked
    self.sources = sources
  }
}

/// A row still needed, and what about it changed.
public struct GatherUpdate: Sendable, Hashable {
  public var id: GatherItemId
  /// The row as it should now read, its amounts rounded as stored.
  public var row: GatheredRow
  /// Its item, amount, unit or aisle changed.
  public var changed: Bool
  /// It was checked and the week now needs more, so it's unchecked.
  public var uncheck: Bool
  /// Its per-recipe amounts changed.
  public var sources: Bool

  public init(id: GatherItemId, row: GatheredRow, changed: Bool, uncheck: Bool, sources: Bool) {
    self.id = id
    self.row = row
    self.changed = changed
    self.uncheck = uncheck
    self.sources = sources
  }
}

public struct Reconciled: Sendable, Hashable {
  public var inserts: [GatheredRow]
  public var updates: [GatherUpdate]
  /// Ids of rows no longer needed, or that repeat a merge key.
  public var removals: [GatherItemId]

  public init(inserts: [GatheredRow], updates: [GatherUpdate], removals: [GatherItemId]) {
    self.inserts = inserts
    self.updates = updates
    self.removals = removals
  }
}

/// The most of a measure, in ml or g for volumes and masses, for spotting "needs more".
private func most(_ q: Quantity?, _ unit: UnitCode?) -> Double {
  guard let q else { return 0 }
  let base = toBase(q, unit)
  return base.max ?? base.min
}

/// A contribution as it was compared: amounts that JSON can't hold (NaN, infinity) read as
/// absent, as `JSON.stringify` had them.
private struct SourceSignature: Hashable {
  var recipeId: RecipeId
  var min: Double?
  var max: Double?
  var unit: UnitCode?

  init(_ source: GatherContribution) {
    func finite(_ x: Double?) -> Double? { x.flatMap { $0.isFinite ? $0 : nil } }
    recipeId = source.recipeId
    min = finite(source.quantity?.min)
    max = finite(source.quantity?.max)
    unit = source.unit
  }
}

private func signatures(_ sources: [GatherContribution]) -> [SourceSignature] {
  // A stable sort by recipe, so the order they were read in doesn't matter.
  sources.map(SourceSignature.init).enumerated()
    .sorted {
      ($0.element.recipeId.uuidString, $0.offset) < ($1.element.recipeId.uuidString, $1.offset)
    }
    .map(\.element)
}

/// What it takes to bring the gathered rows in line with the week's: rows still needed are
/// updated in place (keeping their check, unless the week now needs more), new ones are added,
/// and the rest are removed, along with any row that repeats another's merge key. `round` is
/// how storage rounds an amount; wanted amounts are compared as they'd be stored, so a 1/3
/// that rounds down doesn't read as changed, or as "more", on every sync.
public func reconcile(
  existing: [ExistingGatherRow], wanted: [GatheredRow], round: (Double) -> Double
) -> Reconciled {
  func rounded(_ q: Quantity?) -> Quantity? {
    q.map { Quantity(min: round($0.min), max: $0.max.map(round)) }
  }
  var keyOrder: [String] = []
  var byKey: [String: ExistingGatherRow] = [:]
  var removals: [GatherItemId] = []
  for row in existing {
    let key = mergeKeyOf(row.itemKey, row.quantity, row.unit)
    if byKey[key] != nil {
      removals.append(row.id)
    } else {
      byKey[key] = row
      keyOrder.append(key)
    }
  }
  var inserts: [GatheredRow] = []
  var updates: [GatherUpdate] = []
  for want in wanted {
    var row = want
    row.quantity = rounded(want.quantity)
    row.sources = want.sources.map {
      GatherContribution(recipeId: $0.recipeId, quantity: rounded($0.quantity), unit: $0.unit)
    }
    guard let found = byKey[row.mergeKey] else {
      inserts.append(row)
      continue
    }
    byKey[row.mergeKey] = nil
    let grew = most(row.quantity, row.unit) > most(found.quantity, found.unit) * (1 + 1e-9)
    let changed =
      found.item != row.item || found.quantity?.min != row.quantity?.min
      || found.quantity?.max != row.quantity?.max || found.unit != row.unit
      || found.aisle != row.aisle
    let uncheck = grew && found.checked
    let sources = signatures(row.sources) != signatures(found.sources)
    if changed || uncheck || sources {
      updates.append(
        GatherUpdate(id: found.id, row: row, changed: changed, uncheck: uncheck, sources: sources))
    }
  }
  removals += keyOrder.compactMap { byKey[$0]?.id }
  return Reconciled(inserts: inserts, updates: updates, removals: removals)
}

/// Anything that sits in an aisle and has a name, so a list can be put in store order.
public protocol AisleSortable {
  var aisle: Aisle { get }
  var item: String { get }
}

extension GatheredRow: AisleSortable {}
extension GatherItem: AisleSortable {}

/// Store order: by aisle, then alphabetically by item.
public func sortRows<Row: AisleSortable>(_ rows: [Row]) -> [Row] {
  rows.enumerated().sorted { a, b in
    let byAisle = a.element.aisle.storeOrder - b.element.aisle.storeOrder
    if byAisle != 0 { return byAisle < 0 }
    let byName = compareBase(a.element.item, b.element.item)
    return byName != 0 ? byName < 0 : a.offset < b.offset
  }.map(\.element)
}
