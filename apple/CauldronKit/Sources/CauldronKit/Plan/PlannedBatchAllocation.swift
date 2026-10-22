import Foundation

/// A stored batch assignment reduced to the values needed to assess its allocation.
public struct PlannedBatchAssignment: Sendable, Equatable {
  public let day: LocalDate?
  public let servings: Int?

  public init(day: LocalDate?, servings: Int?) {
    self.day = day
    self.servings = servings
  }
}

/// The allocation state derived from a saved batch and its assignments.
public struct PlannedBatchAllocation: Sendable, Equatable {
  public let assigned: Int
  public let total: Int
  public let unassigned: Int
  public let isOverAssigned: Bool
  public let hasInvalidEntries: Bool

  public init(
    assignments: [PlannedBatchAssignment], weekStart: LocalDate?, total: Int,
    servingLimit: Int
  ) {
    assigned = assignments.compactMap(\.servings).reduce(0, +)
    self.total = total
    unassigned = max(0, total - assigned)
    isOverAssigned = assigned > total
    hasInvalidEntries = assignments.contains { assignment in
      guard let day = assignment.day, let servings = assignment.servings,
        let weekStart
      else { return true }
      return
        servingLimit < 1 || !weekStart.weekDays().contains(day)
        || !(1...servingLimit).contains(servings)
    }
  }

  public static func accepts(
    day: LocalDate, servings: Int, weekStart: LocalDate, servingLimit: Int
  ) -> Bool {
    servingLimit > 0 && weekStart.weekDays().contains(day)
      && (1...servingLimit).contains(servings)
  }
}
