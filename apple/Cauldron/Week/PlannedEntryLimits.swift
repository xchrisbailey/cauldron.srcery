import CauldronKit

/// The edit bounds for one persisted batch assignment.
struct PlannedEntryLimits: Equatable {
  let days: [LocalDate]
  let maxServings: Int

  init(batch: PlannedBatchRecord, entry: PlanEntryRecord, records: [PlanEntryRecord]) {
    days = batch.weekStart?.weekDays() ?? []
    let assignedElsewhere =
      records
      .filter { $0.batch === batch && $0 !== entry }
      .compactMap(\.servings)
      .reduce(0, +)
    maxServings = min(WeekLimits.servings, max(0, batch.totalServings - assignedElsewhere))
  }

  func allows(day: LocalDate, servings: Int?) -> Bool {
    days.contains(day)
      && servings.map { (1...WeekLimits.servings).contains($0) && $0 <= maxServings } == true
  }
}
