import CauldronKit
import Foundation
import SwiftData

/// A weigh-in as the import sees it.
struct ExistingWeighIn: Equatable {
  var day: LocalDate
  var kg: Double
  /// The Health sample it came from; nil when it was typed in.
  var healthSampleID: String?
}

/// What to change in the weigh-ins so they match Health.
struct WeightImportPlan: Equatable {
  struct Change: Equatable {
    var day: LocalDate
    var kg: Double
    var sampleID: String
  }

  var insert: [Change] = []
  var update: [Change] = []
  /// Days whose imported weigh-in is gone from Health.
  var remove: [LocalDate] = []

  var isEmpty: Bool { insert.isEmpty && update.isEmpty && remove.isEmpty }
  var count: Int { insert.count + update.count + remove.count }
}

enum HealthWeightImport {
  /// Reads Health's body mass into one weigh-in a day.
  ///
  /// - A day with no weigh-in gets the day's latest reading (unless `dismissed` lists it: the
  ///   cook removed it from Cauldron).
  /// - A day whose weigh-in came from Health follows Health: a newer reading or a corrected one
  ///   replaces it, and one that is gone from Health is removed.
  /// - A day with a weigh-in typed in Cauldron is never touched, so nothing is duplicated and
  ///   nothing typed is overwritten.
  ///
  /// Only days in `window` are looked at, and readings outside what a weight can be are ignored.
  static func plan(
    samples: [HealthWeightSample], existing: [ExistingWeighIn], dismissed: Set<String>,
    window: ClosedRange<LocalDate>, calendar: Calendar = .current
  ) -> WeightImportPlan {
    // The day's latest reading; the id breaks a tie.
    var latest: [LocalDate: HealthWeightSample] = [:]
    for sample in samples {
      guard sample.kg.isFinite, TrackerLimits.weightKg.contains(sample.kg),
        let day = LocalDate(sample.date, in: calendar), window.contains(day)
      else { continue }
      if let held = latest[day], (held.date, held.id) >= (sample.date, sample.id) { continue }
      latest[day] = sample
    }

    let byDay = Dictionary(existing.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    var plan = WeightImportPlan()
    for day in latest.keys.sorted() {
      guard let sample = latest[day] else { continue }
      let kg = (sample.kg * 100).rounded() / 100
      let change = WeightImportPlan.Change(day: day, kg: kg, sampleID: sample.id)
      guard let held = byDay[day] else {
        if !dismissed.contains(sample.id) { plan.insert.append(change) }
        continue
      }
      guard let heldID = held.healthSampleID else { continue }
      if heldID != sample.id {
        if !dismissed.contains(sample.id) { plan.update.append(change) }
      } else if abs(held.kg - kg) > 0.001 {
        plan.update.append(change)
      }
    }
    for held in existing where held.healthSampleID != nil && window.contains(held.day) {
      if latest[held.day] == nil { plan.remove.append(held.day) }
    }
    plan.remove = Array(Set(plan.remove)).sorted()
    return plan
  }

  /// The weigh-ins in `window` as the import sees them (one a day, by the keeper rule).
  @MainActor
  static func existing(in window: ClosedRange<LocalDate>, context: ModelContext) throws
    -> [ExistingWeighIn]
  {
    let from = window.lowerBound.description
    let to = window.upperBound.description
    let rows = try context.fetch(
      FetchDescriptor<WeighInRecord>(predicate: #Predicate { $0.dayKey >= from && $0.dayKey <= to })
    )
    let days = Set(rows.compactMap(\.day))
    return try days.sorted().compactMap { day in
      try context.weighIn(on: day).map {
        ExistingWeighIn(day: day, kg: $0.weightKg, healthSampleID: $0.healthSampleID)
      }
    }
  }

  /// Makes the plan so, and saves.
  @MainActor
  static func apply(_ plan: WeightImportPlan, in context: ModelContext) throws {
    guard !plan.isEmpty else { return }
    for change in plan.insert + plan.update {
      if let row = try context.weighIn(on: change.day) {
        row.weightKg = change.kg
        row.healthSampleID = change.sampleID
      } else {
        let row = WeighInRecord(day: change.day, weightKg: change.kg)
        row.healthSampleID = change.sampleID
        context.insert(row)
      }
    }
    for day in plan.remove {
      if let row = try context.weighIn(on: day), row.healthSampleID != nil {
        context.delete(row)
      }
    }
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
}
