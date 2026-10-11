import CauldronKit
import Foundation
import Observation
import SwiftData

/// Keeps Cauldron and Health in step: weigh-ins come in from Health, and the diary goes out to
/// Health's nutrition data. It does nothing until the cook connects Health in Settings, and the
/// connection is a choice of this device (kept in `UserDefaults`), since only the iPhone has Health.
///
/// Writes go out in the order they were made, one at a time, and a failure is remembered for
/// Settings to show without ever stopping a diary change.
@MainActor
@Observable
final class HealthSync {
  enum Status: Equatable {
    /// This build lacks what asking for Health needs (see `HealthSetup`).
    case notSetUp
    /// This device has no Health.
    case unavailable
    /// Available, not connected.
    case off
    case on
  }

  static let shared = HealthSync(store: HealthSync.liveStore, setup: .thisBuild)

  static let enabledKey = "health.enabled"
  static let dismissedKey = "health.dismissedWeightSamples"

  /// Health's samples are looked at for this many days back.
  static let importDays = 365

  private let store: any HealthStore
  private let setup: HealthSetup
  private let defaults: UserDefaults
  private let calendar: Calendar
  private var tail: Task<Void, Never>?
  private var enabled: Bool
  /// The last version sent, so two saves in a millisecond still rise.
  private var lastVersion = 0

  /// What Settings says after the last attempt; nil when all went well.
  private(set) var failure: CopyString?
  /// How many weigh-ins the last check changed.
  private(set) var lastImportCount: Int?

  init(
    store: any HealthStore, setup: HealthSetup, defaults: UserDefaults = .standard,
    calendar: Calendar = .current
  ) {
    self.store = store
    self.setup = setup
    self.defaults = defaults
    self.calendar = calendar
    enabled = defaults.bool(forKey: Self.enabledKey)
  }

  private static var liveStore: any HealthStore {
    #if os(iOS)
      LiveHealthStore()
    #else
      UnavailableHealthStore()
    #endif
  }

  var status: Status {
    guard setup.isConfigured else { return .notSetUp }
    guard store.availability == .supported else { return .unavailable }
    return enabled ? .on : .off
  }

  /// Asks for access, and connects when it is given.
  func connect() async {
    guard status == .off else { return }
    do {
      try await store.requestAuthorization()
      enabled = true
      defaults.set(true, forKey: Self.enabledKey)
      failure = nil
    } catch {
      failure = Copy.settings.health.couldntConnect
    }
  }

  /// Stops reading and writing. What is already in Health stays there.
  func disconnect() {
    enabled = false
    defaults.set(false, forKey: Self.enabledKey)
    failure = nil
  }

  // MARK: Weigh-ins in

  /// Weigh-in sample ids the cook removed from Cauldron, so the next check doesn't bring them
  /// back.
  var dismissedSampleIDs: Set<String> {
    Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
  }

  func dismiss(sampleID: String) {
    var ids = dismissedSampleIDs
    ids.insert(sampleID)
    defaults.set(Array(ids).sorted(), forKey: Self.dismissedKey)
  }

  /// Brings Health's weights into the weigh-ins (see `HealthWeightImport`). Returns how many
  /// weigh-ins changed.
  @discardableResult
  func importWeights(into context: ModelContext, today: LocalDate) async -> Int {
    guard status == .on else { return 0 }
    let window = today.adding(days: -Self.importDays)...today
    guard let since = window.lowerBound.date(in: calendar) else { return 0 }
    do {
      let samples = try await store.bodyMass(since: since)
      let existing = try HealthWeightImport.existing(in: window, context: context)
      let plan = HealthWeightImport.plan(
        samples: samples, existing: existing, dismissed: dismissedSampleIDs, window: window,
        calendar: calendar)
      try HealthWeightImport.apply(plan, in: context)
      lastImportCount = plan.count
      failure = nil
      return plan.count
    } catch {
      failure = Copy.settings.health.couldntConnect
      return 0
    }
  }

  // MARK: Diary out

  /// Entries were added or changed: bring their samples up to date.
  func entriesSaved(_ entries: [HealthEntry]) {
    guard status == .on, !entries.isEmpty else { return }
    let plans = entries.map { HealthNutrition.plan(for: $0, calendar: calendar) }
    send(plans)
  }

  /// Entries were deleted: take their samples out.
  func entriesRemoved(_ ids: [UUID]) {
    guard status == .on, !ids.isEmpty else { return }
    send(ids.map(HealthNutrition.removal(of:)))
  }

  private func send(_ plans: [NutritionPlan]) {
    let samples = plans.flatMap(\.save)
    let deletes = plans.flatMap(\.delete)
    let version = max(lastVersion + 1, Int(Date.now.timeIntervalSince1970 * 1000))
    lastVersion = version
    let previous = tail
    tail = Task { [store] in
      await previous?.value
      do {
        if !deletes.isEmpty { try await store.deleteNutrition(syncIDs: deletes) }
        if !samples.isEmpty { try await store.save(samples, version: version) }
        self.failure = nil
      } catch {
        self.failure = Copy.settings.health.couldntUpdate
      }
    }
  }

  /// Waits for the writes made so far to finish.
  func settle() async {
    await tail?.value
  }
}
